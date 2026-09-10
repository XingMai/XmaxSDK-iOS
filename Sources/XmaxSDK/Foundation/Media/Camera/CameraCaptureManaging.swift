import Foundation

/// 管理系统摄像头及其原始视频帧输出。
protocol CameraCaptureManaging: Sendable {

    /// 启动摄像头，输出已经转正并调整到目标尺寸的 NV12 帧。
    ///
    /// - Parameters:
    ///   - videoFormat: 输出像素格式和尺寸。
    ///   - frameRate: 采集帧率。
    ///   - position: 摄像头位置。
    ///   - frameListener: 在采集串行队列接收视频帧。
    ///   - errorListener: 接收采集运行错误。
    /// - Throws: 设备、规格或采集启动失败时抛出错误。
    func start(
        videoFormat: VideoFormat,
        frameRate: Int,
        position: CameraPosition,
        frameListener: @escaping @Sendable (VideoFrame) throws -> Void,
        errorListener: @escaping XmaxErrorListener
    ) async throws

    /// 切换摄像头，保持输出尺寸和帧率。
    ///
    /// - Parameter position: 目标摄像头位置。
    /// - Throws: 设备不可用或切换失败时抛出错误。
    func switchCamera(to position: CameraPosition) async throws

    /// 停止采集，等待正在处理的帧结束并释放设备。
    func stop() async
}
