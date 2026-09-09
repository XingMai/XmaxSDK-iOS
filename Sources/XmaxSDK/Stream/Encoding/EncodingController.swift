/// 根据实时视频格式配置 RTC 视频编码参数。
final class EncodingController: EncodingControlling, Sendable {

    // 基础层组件
    private let rtcManager: any RtcManaging

    init(rtcManager: any RtcManaging) {
        self.rtcManager = rtcManager
    }

    func configure(_ videoFormat: RealtimeVideoFormat) throws {
        try videoFormat.validate()

        let minimum: Int
        let maximum: Int
        if let minimumBitrate = videoFormat.minimumBitrate,
           let maximumBitrate = videoFormat.maximumBitrate {
            minimum = minimumBitrate
            maximum = maximumBitrate
        } else {
            let bitrates = Self.resolveBitrates(
                pixels: Double(videoFormat.width) * Double(videoFormat.height),
                fps: Double(videoFormat.fps)
            )
            let minimumBitrate = bitrates.minimum.rounded()
            let maximumBitrate = bitrates.maximum.rounded()
            guard maximumBitrate.isFinite, maximumBitrate < Double(Int.max) else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Realtime video format exceeds the supported bitrate range"
                )
            }
            let defaultMinimum = max(1, Int(minimumBitrate))
            let defaultMaximum = max(defaultMinimum + 1, Int(maximumBitrate))
            minimum = videoFormat.minimumBitrate ?? defaultMinimum
            maximum = videoFormat.maximumBitrate ?? defaultMaximum
        }

        guard minimum <= maximum else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Minimum bitrate must not exceed maximum bitrate after applying SDK defaults"
            )
        }

        let encoderPreference: VideoEncodingConfiguration.EncoderPreference = switch videoFormat.encoderPreference {
            case .auto: .auto
            case .maintainFramerate: .maintainFramerate
            case .maintainQuality: .maintainQuality
        }

        try rtcManager.configureVideoEncoding(
            VideoEncodingConfiguration(
                width: videoFormat.width,
                height: videoFormat.height,
                frameRate: videoFormat.fps,
                minimumBitrate: minimum,
                maximumBitrate: maximum,
                encoderPreference: encoderPreference
            )
        )
    }
}

// 根据官方编码参数参考表，按上传像素面积和帧率插值计算码率范围。
// 流畅优先推荐值用于最低码率，画质优先推荐值用于最高码率；表外规格按参考比例外推。
// 参考：https://docs.byteplus.com/id/docs/byteplus-rtc/docs-70122
private extension EncodingController {
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

    static func resolveBitrates(pixels: Double, fps: Double) -> (minimum: Double, maximum: Double) {
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
        // 60fps 沿用 30fps 的尺寸曲线，分别匹配 1080p 的两列推荐值。
        let minimum60 = bitrate30 * (4780.0 / 3150)
        let maximum60 = bitrate30 * (6500.0 / 3150)
        return (
            interpolate(fps, points: [
                (10, bitrate10), (15, bitrate15), (30, bitrate30), (60, minimum60)
            ]),
            interpolate(fps, points: [
                (10, bitrate10 * 2), (15, bitrate15 * 2), (30, bitrate30 * 2), (60, maximum60)
            ])
        )
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
