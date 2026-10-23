//
//  TrajectoryOverlayView.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit

/// Captures multitouch trajectories and samples interactions at a fixed frequency.
@MainActor
final class TrajectoryOverlayView: UIView {

    /// The trajectory sampling configuration.
    private enum Sampling {

        /// The minimum trajectory sample interval, in seconds.
        static let interval: TimeInterval = 1.0 / 30.0
    }

    /// An active touch's identifier and position.
    private struct ActiveTouch {

        /// The stable trajectory identifier.
        let id: TrajectoryID

        /// The overlay position, in points.
        var location: CGPoint
    }

    /// The active touches keyed by system touch identity.
    private var activeTouches: [ObjectIdentifier: ActiveTouch] = [:]

    /// The binding delivering samples to media interactions.
    private weak var binding: TrajectoryBinding?

    /// The video content mode.
    private var videoContentMode: VideoContentMode = .fill

    /// The resolved dimensions used to map the complete media area.
    private var resolvedMediaSize: CGSize?

    /// The trajectory effect renderer.
    private var renderer: any TrajectoryEffectRendering

    /// Whether your app enables trajectory interactions.
    private var requestedInteractionEnabled = true

    /// The last submitted sample time, in seconds.
    private var lastSampleTime: TimeInterval?

    /// The display link driving trajectory sampling.
    private var displayLink: CADisplayLink?

    /// Creates a multitouch trajectory overlay.
    ///
    /// - Parameter renderer: The trajectory appearance renderer.
    init(
        renderer: any TrajectoryEffectRendering
    ) {
        self.renderer = renderer
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        installRendererView(renderer)
        updateInteractionState()
    }

    /// Unavailable; create the overlay with a renderer.
    ///
    /// - Parameter coder: The archive decoder.
    @available(*, unavailable)
    required init?(
        coder: NSCoder
    ) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Stops trajectory sampling refresh.
    isolated deinit {
        displayLink?.invalidate()
    }

    /// Replaces the renderer and clears active trajectories.
    ///
    /// - Parameter renderer: The new effect renderer.
    func setRenderer(
        _ renderer: any TrajectoryEffectRendering
    ) {
        cancelInteraction()
        self.renderer.reset()
        self.renderer.view.removeFromSuperview()
        self.renderer = renderer
        installRendererView(renderer)
    }

    /// Sets the trajectory binding and updates interaction availability.
    ///
    /// - Parameter binding: The media interaction binding, or `nil` to clear it.
    func setBinding(
        _ binding: TrajectoryBinding?
    ) {
        self.binding = binding
        if binding == nil {
            cancelInteraction()
        }
        updateInteractionState()
    }

    /// Updates content mode and clears trajectories in the old coordinate space.
    ///
    /// - Parameter contentMode: The new video content mode.
    func setContentMode(
        _ contentMode: VideoContentMode
    ) {
        guard videoContentMode != contentMode else {
            return
        }
        videoContentMode = contentMode
        cancelInteraction()
        updateInteractionState()
    }

    /// Updates media dimensions and clears trajectories in the old coordinate space.
    ///
    /// - Parameter resolvedMediaSize: The resolved local media dimensions, or `nil` if unknown.
    func setResolvedMediaSize(
        _ resolvedMediaSize: CGSize?
    ) {
        guard self.resolvedMediaSize != resolvedMediaSize else {
            return
        }
        self.resolvedMediaSize = resolvedMediaSize
        cancelInteraction()
        updateInteractionState()
    }

    /// Sets the requested interaction enablement.
    ///
    /// - Parameter isEnabled: Whether trajectory interactions are enabled.
    func setRequestedInteractionEnabled(
        _ isEnabled: Bool
    ) {
        guard requestedInteractionEnabled != isEnabled else {
            return
        }
        requestedInteractionEnabled = isEnabled
        if !isEnabled {
            cancelInteraction()
        }
        updateInteractionState()
    }

    /// Updates effect layout and the interactive region.
    override func layoutSubviews() {
        super.layoutSubviews()
        renderer.view.frame = bounds
        updateInteractionState()
    }

    /// Checks whether a touch is within visible interactive video.
    ///
    /// - Parameters:
    ///   - point: The point in overlay coordinates.
    ///   - event: The hit-testing event.
    ///
    /// - Returns: `true` if the point is within the view and valid video region.
    override func point(
        inside point: CGPoint,
        with event: UIEvent?
    ) -> Bool {
        guard
            super.point(
                inside: point,
                with: event
            ),
            let interactionFrame
        else {
            return false
        }
        return interactionFrame.contains(point)
    }

    /// Begins trajectories and submits their initial samples.
    ///
    /// - Parameters:
    ///   - touches: The newly started touches.
    ///   - event: The UIKit event.
    override func touchesBegan(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesBegan(
            touches,
            with: event
        )
        let timestamp = CACurrentMediaTime()
        let points = touches.map { touch -> TrajectoryPoint in
            let location = clamped(touch.location(in: self))
            let activeTouch = ActiveTouch(
                id: TrajectoryID(),
                location: location
            )
            activeTouches[ObjectIdentifier(touch)] = activeTouch
            return trajectoryPoint(
                for: activeTouch,
                timestamp: timestamp
            )
        }
        renderer.renderBegan(points)
        submitIfNeeded(
            now: timestamp,
            force: true
        )
        startDisplayLink()
    }

