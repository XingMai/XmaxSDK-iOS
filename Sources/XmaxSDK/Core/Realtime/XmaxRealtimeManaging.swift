/// 定义 SDK 对接入方提供的实时媒体控制能力。
public protocol XmaxRealtimeManaging: Sendable {

    /// 实时能力配置。
    var options: RealtimeConfiguration { get }

    /// 创建本地相机流并开始预览。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream

    /// 将当前本地媒体流替换为相机流。
    func replaceLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream

    /// 停止本地相机流并释放本地预览与 RTC 资源。
    func stopLocalCameraStream() async throws

    /// 切换前后置摄像头。
    func switchCamera() async throws -> RealtimeMediaStream
}

public extension XmaxRealtimeManaging {
    /// 使用前置摄像头创建本地相机流并开始预览。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat
    ) async throws -> RealtimeMediaStream {
        try await createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
    }

    /// 使用前置摄像头替换当前本地媒体流。
    func replaceLocalCameraStream(
        videoFormat: RealtimeVideoFormat
    ) async throws -> RealtimeMediaStream {
        try await replaceLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
    }
}
