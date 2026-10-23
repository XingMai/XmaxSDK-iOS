//
//  RealtimeVideoFormat.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The encoding preference for realtime video.
public enum RealtimeVideoEncoderPreference: Equatable, Sendable {

    /// Balances frame rate and resolution.
    case auto

    /// Prioritizes frame rate.
    case maintainFramerate

    /// Prioritizes resolution.
    case maintainQuality
}

/// The dimensions, frame rate, and uplink encoding settings for realtime video.
public struct RealtimeVideoFormat: Equatable, Sendable {

    /// Video dimensions and timing.

    /// The positive, even video width, in pixels.
    public let width: Int

    /// The positive, even video height, in pixels.
    public let height: Int

    /// The positive frame rate, in frames per second.
    public let fps: Int

    /// Encoding configuration.

    /// The minimum uplink bitrate, in kbps. `nil` uses 500, capped by the maximum; zero disables
    /// the minimum.
    public let minimumBitrate: Int?

    /// The maximum uplink bitrate, in kbps. `nil` derives it from upload dimensions and frame rate;
    /// explicit values must be positive.
    public let maximumBitrate: Int?

    /// The uplink encoding preference, defaulting to frame rate preservation.
    public let encoderPreference: RealtimeVideoEncoderPreference

    /// Creates a realtime video format.
    public init(
        width: Int,
        height: Int,
        fps: Int,
        minimumBitrate: Int? = nil,
        maximumBitrate: Int? = nil,
        encoderPreference: RealtimeVideoEncoderPreference = .maintainFramerate
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.minimumBitrate = minimumBitrate
        self.maximumBitrate = maximumBitrate
        self.encoderPreference = encoderPreference
    }

    /// Validates dimensions, frame rate, and explicit bitrate bounds.
    ///
    /// - Throws: An error if dimensions, frame rate, or bitrate settings are invalid.
    public func validate() throws {
        guard width > 0,
            height > 0,
            fps > 0,
            width.isMultiple(of: 2),
            height.isMultiple(of: 2)
        else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Realtime video width and height must be positive "
                    + "even numbers, and fps must be greater than zero"
            )
        }
        if let minimumBitrate, minimumBitrate < 0 {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Minimum bitrate must not be negative"
            )
        }
        if let maximumBitrate, maximumBitrate <= 0 {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Maximum bitrate must be greater than zero"
            )
        }
        if let minimumBitrate, let maximumBitrate, minimumBitrate > maximumBitrate {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Minimum bitrate must not exceed maximum bitrate"
            )
        }
    }
}

extension RealtimeVideoFormat {

    /// Returns a format with new dimensions, retaining frame rate and encoding settings.
    ///
    /// - Parameters:
    ///   - width: The target width, in pixels.
    ///   - height: The target height, in pixels.
    ///
    /// - Returns: The resized video format.
    func resized(
        width: Int,
        height: Int
    ) -> RealtimeVideoFormat {
        RealtimeVideoFormat(
            width: width,
            height: height,
            fps: fps,
            minimumBitrate: minimumBitrate,
            maximumBitrate: maximumBitrate,
            encoderPreference: encoderPreference
        )
    }
}
