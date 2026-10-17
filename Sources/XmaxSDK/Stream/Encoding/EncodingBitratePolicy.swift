//
//  EncodingBitratePolicy.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 上下行共用的编码码率预算。
enum EncodingBitratePolicy {
    static func resolve(_ videoFormat: RealtimeVideoFormat) throws -> (minimum: Int, maximum: Int) {
        try videoFormat.validate()
        let minimum: Int
        let maximum: Int
        if let minimumBitrate = videoFormat.minimumBitrate,
           let maximumBitrate = videoFormat.maximumBitrate {
            minimum = minimumBitrate
            maximum = maximumBitrate
        } else {
            let maximumBitrate = (resolveMaximumBitrate(
                pixels: Double(videoFormat.width) * Double(videoFormat.height),
                fps: Double(videoFormat.fps)
            ) * 0.6).rounded(.toNearestOrEven)
            guard maximumBitrate.isFinite, maximumBitrate < Double(Int.max) else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Realtime video format exceeds the supported bitrate range"
                )
            }
            let defaultMaximum = max(100, Int(maximumBitrate))
            minimum = videoFormat.minimumBitrate ?? 100
            maximum = videoFormat.maximumBitrate ?? defaultMaximum
        }

        guard minimum <= maximum else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Minimum bitrate must not exceed maximum bitrate after applying SDK defaults"
            )
        }

        return (minimum, maximum)
    }
}

// 根据编码参数参考表，按上传像素面积和帧率插值计算最高码率预算。
// 默认最低码率为 100kbps；最高码率采用画质优先参考值的 0.6 倍，且不低于 100kbps。
// 表外规格按参考比例外推。
// 参考：https://docs.byteplus.com/id/docs/byteplus-rtc/docs-70122
private extension EncodingBitratePolicy {
    typealias BitratePoint = (value: Double, bitrate: Double)

    // 流畅优先码率参考，按像素面积升序排列，单位为 kbps。
    static let referenceBitratesAt15FPS: [BitratePoint] = [
        (120 * 120, 50),
        (160 * 120, 65),
        (180 * 180, 100),
        (240 * 180, 120),
        (320 * 180, 140),
        (320 * 240, 200),
        (424 * 240, 220),
        (360 * 360, 260),
        (480 * 360, 320),
        (640 * 360, 400),
        (640 * 480, 500),
        (848 * 480, 610),
        (960 * 720, 910),
        (1280 * 720, 1130),
        (1920 * 1080, 2080)
    ]

    static let referenceBitratesAt30FPS: [BitratePoint] = [
        (360 * 360, 400),
        (480 * 360, 490),
        (640 * 360, 600),
        (640 * 480, 750),
        (848 * 480, 930),
        (960 * 720, 1380),
        (1280 * 720, 1710),
        (1920 * 1080, 3150)
    ]

    static func resolveMaximumBitrate(pixels: Double, fps: Double) -> Double {
        let bitrate15 = interpolate(pixels, points: referenceBitratesAt15FPS)
        let bitrate30: Double
        let first30 = referenceBitratesAt30FPS[0]
        if pixels < first30.value {
            // 小尺寸沿用 15fps 的尺寸曲线，衔接 30fps 的首个参考点。
            let reference15 = interpolate(first30.value, points: referenceBitratesAt15FPS)
            bitrate30 = bitrate15 * (first30.bitrate / reference15)
        } else {
            bitrate30 = interpolate(pixels, points: referenceBitratesAt30FPS)
        }

        // 10fps 以 640×480 的 400kbps 为参考，沿用 15fps 的尺寸曲线。
        let bitrate10 = bitrate15 * (400.0 / 500)
        // 60fps 沿用 30fps 的尺寸曲线，匹配 1080p 的最高码率参考值。
        let maximum60 = bitrate30 * (6500.0 / 3150)
        return interpolate(fps, points: [
            (10, bitrate10 * 2), (15, bitrate15 * 2), (30, bitrate30 * 2), (60, maximum60)
        ])
    }

    /// 在相邻参考点间线性插值，表外按最近端点的比例外推。
    static func interpolate(_ value: Double, points: [BitratePoint]) -> Double {
        let first = points[0]
        if value <= first.value {
            return first.bitrate * (value / first.value)
        }
        for index in 1..<points.count {
            let upper = points[index]
            if value <= upper.value {
                let lower = points[index - 1]
                let ratio = (value - lower.value) / (upper.value - lower.value)
                return lower.bitrate + (upper.bitrate - lower.bitrate) * ratio
            }
        }
        let last = points[points.count - 1]
        return last.bitrate * (value / last.value)
    }
}
