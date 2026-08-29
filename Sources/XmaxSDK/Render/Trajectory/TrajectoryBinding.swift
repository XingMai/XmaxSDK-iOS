import UIKit

/// 将渲染层触摸输入转交给媒体交互层。
final class TrajectoryBinding: @unchecked Sendable {
    private let interactionListener: RenderInteractionListener

    @MainActor private weak var overlayView: TrajectoryOverlayView?
    @MainActor private var contentMode: VideoContentMode = .fill
    @MainActor private var videoSize: CGSize?

    init(
        interactionListener: @escaping RenderInteractionListener,
        videoFormat: RealtimeVideoFormat
    ) {
        self.interactionListener = interactionListener
        videoSize = videoFormat.size
    }

    @MainActor
    func attach(
        to overlayView: TrajectoryOverlayView,
        contentMode: VideoContentMode
    ) {
        if self.overlayView !== overlayView {
            self.overlayView?.setBinding(nil)
            self.overlayView = overlayView
        }
        self.contentMode = contentMode
        overlayView.setBinding(self)
        overlayView.setContentMode(contentMode)
        overlayView.setVideoSize(videoSize)
    }

    @MainActor
    func detach(from overlayView: TrajectoryOverlayView) {
        guard self.overlayView === overlayView else { return }
        self.overlayView = nil
        overlayView.setBinding(nil)
    }

    @MainActor
    func invalidate() {
        overlayView?.setBinding(nil)
        overlayView = nil
    }

    @MainActor
    func update(contentMode: VideoContentMode) {
        self.contentMode = contentMode
        overlayView?.setContentMode(contentMode)
    }

    @MainActor
    func update(videoFormat: RealtimeVideoFormat) {
        videoSize = videoFormat.size
        overlayView?.setVideoSize(videoFormat.size)
    }

    @MainActor
    func submit(points: [CGPoint], viewportSize: CGSize) {
        guard !points.isEmpty else { return }
        let frame = InteractionFrame(
            points: points,
            viewportSize: viewportSize,
            contentMode: contentMode
        )
        let interactionListener = interactionListener
        Task {
            await interactionListener(frame)
        }
    }
}
