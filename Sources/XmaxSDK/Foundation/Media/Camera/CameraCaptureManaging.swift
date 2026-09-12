import Foundation

/// 摄像头画面在窗口中的显示方向。
enum CameraOrientation: Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    var isLandscape: Bool {
        self == .landscapeLeft || self == .landscapeRight
    }

    /// 将固定竖向、未镜像的采集帧转为窗口显示方向。
    var frameRotation: VideoRotation {
        switch self {
        case .portrait: .rotation0
        case .portraitUpsideDown: .rotation180
        case .landscapeLeft: .rotation270
        case .landscapeRight: .rotation90
        }
    }
}

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

    /// 更新帧转换方向和输出尺寸，保留采集连接及帧率。
    ///
    /// - Parameters:
    ///   - orientation: 窗口显示方向。
    ///   - videoFormat: 转正后的输出尺寸和像素格式。
    /// - Throws: 采集已停止时抛出错误。
    func updateOrientation(_ orientation: CameraOrientation, videoFormat: VideoFormat) async throws

    /// 停止采集，等待正在处理的帧结束并释放设备。
    func stop() async
}
