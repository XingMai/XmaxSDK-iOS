/// 实时生成业务入口，负责向公开协议转发本地媒体操作。
final class XmaxRealtimeManager: XmaxRealtimeManaging, Sendable {

    // 公共配置
    let options: RealtimeConfiguration

    // 实时管理组件
    private let mediaManager: XmaxRealtimeMediaManager

    @MainActor
    init(options: RealtimeConfiguration) {
        self.options = options
        let rtcProvider = RtcProvider()
        mediaManager = XmaxRealtimeMediaManager(rtcProvider: rtcProvider)
    }

    init(
        options: RealtimeConfiguration,
        mediaManager: XmaxRealtimeMediaManager
    ) {
        self.options = options
        self.mediaManager = mediaManager
    }

    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        try await mediaManager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: position
        )
    }

    func replaceLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        try await mediaManager.replaceLocalCameraStream(
            videoFormat: videoFormat,
            position: position
        )
    }

    func stopLocalCameraStream() async throws {
        await mediaManager.stopLocalCameraStream()
    }

    func switchCamera() async throws -> RealtimeMediaStream {
        try await mediaManager.switchCamera()
    }
}
