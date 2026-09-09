/// 根据实时视频格式配置 RTC 视频编码参数。
final class EncodingController: EncodingControlling, Sendable {

    // 基础层组件
    private let rtcManager: any RtcManaging

    init(rtcManager: any RtcManaging) {
        self.rtcManager = rtcManager
    }

    func configure(_ videoFormat: RealtimeVideoFormat) throws {
        try videoFormat.validate()

        // 按上传像素面积和帧率计算码率范围。
        let scale = Double(videoFormat.width) * Double(videoFormat.height) / (1920 * 1080)
            * (Double(videoFormat.fps) / 30)
        let minimumBitrate = (3150 * scale).rounded()
        let maximumBitrate = (6300 * scale).rounded()
        guard maximumBitrate.isFinite, maximumBitrate < Double(Int.max) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Realtime video format exceeds the supported bitrate range"
            )
        }
        let minimum = max(1, Int(minimumBitrate))
        let maximum = max(minimum + 1, Int(maximumBitrate))
        try rtcManager.configureVideoEncoding(
            VideoEncodingConfiguration(
                width: videoFormat.width,
                height: videoFormat.height,
                frameRate: videoFormat.fps,
                minimumBitrate: minimum,
                maximumBitrate: maximum
            )
        )
    }
}
