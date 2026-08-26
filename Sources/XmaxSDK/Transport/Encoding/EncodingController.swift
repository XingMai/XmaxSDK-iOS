/// 根据实时视频格式配置 RTC 视频编码参数。
final class EncodingController: EncodingControlling, Sendable {

    // 基础层组件
    private let rtcManager: any RtcManaging

    init(rtcManager: any RtcManaging) {
        self.rtcManager = rtcManager
    }

    func configure(_ videoFormat: RealtimeVideoFormat) throws {
        try videoFormat.validate()
        try rtcManager.configureVideoEncoding(
            VideoEncodingConfiguration(
                width: videoFormat.width,
                height: videoFormat.height,
                frameRate: videoFormat.fps
            )
        )
    }
}
