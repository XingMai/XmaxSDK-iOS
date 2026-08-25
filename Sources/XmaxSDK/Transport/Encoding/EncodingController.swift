/// 根据实时视频格式配置 RTC 视频编码参数。
final class EncodingController: EncodingControlling, Sendable {

    // 基础层组件
    private let rtcProvider: any RtcProviding

    init(rtcProvider: any RtcProviding) {
        self.rtcProvider = rtcProvider
    }

    func configure(_ videoFormat: RealtimeVideoFormat) throws {
        try videoFormat.validate()
        try rtcProvider.configureVideoEncoding(
            VideoEncodingConfiguration(
                width: videoFormat.width,
                height: videoFormat.height,
                frameRate: videoFormat.fps
            )
        )
    }
}
