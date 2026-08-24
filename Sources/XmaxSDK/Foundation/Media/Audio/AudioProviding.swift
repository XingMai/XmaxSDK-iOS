/// 定义本地 PCM 音频播放能力。
protocol AudioProviding: Sendable {

    /// 创建并启动本地 PCM 音频播放器。
    func start() async throws

    /// 写入一帧本地预览音频。
    func write(frame: AudioFrame)

    /// 清除尚未播放的音频数据。
    func flush() async throws

    /// 停止本地音频播放并释放资源。
    func stop() async
}
