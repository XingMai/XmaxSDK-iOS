import Foundation

/// 统一协调视频轨道、RTC 画面和轨迹交互的渲染资源。
@MainActor
final class RenderController: RenderControlling {

    // 基础层组件
    private let rtcManager: any RtcManaging

    // 渲染层组件
    private let remoteVideoController: any RemoteVideoControlling

    convenience init(rtcManager: any RtcManaging) {
        self.init(
            rtcManager: rtcManager,
            remoteVideoController: RemoteVideoController(
                rtcManager: rtcManager
            )
        )
    }

    init(
        rtcManager: any RtcManaging,
        remoteVideoController: any RemoteVideoControlling
    ) {
        self.rtcManager = rtcManager
        self.remoteVideoController = remoteVideoController
    }

    func setRemoteStream(_ stream: RemoteStream?) throws {
        try remoteVideoController.setRemoteStream(stream)
    }

    func registerRemoteTrack(
        _ track: RealtimeVideoTrack,
        interactionListener: @escaping RenderInteractionListener
    ) {
        let remoteVideoController = remoteVideoController
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(
                libraryName: rtcManager.renderLibraryName,
                attachHandler: { view, contentMode in
                    try remoteVideoController.attach(
                        to: view,
                        contentMode: contentMode
                    )
                },
                detachHandler: { _ in
                    try remoteVideoController.detach()
                }
            )
        )

        guard let videoFormat = track.videoFormat else { return }
        TrajectoryRegistry.register(
            track,
            binding: TrajectoryBinding(
                interactionListener: interactionListener,
                videoFormat: videoFormat
            )
        )
    }

    func updateRemoteVideoFormat(
        _ videoFormat: RealtimeVideoFormat,
        for track: RealtimeVideoTrack
    ) {
        TrajectoryRegistry.binding(for: track)?
            .update(videoFormat: videoFormat)
    }

    func resetRemoteTrack(_ track: RealtimeVideoTrack?) throws {
        if let track {
            VideoRenderRegistry.unregister(track)
            TrajectoryRegistry.unregister(track)
        }
        try remoteVideoController.reset()
    }
}
