import Foundation

typealias MediaSourceErrorListener = @Sendable (XmaxError) -> Void

/// 保存媒体层错误监听器，并允许同步媒体回调从任意线程报告错误。
final class MediaSourceErrorHandler: @unchecked Sendable {

    // 并发控制
    private let lock = NSLock()

    // 事件监听
    private var listener: MediaSourceErrorListener?

    func setListener(_ listener: MediaSourceErrorListener?) {
        lock.withLock {
            self.listener = listener
        }
    }

    func report(_ error: XmaxError) {
        let listener = lock.withLock { listener }
        listener?(error)
    }
}

/// 定义本地视频文件准备、循环播放和重新起播能力。
protocol MediaSourceControlling: Sendable {

    /// 当前媒体是否包含音频轨道。
    var hasAudio: Bool { get }

    /// 准备本地视频文件和输出格式。
    func prepare(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> MediaSourceConfiguration

    /// 从文件起点开始循环输出音视频帧。
    func start() async throws

    /// 为新一轮生成从指定文件时间重新建立同步时间线。
    ///
    /// - Parameter mediaTimeUs: 音频和视频共同使用的文件内起播时间。
    func restart(from mediaTimeUs: Int64) async throws

    /// 启用或暂停本地音频预览，不影响 RTC 音频帧输出。
    ///
    /// - Parameter enabled: `true` 表示播放本地预览音频；
    ///   `false` 表示立即清空缓冲并保持静音。
    func setLocalAudioPreviewEnabled(_ enabled: Bool) async throws

    /// 停止输出并释放解码与本地音频播放资源。
    func stop() async
}
