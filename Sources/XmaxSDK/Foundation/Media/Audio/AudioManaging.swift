/// 定义本地 PCM 音频播放能力。
protocol AudioManaging: Sendable {

    /// 创建并启动本地 PCM 音频播放器。
    func start() async throws

    /// 写入一帧本地预览音频。
    func write(frame: AudioFrame)

    /// 清除尚未播放的音频数据。
    func flush() async throws

    /// 启用或暂停本地 PCM 预览音频输出。
    ///
    /// - Parameter enabled: `true` 表示播放后续写入的音频帧；
    ///   `false` 表示清空当前缓冲并忽略后续音频帧。
    func setPlaybackEnabled(_ enabled: Bool) async throws

    /// 停止本地音频播放并释放资源。
    func stop() async
}
