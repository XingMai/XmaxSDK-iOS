import Foundation

/// 将解码帧投递到当前绑定的 SDK 视频视图。
@MainActor
final class DecodedVideoPreviewPresenter {

    // 预览资源
    private weak var view: XmaxVideoView?
    private var contentMode = VideoContentMode.fill
    private var mirrored = false

    func attach(
        to view: XmaxVideoView,
        contentMode: VideoContentMode
    ) {
        self.view = view
        self.contentMode = contentMode
        view.prepareDecodedVideoPreview(contentMode: contentMode)
        view.setDecodedVideoPreviewMirrored(mirrored)
    }

    func detach(from view: XmaxVideoView) {
        view.clearDecodedVideoPreview()
        if self.view === view {
            self.view = nil
        }
    }

    func display(_ frame: VideoFrame) {
        view?.displayDecodedVideoFrame(frame, contentMode: contentMode)
    }

    func setMirrored(_ mirrored: Bool) {
        self.mirrored = mirrored
        view?.setDecodedVideoPreviewMirrored(mirrored)
    }

    func clear() {
        view?.clearDecodedVideoPreview()
        view = nil
    }
}

/// 合并主线程来不及显示的帧，只保留最新的视频预览帧。
final class DecodedVideoPreviewDispatcher: @unchecked Sendable {

    // 渲染组件
    private let presenter: DecodedVideoPreviewPresenter

    // 并发状态
    private let lock = NSLock()
    private var pendingFrame: VideoFrame?
    private var isDeliveryScheduled = false

    init(presenter: DecodedVideoPreviewPresenter) {
        self.presenter = presenter
    }

    func enqueue(_ frame: VideoFrame) {
        let shouldSchedule = lock.withLock { () -> Bool in
            pendingFrame = frame
            guard !isDeliveryScheduled else { return false }
            isDeliveryScheduled = true
            return true
        }
        if shouldSchedule {
            scheduleDelivery()
        }
    }

    func reset() {
        lock.withLock {
            pendingFrame = nil
        }
    }

    private func scheduleDelivery() {
        Task { @MainActor [weak self] in
            self?.deliverLatestFrame()
        }
    }

    @MainActor
    private func deliverLatestFrame() {
        let frame = lock.withLock { () -> VideoFrame? in
            let frame = pendingFrame
            pendingFrame = nil
            return frame
        }
        if let frame {
            presenter.display(frame)
        }

        let shouldScheduleAgain = lock.withLock { () -> Bool in
            if pendingFrame == nil {
                isDeliveryScheduled = false
                return false
            }
            return true
        }
        if shouldScheduleAgain {
            scheduleDelivery()
        }
    }
}
