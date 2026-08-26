import Foundation

typealias AudioSourceErrorListener = @Sendable (XmaxError) -> Void

/// 定义本地媒体音频循环解码能力。
protocol AudioSourceControlling: Sendable {

    /// 配置包含音频轨道的本地媒体文件。
    func configure(fileURL: URL) throws

    /// 使用共享时间线开始循环输出音频帧。
    func start(timeline: MediaTimeline) async throws

    /// 从文件起点重新开始循环输出音频帧。
    func restart(timeline: MediaTimeline) async throws

    /// 停止解码并释放音频资源。
    func stop()
}
