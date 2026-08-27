/// 定义实时视频编码参数的配置能力。
protocol EncodingControlling: Sendable {

    /// 校验并应用实时视频编码格式。
    func configure(_ videoFormat: RealtimeVideoFormat) throws
}
