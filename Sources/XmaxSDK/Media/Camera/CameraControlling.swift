import Foundation

/// 通知摄像头预览就绪，并提供异步处理时检查该预览仍有效的能力。
typealias CameraPreviewReadyHandler = @MainActor @Sendable (
    _ isCurrent: @escaping @Sendable () -> Bool
) -> Void

/// 定义本地摄像头流、麦克风采集和预览资源管理能力。
protocol CameraControlling: Sendable {

    /// 当前本地相机视频轨道；尚未创建或已停止时为空。
    var currentTrack: RealtimeVideoTrack? { get }

    /// 当前相机流是否配置为使用麦克风。
    var useMicrophone: Bool { get }

    /// 设置当前相机流的一次性内部就绪处理；条件为已收到有效帧且预览已绑定。
    ///
    /// - Parameter handler: 就绪时调用的处理闭包；传入空值时清除。
    func setPreviewReadyHandler(_ handler: CameraPreviewReadyHandler?)

    /// 创建并启动本地相机流。
    ///
    /// - Parameters:
    ///   - videoFormat: 期望的输出尺寸、帧率和编码配置；尺寸按模型规则调整。
    ///   - position: 首次启动时使用的摄像头位置。
    ///   - useMicrophone: 是否申请麦克风权限并允许实时连接时启动音频采集。
    /// - Returns: 包含本地相机视频轨道的媒体流。
    /// - Throws: 已有活动相机流、格式无效、权限不足或采集启动失败时抛出错误。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition,
        useMicrophone: Bool
    ) async throws -> RealtimeMediaStream

    /// 为已启用麦克风的相机流启动音频采集，不开启本地回放。
    ///
    /// - Throws: RTC 音频源配置或麦克风采集启动失败时抛出错误。
    func startMicrophoneCapture() throws

    /// 停止麦克风采集，保留下一次连接所需的配置。
    ///
    /// - Throws: RTC 麦克风采集停止失败时抛出错误。
    func stopMicrophoneCapture() throws

    /// 停止相机和麦克风采集，并释放当前轨道及本地预览资源。
    func stopLocalCameraStream() async

    /// 在前置和后置摄像头之间切换，保留当前视频轨道。
    ///
    /// - Returns: 包含更新后相机轨道的媒体流。
    /// - Throws: 相机流尚未启动、设备切换或镜像配置失败时抛出错误。
    func switchCamera() async throws -> RealtimeMediaStream
}
