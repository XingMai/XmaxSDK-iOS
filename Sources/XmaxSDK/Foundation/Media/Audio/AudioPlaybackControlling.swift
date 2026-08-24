import Foundation

/// 隔离平台音频播放资源的生命周期和缓冲调度。
protocol AudioPlaybackControlling: AnyObject, Sendable {

    /// 启动平台播放资源。
    func start() throws

    /// 调度一段交错排列的 PCM16 数据。
    func enqueue(_ data: Data) throws

    /// 清除尚未播放的缓冲区。
    func flush() throws

    /// 停止并释放平台播放资源。
    func stop()
}
