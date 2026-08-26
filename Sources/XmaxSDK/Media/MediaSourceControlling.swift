import Foundation

typealias MediaSourceErrorListener = @Sendable (XmaxError) -> Void

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

    /// 为新一轮生成从文件起点重新建立同步时间线。
    func restart() async throws

    /// 停止输出并释放解码与本地音频播放资源。
    func stop() async
}