    /// Updates moved touches and trajectory samples.
    ///
    /// - Parameters:
    ///   - touches: The moved touches.
    ///   - event: The UIKit event.
    override func touchesMoved(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesMoved(
            touches,
            with: event
        )
        let timestamp = CACurrentMediaTime()
        var began: [TrajectoryPoint] = []
        var moved: [TrajectoryPoint] = []

        for touch in touches {
            let key = ObjectIdentifier(touch)
            let location = clamped(touch.location(in: self))
            if var activeTouch = activeTouches[key] {
                let dx = location.x - activeTouch.location.x
                let dy = location.y - activeTouch.location.y
                guard dx * dx + dy * dy >= 0.25 else {
                    continue
                }
                activeTouch.location = location
                activeTouches[key] = activeTouch
                moved.append(
                    trajectoryPoint(
                        for: activeTouch,
                        timestamp: timestamp
                    )
                )
            } else {
                let activeTouch = ActiveTouch(
                    id: TrajectoryID(),
                    location: location
                )
                activeTouches[key] = activeTouch
                began.append(
                    trajectoryPoint(
                        for: activeTouch,
                        timestamp: timestamp
                    )
                )
            }
        }

        if !began.isEmpty {
            renderer.renderBegan(began)
        }
        if !moved.isEmpty {
            renderer.renderMoved(moved)
        }
        if !began.isEmpty || !moved.isEmpty {
            startDisplayLink()
        }
    }

    /// Ends trajectories for released touches.
    ///
    /// - Parameters:
    ///   - touches: The ended touches.
    ///   - event: The UIKit event.
    override func touchesEnded(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesEnded(
            touches,
            with: event
        )
        finish(touches)
    }

    /// Ends system-cancelled touch trajectories.
    ///
    /// - Parameters:
    ///   - touches: The cancelled touches.
    ///   - event: The UIKit event.
    override func touchesCancelled(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesCancelled(
            touches,
            with: event
        )
        finish(touches)
    }
}

private extension TrajectoryOverlayView {

    /// Removes ended touches and stops sampling when none remain.
    ///
    /// - Parameter touches: The touches to end.
    func finish(
        _ touches: Set<UITouch>
    ) {
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

    /// Submits active touches at the sampling interval.
    ///
    /// - Parameters:
    ///   - now: The monotonic time, in seconds.
    ///   - force: Whether to bypass the sampling interval.
    func submitIfNeeded(
        now: TimeInterval,
        force: Bool = false
    ) {
        let points = activeTouches.values.map(\.location)
        guard !points.isEmpty else {
            return
        }
        if !force,
            let lastSampleTime,
            now - lastSampleTime < Sampling.interval
        {
            return
        }
        lastSampleTime = now
        binding?.submit(
            points: points,
            viewportSize: bounds.size
        )
    }

    /// Clears active touches, sampling, and effects.
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

    /// Starts continuous trajectory sampling.
    func startDisplayLink() {
        guard displayLink == nil else {
            return
        }
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(displayLinkDidTick)
        )
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(
            to: .main,
            forMode: .common
        )
        self.displayLink = displayLink
    }

    /// Stops trajectory sampling refresh.
    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Samples trajectories on display refresh.
    @objc func displayLinkDidTick() {
        submitIfNeeded(now: CACurrentMediaTime())
        if activeTouches.isEmpty {
            stopDisplayLink()
        }
    }

    /// Updates interaction availability for the binding and video region.
    func updateInteractionState() {
        isUserInteractionEnabled =
            requestedInteractionEnabled
            && binding != nil
            && interactionFrame != nil
    }

    /// Installs the effect view without intercepting touches.
    ///
    /// - Parameter renderer: The renderer providing the effect view.
    func installRendererView(
        _ renderer: any TrajectoryEffectRendering
    ) {
        let rendererView = renderer.view
        rendererView.frame = bounds
        rendererView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        rendererView.isUserInteractionEnabled = false
        addSubview(rendererView)
    }

    /// Creates an effect sample from an active touch.
    ///
    /// - Parameters:
    ///   - activeTouch: The active touch.
    ///   - timestamp: The monotonic sample time, in seconds.
    ///
    /// - Returns: A touch with viewport and normalized resolved-media positions.
    private func trajectoryPoint(
        for activeTouch: ActiveTouch,
        timestamp: TimeInterval
    ) -> TrajectoryPoint {
        let normalizationFrame = displayedMediaFrame ?? bounds
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

    /// Clamps a touch to the interactive video region.
    ///
    /// - Parameter point: The overlay point to clamp.
    ///
    /// - Returns: The clamped point, or the original if no region exists.
    func clamped(
        _ point: CGPoint
    ) -> CGPoint {
        guard let interactionFrame else {
            return point
        }
        return CGPoint(
            x: min(
                max(
                    point.x,
                    interactionFrame.minX
                ),
                interactionFrame.maxX
            ),
            y: min(
                max(
                    point.y,
                    interactionFrame.minY
                ),
                interactionFrame.maxY
            )
        )
    }

    /// The full media rectangle for the resolved aspect ratio and content mode.
    var displayedMediaFrame: CGRect? {
        guard let resolvedMediaSize else {
            return nil
        }
        return InteractionCoordinateMapper.displayedFrame(
            viewportSize: bounds.size,
            resolvedMediaSize: resolvedMediaSize,
            contentMode: videoContentMode
        )
    }

    /// The intersection of the media rectangle and view bounds.
    var interactionFrame: CGRect? {
        guard let displayedMediaFrame else {
            return nil
        }
        let frame = displayedMediaFrame.intersection(bounds)
        return frame.isNull || frame.isEmpty ? nil : frame
    }
}
