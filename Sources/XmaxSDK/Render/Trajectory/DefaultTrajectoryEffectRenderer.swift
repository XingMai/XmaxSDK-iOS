//
//  DefaultTrajectoryEffectRenderer.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit

/// The built-in glowing trajectory effect.
@MainActor
public final class DefaultTrajectoryEffectRenderer: UIView,
    TrajectoryEffectRendering
{

    /// The trajectory appearance and fade configuration.
    private enum Style {

        /// The trajectory centerline color.
        static let coreColor = UIColor.white

        /// The trajectory glow color.
        static let glowColor = UIColor(
            red: 0,
            green: 1,
            blue: 100.0 / 255.0,
            alpha: 1
        )

        /// The centerline width, in points.
        static let coreWidth: CGFloat = 3

        /// The glow width, in points.
        static let glowWidth: CGFloat = 18

        /// The trail opacity decay per refresh.
        static let fadeStep: CGFloat = 0.05

        /// The maximum fade frames after interaction stops.
        static let idleFadeFrameLimit = 64
    }

    /// An active trajectory's position and start time.
    private struct ActiveTrajectory {

        /// The latest trajectory position in view coordinates.
        var location: CGPoint

        /// The pulse animation start time, in seconds.
        let startTime: TimeInterval
    }

    /// The trajectory effect view.
    public var view: UIView {
        self
    }

    /// Trajectory drawing.

    /// The active touches and animation origins keyed by trajectory identifier.
    private var activeTrajectories: [TrajectoryID: ActiveTrajectory] = [:]

    /// The persistent trail bitmap context.
    private var trailBitmapContext: CGContext?

    /// The trail bitmap's view dimensions, in points.
    private var trailBitmapSize: CGSize = .zero

    /// The trail bitmap's display scale.
    private var trailBitmapScale: CGFloat = 0

    /// Whether the trail bitmap contains visible content.
    private var hasTrailPixels = false

    /// Animation state.

    /// The elapsed fade frames since interaction ended.
    private var idleFadeFrameCount = 0

    /// The trajectory animation display link.
    private var displayLink: CADisplayLink?

    /// Creates the built-in glowing trajectory view.
    ///
    /// - Parameter frame: The initial view frame.
    public override init(
        frame: CGRect = .zero
    ) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    /// Unavailable; create this effect view programmatically.
    ///
    /// - Parameter coder: The archive decoder.
    @available(*, unavailable)
    public required init?(
        coder: NSCoder
    ) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Stops trajectory display refresh.
    isolated deinit {
        displayLink?.invalidate()
    }

    /// Updates the trajectory bitmap for the view dimensions.
    public override func layoutSubviews() {
        super.layoutSubviews()
        rebuildTrailBitmapIfNeeded()
    }

    /// Prepares or clears trajectories when window attachment changes.
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            reset()
        } else {
            rebuildTrailBitmapIfNeeded()
        }
    }

    /// Begins trajectories for new touches.
    ///
    /// - Parameter points: The newly started touches.
    public func renderBegan(
        _ points: [TrajectoryPoint]
    ) {
        for point in points {
            activeTrajectories[point.id] = ActiveTrajectory(
                location: point.location,
                startTime: point.timestamp
            )
        }
        startDisplayLink()
        setNeedsDisplay()
    }

    /// Updates active trajectory positions.
    ///
    /// - Parameter points: The latest active touches.
    public func renderMoved(
        _ points: [TrajectoryPoint]
    ) {
        for point in points {
            guard var trajectory = activeTrajectories[point.id] else {
                activeTrajectories[point.id] = ActiveTrajectory(
                    location: point.location,
                    startTime: point.timestamp
                )
                continue
            }

            let dx = point.location.x - trajectory.location.x
            let dy = point.location.y - trajectory.location.y
            if dx * dx + dy * dy >= 0.25 {
                drawTrailSegment(
                    from: trajectory.location,
                    to: point.location
                )
            }
            trajectory.location = point.location
            activeTrajectories[point.id] = trajectory
        }
        startDisplayLink()
    }

    /// Ends active trajectories.
    ///
    /// - Parameter identifiers: The trajectory identifiers to end.
    public func renderEnded(
        _ identifiers: [TrajectoryID]
    ) {
        identifiers.forEach {
            activeTrajectories.removeValue(forKey: $0)
        }
        setNeedsDisplay()
    }

    /// Clears all trajectories and animation resources.
    public func reset() {
        activeTrajectories.removeAll()
        clearTrailBitmap()
        stopDisplayLink()
        setNeedsDisplay()
    }

    /// Draws the trail bitmap and active touch effects.
    ///
    /// - Parameter rect: The view region to redraw.
    public override func draw(
        _ rect: CGRect
    ) {
        if let trailImage = trailBitmapContext?.makeImage() {
            UIImage(
                cgImage: trailImage,
                scale: trailBitmapScale,
                orientation: .up
            ).draw(
                in: bounds
            )
        }

        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.saveGState()
        context.setBlendMode(.plusLighter)
        drawTouchEffects(
            now: CACurrentMediaTime(),
            in: context
        )
        context.restoreGState()
    }
}

