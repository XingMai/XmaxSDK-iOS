import Foundation

typealias VideoSourceFrameListener = @Sendable (any VideoFrame) throws -> Void
typealias VideoSourceErrorListener = @Sendable (XmaxError) -> Void

/// 定义本地视频文件循环解码和帧率采样能力。
protocol VideoSourceControlling: Sendable {

    /// 配置视频文件、旋转方向和目标帧率。
    func configure(
        fileURL: URL,
        rotation: VideoRotation,
        frameRate: Int
    ) throws

    /// 使用共享时间线开始循环输出视频帧。
    func start(timeline: MediaTimeline) async throws

    /// 从首帧重新开始循环输出视频帧。
    func restart(timeline: MediaTimeline) async throws

    /// 停止解码并释放视频资源。
    func stop()
}
