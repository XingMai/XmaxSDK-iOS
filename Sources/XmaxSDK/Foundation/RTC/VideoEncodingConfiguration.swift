/// RTC 主视频流编码参数。
struct VideoEncodingConfiguration: Equatable, Sendable {
    enum EncoderPreference: Equatable, Sendable {
        case auto
        case maintainFramerate
        case maintainQuality
    }

    // 编码参数
    let width: Int
    let height: Int
    let frameRate: Int
    let minimumBitrate: Int
    let maximumBitrate: Int
    let encoderPreference: EncoderPreference

    init(
        width: Int,
        height: Int,
        frameRate: Int,
        minimumBitrate: Int = 0,
        maximumBitrate: Int = -1,
        encoderPreference: EncoderPreference = .auto
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.minimumBitrate = minimumBitrate
        self.maximumBitrate = maximumBitrate
        self.encoderPreference = encoderPreference
    }
}
