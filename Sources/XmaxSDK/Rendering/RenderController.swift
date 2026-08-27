import UIKit

/// 统一协调视频轨道、RTC 画面和轨迹交互的渲染资源。
@MainActor
final class RenderController: RenderControlling {

    // 基础层组件
    private let rtcManager: any RtcManaging

    // 事件监听
    private let errorListener: XmaxErrorListener

    // 远端渲染资源
    private var remoteStream: RemoteStream?
    private weak var remoteView: UIView?
    private var remoteContentMode = VideoContentMode.fill

    init(
        rtcManager: any RtcManaging,
        errorListener: @escaping XmaxErrorListener = { _ in }
    ) {
        self.rtcManager = rtcManager
        self.errorListener = errorListener
    }

    func setRemoteStream(_ stream: RemoteStream?) throws {
        let previousStream = remoteStream
        if let previousStream, previousStream != stream {
            try rtcManager.unbindRemoteVideo(previousStream)
        }

        remoteStream = stream
        guard let stream, let remoteView else { return }
        try rtcManager.bindRemoteVideo(
            stream,
            to: remoteView,
            contentMode: remoteContentMode
        )
    }

    func registerRemoteTrack(
        _ track: RealtimeVideoTrack,
        interactionListener: @escaping RenderInteractionListener
    ) {
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(
                libraryName: rtcManager.renderLibraryName,
                attachHandler: { [weak self] view, contentMode in
                    try self?.attachRemoteVideo(
                        to: view,
                        contentMode: contentMode
                    )
                },
                detachHandler: { [weak self] _ in
                    try self?.detachRemoteVideo()
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
        try resetRemoteVideo()
    }
}

private extension RenderController {
    func attachRemoteVideo(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        if let remoteView,
           remoteView !== view,
           let remoteStream {
            try rtcManager.unbindRemoteVideo(remoteStream)
        }

        remoteView = view
        remoteContentMode = contentMode
        guard let remoteStream else { return }
        do {
            try rtcManager.bindRemoteVideo(
                remoteStream,
                to: view,
                contentMode: contentMode
            )
        } catch {
            errorListener(XmaxError.from(error))
            throw error
        }
    }

    func detachRemoteVideo() throws {
        guard remoteView != nil else { return }
        remoteView = nil
        if let remoteStream {
            try rtcManager.unbindRemoteVideo(remoteStream)
        }
    }

    func resetRemoteVideo() throws {
        let stream = remoteStream
        remoteStream = nil
        remoteView = nil
        remoteContentMode = .fill

        if let stream {
            try rtcManager.unbindRemoteVideo(stream)
        }
    }
}
