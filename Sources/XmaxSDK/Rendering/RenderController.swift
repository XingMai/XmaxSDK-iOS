import UIKit

/// 统一协调视频轨道、远端帧处理和轨迹交互的渲染资源。
@MainActor
final class RenderController: RenderControlling {

    // 基础层组件
    private let rtcManager: any RtcManaging

    // 事件监听
    private let errorListener: XmaxErrorListener

    // 远端帧处理
    private let initialFrameInterpolationEnabled: Bool
    private let frameInterpolationSupportChecker:
        RemoteVideoFramePipeline.FrameInterpolationSupportChecker
    private var renderingToken = UUID()
    private lazy var remoteFramePipeline = RemoteVideoFramePipeline(
        interpolationEnabled: initialFrameInterpolationEnabled,
        outputToken: renderingToken,
        frameInterpolationSupportChecker:
            frameInterpolationSupportChecker,
        outputListener: { [weak self] frame, outputToken in
            await self?.displayRemoteFrame(
                frame,
                outputToken: outputToken
            )
        },
        errorListener: { [weak self] error in
            self?.errorListener(error)
        }
    )

    // 远端渲染资源
    private var remoteStream: RemoteStream?
    private var activeRemoteFrameStream: RemoteStream?
    private weak var remoteView: XmaxVideoView?
    private var remoteContentMode = VideoContentMode.fill

    init(
        rtcManager: any RtcManaging,
        frameInterpolationEnabled: Bool = false,
        frameInterpolationSupportChecker:
            @escaping RemoteVideoFramePipeline
                .FrameInterpolationSupportChecker = {
                    FrameInterpolationSupport.supports(size: $0)
                },
        errorListener: @escaping XmaxErrorListener = { _ in }
    ) {
        self.rtcManager = rtcManager
        initialFrameInterpolationEnabled = frameInterpolationEnabled
        self.frameInterpolationSupportChecker =
            frameInterpolationSupportChecker
        self.errorListener = errorListener
    }

    var isFrameInterpolationEnabled: Bool {
        get async {
            await remoteFramePipeline.isFrameInterpolationEnabled
        }
    }

    nonisolated var isFrameInterpolationSupported: Bool {
        FrameInterpolationSupport.isSupported
    }

    func setRemoteStream(_ stream: RemoteStream?) throws {
        let previousStream = remoteStream
        if let previousStream, previousStream != stream {
            try deactivateRemoteFrames(for: previousStream)
        }

        remoteStream = stream
        refreshRenderingToken()
        guard stream != nil else {
            remoteView?.clearDecodedVideoPreview()
            return
        }
        try activateRemoteFramesIfReady(reportsError: false)
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

    func setFrameInterpolationEnabled(
        _ enabled: Bool,
        videoFormat: RealtimeVideoFormat?
    ) async throws {
        renderingToken = UUID()
        try await remoteFramePipeline.setFrameInterpolationEnabled(
            enabled,
            videoSize: videoFormat.map {
                CGSize(width: $0.width, height: $0.height)
            },
            outputToken: renderingToken
        )
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
        guard let videoView = view as? XmaxVideoView else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Remote tracks require an XmaxVideoView"
            )
        }
        if let remoteView, remoteView !== videoView,
           let remoteStream {
            try deactivateRemoteFrames(for: remoteStream)
            remoteView.clearDecodedVideoPreview()
        }

        remoteView = videoView
        remoteContentMode = contentMode
        videoView.prepareDecodedVideoPreview(contentMode: contentMode)
        try activateRemoteFramesIfReady(reportsError: true)
    }

    func detachRemoteVideo() throws {
        if let remoteStream {
            try deactivateRemoteFrames(for: remoteStream)
        }
        remoteView?.clearDecodedVideoPreview()
        self.remoteView = nil
        refreshRenderingToken()
    }

    func resetRemoteVideo() throws {
        let stream = remoteStream
        remoteStream = nil
        remoteContentMode = .fill

        if let stream {
            try deactivateRemoteFrames(for: stream)
        }
        remoteView?.clearDecodedVideoPreview()
        remoteView = nil
        refreshRenderingToken()
    }

    func activateRemoteFramesIfReady(reportsError: Bool) throws {
        guard let remoteStream, remoteView != nil else { return }
        guard activeRemoteFrameStream != remoteStream else { return }
        do {
            try rtcManager.setRemoteVideoFrameListener(
                { [weak remoteFramePipeline] frame in
                    Task {
                        await remoteFramePipeline?.enqueue(frame)
                    }
                },
                for: remoteStream
            )
            activeRemoteFrameStream = remoteStream
        } catch {
            if reportsError {
                errorListener(XmaxError.from(error))
            }
            throw error
        }
    }

    func deactivateRemoteFrames(for stream: RemoteStream) throws {
        guard activeRemoteFrameStream == stream else { return }
        try rtcManager.setRemoteVideoFrameListener(nil, for: stream)
        activeRemoteFrameStream = nil
    }

    func refreshRenderingToken() {
        renderingToken = UUID()
        let token = renderingToken
        Task { [remoteFramePipeline] in
            await remoteFramePipeline.reset(outputToken: token)
        }
    }

    func displayRemoteFrame(
        _ frame: DecodedVideoFrame,
        outputToken: UUID
    ) {
        guard outputToken == renderingToken, let remoteView else { return }
        remoteView.displayRemoteVideoFrame(
            frame,
            contentMode: remoteContentMode
        )
    }
}
