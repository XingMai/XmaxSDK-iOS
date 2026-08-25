import Foundation

typealias ImageSourceFrameListener = @Sendable (any VideoFrame) throws -> Void
typealias ImageSourceErrorListener = @Sendable (XmaxError) -> Void

/// 定义本地图片持续输出视频帧的能力。
protocol ImageSourceControlling: Sendable {

    /// 准备本地图片和输出格式。
    func prepare(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeVideoFormat

    /// 开始按目标帧率持续输出图片帧。
    func start() throws

    /// 停止输出并释放图片资源。
    func stop()
}
