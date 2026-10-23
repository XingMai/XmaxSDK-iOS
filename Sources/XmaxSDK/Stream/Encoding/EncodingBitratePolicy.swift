//
//  EncodingBitratePolicy.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The shared encoding bitrate budget.
enum EncodingBitratePolicy {

    /// Resolves bitrate bounds, honoring explicit settings.
    ///
    /// - Parameter videoFormat: The dimensions, frame rate, and optional bitrate bounds.
    ///
    /// - Returns: The minimum and maximum bitrate, in kbps.
    ///
    /// - Throws: An error if the format is invalid, bitrate overflows, or bounds conflict.
    static func resolve(
        _ videoFormat: RealtimeVideoFormat
    ) throws -> (minimum: Int, maximum: Int) {
        try videoFormat.validate()
        let minimum: Int
        let maximum: Int
        if let minimumBitrate = videoFormat.minimumBitrate,
            let maximumBitrate = videoFormat.maximumBitrate
        {
            minimum = minimumBitrate
            maximum = maximumBitrate
        } else {
            let maximumBitrate =
                (resolveMaximumBitrate(
                    pixels: Double(videoFormat.width) * Double(videoFormat.height),
                    fps: Double(videoFormat.fps)
                ) * 0.6).rounded(
                    .toNearestOrEven
                )
            guard maximumBitrate.isFinite, maximumBitrate < Double(Int.max) else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Realtime video format exceeds the supported bitrate range"
                )
            }
            let defaultMaximum = max(
                100,
                Int(maximumBitrate)
            )
            minimum = videoFormat.minimumBitrate ?? 100
            maximum = videoFormat.maximumBitrate ?? defaultMaximum
        }

        guard minimum <= maximum else {
            throw XmaxError(
                code: .invalidConfiguration,
                message:
                    "Minimum bitrate must not exceed maximum bitrate after applying SDK defaults"
            )
        }

        return (minimum, maximum)
    }
}

/// Interpolates a maximum bitrate from reference dimensions and frame rates. The minimum defaults
/// to 100 kbps; the maximum is 0.6 times the quality reference, with a 100 kbps floor. Formats
/// outside the table are extrapolated from reference ratios. Reference:
/// https://docs.byteplus.com/id/docs/byteplus-rtc/docs-70122
private extension EncodingBitratePolicy {

    /// A resolution or frame rate and its reference bitrate.
    typealias BitratePoint = (value: Double, bitrate: Double)

    /// The pixel area and bitrate references at 15 fps, in kbps.
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

    /// The pixel area and bitrate references at 30 fps, in kbps.
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

    /// Resolves a reference maximum bitrate by pixel area and frame rate.
    ///
    /// - Parameters:
    ///   - pixels: The total pixel area.
    ///   - fps: The frames per second.
    ///
    /// - Returns: The reference maximum bitrate before the budget multiplier, in kbps.
    static func resolveMaximumBitrate(
        pixels: Double,
        fps: Double
    ) -> Double {
        let bitrate15 = interpolate(
            pixels,
            points: referenceBitratesAt15FPS
        )
        let bitrate30: Double
        let first30 = referenceBitratesAt30FPS[0]
        if pixels < first30.value {
            // Extend the 15 fps size curve to the first 30 fps reference point for smaller frames.
            let reference15 = interpolate(
                first30.value,
                points: referenceBitratesAt15FPS
            )
            bitrate30 = bitrate15 * (first30.bitrate / reference15)
        } else {
            bitrate30 = interpolate(
                pixels,
                points: referenceBitratesAt30FPS
            )
        }

        // Anchor the 10 fps curve at 400 kbps for 640 × 480.
        let bitrate10 = bitrate15 * (400.0 / 500)
        // Extend the 30 fps size curve to match the 1080p 60 fps reference.
        let maximum60 = bitrate30 * (6500.0 / 3150)
        return interpolate(
            fps,
            points: [
                (10, bitrate10 * 2), (15, bitrate15 * 2), (30, bitrate30 * 2), (60, maximum60)
            ]
        )
    }

    /// Interpolates between references and extrapolates proportionally beyond endpoints.
    ///
    /// - Parameters:
    ///   - value: The pixel area or frame rate to evaluate.
    ///   - points: The nonempty reference points sorted by input value.
    ///
    /// - Returns: The interpolated or extrapolated bitrate.
    static func interpolate(
        _ value: Double,
        points: [BitratePoint]
    ) -> Double {
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