private extension DefaultTrajectoryEffectRenderer {

    /// Advances fading and stops refresh when no effect remains.
    @objc func tick() {
        fadeTrailBitmap()
        setNeedsDisplay()
        if activeTrajectories.isEmpty, !hasTrailPixels {
            stopDisplayLink()
        }
    }

    /// Starts trajectory display refresh.
    func startDisplayLink() {
        guard displayLink == nil else {
            return
        }
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(tick)
        )
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(
            to: .main,
            forMode: .common
        )
        self.displayLink = displayLink
    }

    /// Stops trajectory display refresh.
    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Resolves a trajectory bitmap for the view dimensions and display scale.
    func rebuildTrailBitmapIfNeeded() {
        let scale = window?.screen.scale ?? traitCollection.displayScale
        let pixelWidth = Int(ceil(bounds.width * scale))
        let pixelHeight = Int(ceil(bounds.height * scale))
        guard pixelWidth > 0, pixelHeight > 0 else {
            return
        }

        let bitmapSize = CGSize(
            width: pixelWidth,
            height: pixelHeight
        )
        guard
            trailBitmapContext == nil
                || trailBitmapSize != bitmapSize
                || trailBitmapScale != scale
        else {
            return
        }

        let bitmapInfo =
            CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            )
        else {
            return
        }

        context.translateBy(
            x: 0,
            y: CGFloat(pixelHeight)
        )
        context.scaleBy(
            x: scale,
            y: -scale
        )
        trailBitmapContext = context
        trailBitmapSize = bitmapSize
        trailBitmapScale = scale
        hasTrailPixels = false
        idleFadeFrameCount = 0
    }

    /// Draws a glowing segment into the trail bitmap.
    ///
    /// - Parameters:
    ///   - start: The segment start in view coordinates.
    ///   - end: The segment end in view coordinates.
    func drawTrailSegment(
        from start: CGPoint,
        to end: CGPoint
    ) {
        rebuildTrailBitmapIfNeeded()
        guard let context = trailBitmapContext else {
            return
        }

        context.saveGState()
        context.setBlendMode(.plusLighter)
        drawGlowLayer(
            from: start,
            to: end,
            width: Style.glowWidth,
            blur: Style.glowWidth * 2 / 3,
            alpha: 0.22,
            in: context
        )
        drawGlowLayer(
            from: start,
            to: end,
            width: Style.glowWidth * 5 / 9,
            blur: Style.glowWidth / 3,
            alpha: 0.52,
            in: context
        )

        context.setShadow(
            offset: .zero,
            blur: 0,
            color: nil
        )
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(Style.coreWidth)
        context.setStrokeColor(
            Style.coreColor.withAlphaComponent(0.82).cgColor
        )
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()

        hasTrailPixels = true
        idleFadeFrameCount = 0
        setNeedsDisplay()
    }

    /// Draws a glowing segment with the requested appearance.
    ///
    /// - Parameters:
    ///   - start: The segment start.
    ///   - end: The segment end.
    ///   - width: The line width, in points.
    ///   - blur: The shadow blur radius, in points.
    ///   - alpha: The glow opacity.
    ///   - context: The drawing context.
    func drawGlowLayer(
        from start: CGPoint,
        to end: CGPoint,
        width: CGFloat,
        blur: CGFloat,
        alpha: CGFloat,
        in context: CGContext
    ) {
        guard width > 0, Style.glowColor != .clear else {
            return
        }
        let color = Style.glowColor.withAlphaComponent(alpha)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(width)
        context.setStrokeColor(color.cgColor)
        if blur > 0 {
            context.setShadow(
                offset: .zero,
                blur: blur,
                color: color.cgColor
            )
        }
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    /// Fades accumulated trails and clears the bitmap when fading completes.
    func fadeTrailBitmap() {
        guard hasTrailPixels, let context = trailBitmapContext else {
            return
        }
        context.saveGState()
        context.setBlendMode(.destinationOut)
        context.setFillColor(
            UIColor.black.withAlphaComponent(Style.fadeStep).cgColor
        )
        context.fill(bounds)
        context.restoreGState()

        if activeTrajectories.isEmpty {
            idleFadeFrameCount += 1
            if idleFadeFrameCount > Style.idleFadeFrameLimit {
                clearTrailBitmap()
            }
        } else {
            idleFadeFrameCount = 0
        }
    }

    /// Clears the trail bitmap and fade state.
    func clearTrailBitmap() {
        if let context = trailBitmapContext {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fill(bounds)
            context.restoreGState()
        }
        hasTrailPixels = false
        idleFadeFrameCount = 0
    }

    /// Draws active touch halos, particles, and highlights.
    ///
    /// - Parameters:
    ///   - now: The monotonic time, in seconds.
    ///   - context: The drawing context.
    func drawTouchEffects(
        now: TimeInterval,
        in context: CGContext
    ) {
        for trajectory in activeTrajectories.values {
            drawPulsingRings(
                for: trajectory,
                now: now,
                in: context
            )
            drawOrbitParticles(
                for: trajectory,
                now: now,
                in: context
            )
            drawHeadGlow(
                at: trajectory.location,
                in: context
            )
        }
    }

    /// Draws a touch highlight and radial glow.
    ///
    /// - Parameters:
    ///   - point: The touch position in view coordinates.
    ///   - context: The drawing context.
    func drawHeadGlow(
        at point: CGPoint,
        in context: CGContext
    ) {
        let headRadius = max(
            Style.coreWidth * 5 / 3,
            3
        )
        let glowRadius = max(
            Style.glowWidth * 8 / 9,
            headRadius
        )
        let colors =
            [
                Style.glowColor.withAlphaComponent(0.9).cgColor,
                Style.glowColor.withAlphaComponent(0.54).cgColor,
                Style.glowColor.withAlphaComponent(0).cgColor,
            ] as CFArray
        if Style.glowWidth > 0,
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.4, 1]
            )
        {
            context.drawRadialGradient(
                gradient,
                startCenter: point,
                startRadius: 0,
                endCenter: point,
                endRadius: glowRadius,
                options: []
            )
        }

        context.setFillColor(Style.coreColor.cgColor)
        context.fillEllipse(
            in: CGRect(
                x: point.x - headRadius,
                y: point.y - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            )
        )
    }

    /// Draws a pulsing halo for an active trajectory.
    ///
    /// - Parameters:
    ///   - trajectory: The active trajectory to draw.
    ///   - now: The monotonic time, in seconds.
    ///   - context: The drawing context.
    private func drawPulsingRings(
        for trajectory: ActiveTrajectory,
        now: TimeInterval,
        in context: CGContext
    ) {
        let elapsed = CGFloat(now - trajectory.startTime)
        context.setLineWidth(2)
        for index in 0..<2 {
            let indexValue = CGFloat(index)
            let baseRadius = 14 + indexValue * 18
            let pulseOffset = elapsed * 1.2 + indexValue * 0.5
            let pulse = (sin(pulseOffset * .pi * 2) + 1) / 2
            let radius = baseRadius + pulse * 8
            let alpha =
                0.5
                * (1 - indexValue * 0.2)
                * (0.5 + pulse * 0.5)
            context.setStrokeColor(
                Style.glowColor.withAlphaComponent(alpha).cgColor
            )
            context.strokeEllipse(
                in: CGRect(
                    x: trajectory.location.x - radius,
                    y: trajectory.location.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
        }
    }

    /// Draws glowing particles around a touch.
    ///
    /// - Parameters:
    ///   - trajectory: The active trajectory to draw.
    ///   - now: The monotonic time, in seconds.
    ///   - context: The drawing context.
    private func drawOrbitParticles(
        for trajectory: ActiveTrajectory,
        now: TimeInterval,
        in context: CGContext
    ) {
        let elapsed = CGFloat(now - trajectory.startTime)
        for index in 0..<4 {
            let indexValue = CGFloat(index)
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let baseAngle = indexValue / 4 * .pi * 2
            let angle = baseAngle + elapsed * 0.06 * direction
            let center = CGPoint(
                x: trajectory.location.x + cos(angle) * 22,
                y: trajectory.location.y + sin(angle) * 22
            )
            let alpha =
                0.6
                * (0.6 + sin(elapsed * 3 + indexValue) * 0.4)
            drawParticle(
                at: center,
                alpha: alpha,
                in: context
            )
        }
    }

    /// Draws a radial gradient particle.
    ///
    /// - Parameters:
    ///   - point: The particle center in view coordinates.
    ///   - alpha: The particle center opacity.
    ///   - context: The drawing context.
    func drawParticle(
        at point: CGPoint,
        alpha: CGFloat,
        in context: CGContext
    ) {
        let colors =
            [
                Style.glowColor.withAlphaComponent(alpha).cgColor,
                Style.glowColor.withAlphaComponent(0).cgColor,
            ] as CFArray
        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            )
        else {
            return
        }
        context.drawRadialGradient(
            gradient,
            startCenter: point,
            startRadius: 0,
            endCenter: point,
            endRadius: 6,
            options: []
        )
    }
}
