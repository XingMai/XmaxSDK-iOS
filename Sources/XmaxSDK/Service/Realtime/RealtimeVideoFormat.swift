/// 实时视频的编码策略偏好。
public enum RealtimeVideoEncoderPreference: Equatable, Sendable {

    /// 平衡帧率和分辨率。
    case auto

    /// 优先保障帧率。
    case maintainFramerate

    /// 优先保障分辨率。
    case maintainQuality
}

/// 实时视频的尺寸、帧率和上传编码配置。
public struct RealtimeVideoFormat: Equatable, Sendable {

    /// 视频宽度，单位为像素。
    public let width: Int

    /// 视频高度，单位为像素。
    public let height: Int

    /// 视频帧率。
    public let fps: Int

    /// 最低上传码率，单位为 kbps；nil 使用 SDK 默认值，0 表示不设最低码率。
    public let minimumBitrate: Int?

    /// 最高上传码率，单位为 kbps；nil 使用 SDK 默认值，指定时必须大于 0。
    public let maximumBitrate: Int?

    /// 上传编码策略偏好，默认平衡帧率和分辨率。
    public let encoderPreference: RealtimeVideoEncoderPreference

    /// 创建实时视频格式。
    ///
    /// - Parameters:
    ///   - width: 视频宽度，单位为像素。
    ///   - height: 视频高度，单位为像素。
    ///   - fps: 视频帧率，必须大于 0。
    ///   - minimumBitrate: 最低上传码率，单位为 kbps；nil 按最终上传尺寸和帧率计算。
    ///   - maximumBitrate: 最高上传码率，单位为 kbps；nil 按最终上传尺寸和帧率计算。
    ///   - encoderPreference: 上传编码策略偏好，默认值为 auto。
    public init(
        width: Int,
        height: Int,
        fps: Int,
        minimumBitrate: Int? = nil,
        maximumBitrate: Int? = nil,
        encoderPreference: RealtimeVideoEncoderPreference = .auto
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.minimumBitrate = minimumBitrate
        self.maximumBitrate = maximumBitrate
        self.encoderPreference = encoderPreference
    }

    /// 校验尺寸、帧率和显式指定的码率范围。
    ///
    /// - Throws: 尺寸、帧率或码率配置无效时抛出错误。
    public func validate() throws {
        guard width > 0,
              height > 0,
              fps > 0,
              width.isMultiple(of: 2),
              height.isMultiple(of: 2) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Realtime video width and height must be positive " +
                    "even numbers, and fps must be greater than zero"
            )
        }
        if let minimumBitrate, minimumBitrate < 0 {
            throw XmaxError(code: .invalidConfiguration, message: "Minimum bitrate must not be negative")
        }
        if let maximumBitrate, maximumBitrate <= 0 {
            throw XmaxError(code: .invalidConfiguration, message: "Maximum bitrate must be greater than zero")
        }
        if let minimumBitrate, let maximumBitrate, minimumBitrate > maximumBitrate {
            throw XmaxError(code: .invalidConfiguration, message: "Minimum bitrate must not exceed maximum bitrate")
        }
    }
}

extension RealtimeVideoFormat {
    /// 调整尺寸，保留帧率和上传编码配置。
    func resized(width: Int, height: Int) -> RealtimeVideoFormat {
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
