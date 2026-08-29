import UIKit

/// 采集多指触摸、驱动轨迹效果并按固定频率提交交互帧。
@MainActor
final class TrajectoryOverlayView: UIView {
    private enum Sampling {
        static let interval: TimeInterval = 1.0 / 30.0
    }

    private struct ActiveTouch {
        let id: TrajectoryID
        var location: CGPoint
    }

    private var activeTouches: [ObjectIdentifier: ActiveTouch] = [:]
    private weak var binding: TrajectoryBinding?
    private var videoContentMode: VideoContentMode = .fill
    private var videoSize: CGSize?
    private var renderer: any TrajectoryEffectRendering
    private var requestedInteractionEnabled = true
    private var lastSampleTime: TimeInterval?
    private var displayLink: CADisplayLink?

    init(renderer: any TrajectoryEffectRendering) {
        self.renderer = renderer
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        installRendererView(renderer)
        updateInteractionState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        displayLink?.invalidate()
    }

    func setRenderer(_ renderer: any TrajectoryEffectRendering) {
        cancelInteraction()
        self.renderer.reset()
        self.renderer.view.removeFromSuperview()
        self.renderer = renderer
        installRendererView(renderer)
    }

    func setBinding(_ binding: TrajectoryBinding?) {
        self.binding = binding
        if binding == nil {
            cancelInteraction()
        }
        updateInteractionState()
    }

    func setContentMode(_ contentMode: VideoContentMode) {
        guard videoContentMode != contentMode else { return }
        videoContentMode = contentMode
        cancelInteraction()
        updateInteractionState()
    }

    func setVideoSize(_ videoSize: CGSize?) {
        guard self.videoSize != videoSize else { return }
        self.videoSize = videoSize
        cancelInteraction()
        updateInteractionState()
    }

    func setRequestedInteractionEnabled(_ isEnabled: Bool) {
        guard requestedInteractionEnabled != isEnabled else { return }
        requestedInteractionEnabled = isEnabled
        if !isEnabled {
            cancelInteraction()
        }
        updateInteractionState()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderer.view.frame = bounds
        updateInteractionState()
    }

    override func point(
        inside point: CGPoint,
        with event: UIEvent?
    ) -> Bool {
        guard super.point(inside: point, with: event),
              let interactionFrame else {
            return false
        }
        return interactionFrame.contains(point)
    }

    override func touchesBegan(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesBegan(touches, with: event)
        let timestamp = CACurrentMediaTime()
        let points = touches.map { touch -> TrajectoryPoint in
            let location = clamped(touch.location(in: self))
            let activeTouch = ActiveTouch(
                id: TrajectoryID(),
                location: location
            )
            activeTouches[ObjectIdentifier(touch)] = activeTouch
            return trajectoryPoint(for: activeTouch, timestamp: timestamp)
        }
        renderer.renderBegan(points)
        submitIfNeeded(now: timestamp, force: true)
        startDisplayLink()
    }

    override func touchesMoved(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesMoved(touches, with: event)
        let timestamp = CACurrentMediaTime()
        var began: [TrajectoryPoint] = []
        var moved: [TrajectoryPoint] = []

        for touch in touches {
            let key = ObjectIdentifier(touch)
            let location = clamped(touch.location(in: self))
            if var activeTouch = activeTouches[key] {
                let dx = location.x - activeTouch.location.x
                let dy = location.y - activeTouch.location.y
                guard dx * dx + dy * dy >= 0.25 else { continue }
                activeTouch.location = location
                activeTouches[key] = activeTouch
                moved.append(
                    trajectoryPoint(for: activeTouch, timestamp: timestamp)
                )
            } else {
                let activeTouch = ActiveTouch(
                    id: TrajectoryID(),
                    location: location
                )
                activeTouches[key] = activeTouch
                began.append(
                    trajectoryPoint(for: activeTouch, timestamp: timestamp)
                )
            }
        }

        if !began.isEmpty { renderer.renderBegan(began) }
        if !moved.isEmpty { renderer.renderMoved(moved) }
        if !began.isEmpty || !moved.isEmpty {
            startDisplayLink()
        }
    }

    override func touchesEnded(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesEnded(touches, with: event)
        finish(touches)
    }

    override func touchesCancelled(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesCancelled(touches, with: event)
        finish(touches)
    }
}

private extension TrajectoryOverlayView {
    func finish(_ touches: Set<UITouch>) {
        let identifiers = touches.compactMap {
            activeTouches.removeValue(forKey: ObjectIdentifier($0))?.id
        }
        if !identifiers.isEmpty {
            renderer.renderEnded(identifiers)
        }
        if activeTouches.isEmpty {
            lastSampleTime = nil
            stopDisplayLink()
        }
    }

    func submitIfNeeded(
        now: TimeInterval,
        force: Bool = false
    ) {
        let points = activeTouches.values.map(\.location)
        guard !points.isEmpty else { return }
        if !force,
           let lastSampleTime,
           now - lastSampleTime < Sampling.interval {
            return
        }
        lastSampleTime = now
        binding?.submit(points: points, viewportSize: bounds.size)
    }

    func cancelInteraction() {
        lastSampleTime = nil
        stopDisplayLink()
        let identifiers = activeTouches.values.map(\.id)
        activeTouches.removeAll()
        if !identifiers.isEmpty {
            renderer.renderEnded(identifiers)
        }
        renderer.reset()
    }

    func startDisplayLink() {
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(displayLinkDidTick)
        )
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc func displayLinkDidTick() {
        submitIfNeeded(now: CACurrentMediaTime())
        if activeTouches.isEmpty {
            stopDisplayLink()
        }
    }

    func updateInteractionState() {
        isUserInteractionEnabled = requestedInteractionEnabled
            && binding != nil
            && interactionFrame != nil
    }

    func installRendererView(
        _ renderer: any TrajectoryEffectRendering
    ) {
        let rendererView = renderer.view
        rendererView.frame = bounds
        rendererView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        rendererView.isUserInteractionEnabled = false
        addSubview(rendererView)
    }

    private func trajectoryPoint(
        for activeTouch: ActiveTouch,
        timestamp: TimeInterval
    ) -> TrajectoryPoint {
        let normalizationFrame = displayedVideoFrame ?? bounds
        let normalizedLocation = CGPoint(
            x: normalizationFrame.width > 0
                ? (activeTouch.location.x - normalizationFrame.minX)
                    / normalizationFrame.width
                : 0,
            y: normalizationFrame.height > 0
                ? (activeTouch.location.y - normalizationFrame.minY)
                    / normalizationFrame.height
                : 0
        )
        return TrajectoryPoint(
            id: activeTouch.id,
            location: activeTouch.location,
            normalizedLocation: normalizedLocation,
            timestamp: timestamp
        )
    }

    func clamped(_ point: CGPoint) -> CGPoint {
        guard let interactionFrame else { return point }
        return CGPoint(
            x: min(max(point.x, interactionFrame.minX), interactionFrame.maxX),
            y: min(max(point.y, interactionFrame.minY), interactionFrame.maxY)
        )
    }

    var displayedVideoFrame: CGRect? {
        guard let videoSize else { return nil }
        return InteractionCoordinateMapper.displayedFrame(
            viewportSize: bounds.size,
            videoSize: videoSize,
            contentMode: videoContentMode
        )
    }

    var interactionFrame: CGRect? {
        guard let displayedVideoFrame else { return nil }
        let frame = displayedVideoFrame.intersection(bounds)
        return frame.isNull || frame.isEmpty ? nil : frame
    }
}
