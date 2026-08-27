import UIKit

/// 跨并发域弱持有 RTC Canvas 使用的 UIKit 视图。
private final class RemoteVideoRenderTarget: @unchecked Sendable {
    weak var view: UIView?

    @MainActor
    init(view: UIView) {
        self.view = view
    }
}

/// 描述某一版本期望使用的完整远端视频渲染状态。
private struct RemoteVideoRenderRequest: @unchecked Sendable {
    let revision: UInt64
    let stream: RemoteStream?
    let target: RemoteVideoRenderTarget?
    let contentMode: VideoContentMode
}

/// 串行执行可能阻塞的 RTC Canvas 操作，避免占用 UIKit 主线程。
private actor RemoteVideoRenderWorker {

    // 基础层组件
    private let rtcManager: any RtcManaging

    // 事件监听
    private let errorListener: XmaxErrorListener

    // 运行状态
    private var latestRevision: UInt64 = 0
    private var boundStream: RemoteStream?
    private var boundTargetIdentifier: ObjectIdentifier?
    private var boundContentMode = VideoContentMode.fill

    init(
        rtcManager: any RtcManaging,
        errorListener: @escaping XmaxErrorListener
    ) {
        self.rtcManager = rtcManager
        self.errorListener = errorListener
    }

    func apply(_ request: RemoteVideoRenderRequest) {
        guard request.revision > latestRevision else { return }
        latestRevision = request.revision

        let targetView = request.target?.view
        let targetIdentifier = targetView.map(ObjectIdentifier.init)
        guard boundStream != request.stream ||
                boundTargetIdentifier != targetIdentifier ||
                boundContentMode != request.contentMode else {
            return
        }

        if let boundStream {
            perform(
                "解除远端 RTC 画面失败 (Failed to Unbind Remote RTC Video)"
            ) {
                try rtcManager.unbindRemoteVideo(boundStream)
            }
        }
        boundStream = nil
        boundTargetIdentifier = nil
        boundContentMode = .fill

        guard let stream = request.stream,
              let targetView,
              let targetIdentifier else {
            return
        }
        do {
            try rtcManager.bindRemoteVideo(
                stream,
                to: targetView,
                contentMode: request.contentMode
            )
            boundStream = stream
            boundTargetIdentifier = targetIdentifier
            boundContentMode = request.contentMode
        } catch {
            report(
                "绑定远端 RTC 画面失败 (Failed to Bind Remote RTC Video)",
                error: error
            )
        }
    }
}

private extension RemoteVideoRenderWorker {
    func perform(
        _ title: String,
        operation: () throws -> Void
    ) {
        do {
            try operation()
        } catch {
            report(title, error: error)
        }
    }

    func report(_ title: String, error: any Error) {
        let xmaxError = XmaxError.from(error)
        XmaxLogger.error(
            "\(title)\n└─ 原因：" +
                (error as NSError).localizedDescription,
            category: "Rendering"
        )
        errorListener(xmaxError)
    }
}

/// 统一协调视频轨道、RTC 画面和轨迹交互的渲染资源。
@MainActor
final class RenderController: RenderControlling {

    // 基础层组件
    private let rtcManager: any RtcManaging

    // 渲染组件
    private let remoteVideoRenderWorker: RemoteVideoRenderWorker

    // 远端渲染资源
    private var remoteStream: RemoteStream?
    private weak var remoteView: UIView?
    private var remoteContentMode = VideoContentMode.fill

    // 并发控制
    private var renderRevision: UInt64 = 0
    private var renderUpdateTask: Task<Void, Never>?

    init(
        rtcManager: any RtcManaging,
        errorListener: @escaping XmaxErrorListener = { _ in }
    ) {
        self.rtcManager = rtcManager
        remoteVideoRenderWorker = RemoteVideoRenderWorker(
            rtcManager: rtcManager,
            errorListener: errorListener
        )
    }

    func setRemoteStream(_ stream: RemoteStream?) {
        remoteStream = stream
        scheduleRemoteVideoRenderUpdate()
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
                    self?.attachRemoteVideo(
                        to: view,
                        contentMode: contentMode
                    )
                },
                detachHandler: { [weak self] _ in
                    self?.detachRemoteVideo()
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

    func resetRemoteTrack(_ track: RealtimeVideoTrack?) async {
        if let track {
            VideoRenderRegistry.unregister(track)
            TrajectoryRegistry.unregister(track)
        }
        resetRemoteVideo()
        await waitForPendingRenderUpdates()
    }

    func waitForPendingRenderUpdates() async {
        await renderUpdateTask?.value
    }
}

private extension RenderController {
    func attachRemoteVideo(
        to view: UIView,
        contentMode: VideoContentMode
    ) {
        remoteView = view
        remoteContentMode = contentMode
        scheduleRemoteVideoRenderUpdate()
    }

    func detachRemoteVideo() {
        guard remoteView != nil else { return }
        remoteView = nil
        scheduleRemoteVideoRenderUpdate()
    }

    func resetRemoteVideo() {
        remoteStream = nil
        remoteView = nil
        remoteContentMode = .fill
        scheduleRemoteVideoRenderUpdate()
    }

    func scheduleRemoteVideoRenderUpdate() {
        renderRevision &+= 1
        let request = RemoteVideoRenderRequest(
            revision: renderRevision,
            stream: remoteStream,
            target: remoteView.map(RemoteVideoRenderTarget.init(view:)),
            contentMode: remoteContentMode
        )
        let previousTask = renderUpdateTask
        let worker = remoteVideoRenderWorker
        renderUpdateTask = Task {
            await previousTask?.value
            await worker.apply(request)
        }
    }
}
