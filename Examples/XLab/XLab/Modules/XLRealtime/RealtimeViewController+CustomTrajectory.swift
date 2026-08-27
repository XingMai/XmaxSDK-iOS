import UIKit
import XmaxSDK

enum RealtimeTrajectoryStyle {
    case sdkDefault
    case xLabCustom
}

extension RealtimeViewController {
    @MainActor
    static func makeCustomTrajectoryRenderer()
        -> any TrajectoryEffectRendering {
        XLabTrajectoryRenderer()
    }
}

/// 与 SDK 内置实现保持一致，并以蓝、粉双色区分多指轨迹。
@MainActor
private final class XLabTrajectoryRenderer: UIView,
    TrajectoryEffectRendering {

    private enum Style {
        static let palette: [(core: UIColor, glow: UIColor)] = [
            (
                core: UIColor(
                    red: 1,
                    green: 0.9,
                    blue: 0.98,
                    alpha: 1
                ),
                glow: UIColor(
                    red: 1,
                    green: 0.18,
                    blue: 0.72,
                    alpha: 1
                )
            ),
            (
                core: UIColor(
                    red: 0.9,
                    green: 0.98,
                    blue: 1,
                    alpha: 1
                ),
                glow: UIColor(
                    red: 0.14,
                    green: 0.74,
                    blue: 1,
                    alpha: 1
                )
            ),
        ]
        static let coreWidth: CGFloat = 3
        static let glowWidth: CGFloat = 18
        static let fadeStep: CGFloat = 0.05
        static let idleFadeFrameLimit = 64
    }

    private struct ActiveTrajectory {
        var location: CGPoint
        let startTime: TimeInterval
        let coreColor: UIColor
        let glowColor: UIColor
    }

    var view: UIView { self }

    private var activeTrajectories: [TrajectoryID: ActiveTrajectory] = [:]
    private var trailBitmapContext: CGContext?
    private var trailBitmapSize: CGSize = .zero
    private var trailBitmapScale: CGFloat = 0
    private var hasTrailPixels = false
    private var idleFadeFrameCount = 0
    private var displayLink: CADisplayLink?
    private var nextPaletteIndex = 0

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        displayLink?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildTrailBitmapIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            reset()
        } else {
            rebuildTrailBitmapIfNeeded()
        }
    }

    func renderBegan(_ points: [TrajectoryPoint]) {
        for point in points {
            activeTrajectories[point.id] = makeTrajectory(for: point)
        }
        startDisplayLink()
        setNeedsDisplay()
    }

    func renderMoved(_ points: [TrajectoryPoint]) {
        for point in points {
            guard var trajectory = activeTrajectories[point.id] else {
                activeTrajectories[point.id] = makeTrajectory(for: point)
                continue
            }

            let dx = point.location.x - trajectory.location.x
            let dy = point.location.y - trajectory.location.y
            if dx * dx + dy * dy >= 0.25 {
                drawTrailSegment(
                    from: trajectory.location,
                    to: point.location,
                    coreColor: trajectory.coreColor,
                    glowColor: trajectory.glowColor
                )
            }
            trajectory.location = point.location
            activeTrajectories[point.id] = trajectory
        }
        startDisplayLink()
    }

    func renderEnded(_ identifiers: [TrajectoryID]) {
        identifiers.forEach {
            activeTrajectories.removeValue(forKey: $0)
        }
        setNeedsDisplay()
    }

    func reset() {
        activeTrajectories.removeAll()
        nextPaletteIndex = 0
        clearTrailBitmap()
        stopDisplayLink()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        if let trailImage = trailBitmapContext?.makeImage() {
            UIImage(
                cgImage: trailImage,
                scale: trailBitmapScale,
                orientation: .up
            ).draw(in: bounds)
        }

        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setBlendMode(.plusLighter)
        drawTouchEffects(now: CACurrentMediaTime(), in: context)
        context.restoreGState()
    }
}

private extension XLabTrajectoryRenderer {
    private func makeTrajectory(
        for point: TrajectoryPoint
    ) -> ActiveTrajectory {
        let colors = Style.palette[nextPaletteIndex % Style.palette.count]
        nextPaletteIndex += 1
        return ActiveTrajectory(
            location: point.location,
            startTime: point.timestamp,
            coreColor: colors.core,
            glowColor: colors.glow
        )
    }

    @objc func tick() {
        fadeTrailBitmap()
        setNeedsDisplay()
        if activeTrajectories.isEmpty, !hasTrailPixels {
            stopDisplayLink()
        }
    }

    func startDisplayLink() {
        guard displayLink == nil else { return }
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(tick)
        )
        displayLink.preferredFramesPerSecond = 60
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func rebuildTrailBitmapIfNeeded() {
        let scale = window?.screen.scale ?? traitCollection.displayScale
        let pixelWidth = Int(ceil(bounds.width * scale))
        let pixelHeight = Int(ceil(bounds.height * scale))
        guard pixelWidth > 0, pixelHeight > 0 else { return }

        let bitmapSize = CGSize(width: pixelWidth, height: pixelHeight)
        guard trailBitmapContext == nil
                || trailBitmapSize != bitmapSize
                || trailBitmapScale != scale
        else {
            return
        }

        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return
        }

        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        trailBitmapContext = context
        trailBitmapSize = bitmapSize
        trailBitmapScale = scale
        hasTrailPixels = false
        idleFadeFrameCount = 0
    }

    func drawTrailSegment(
        from start: CGPoint,
        to end: CGPoint,
        coreColor: UIColor,
        glowColor: UIColor
    ) {
        rebuildTrailBitmapIfNeeded()
        guard let context = trailBitmapContext else { return }

        context.saveGState()
        context.setBlendMode(.plusLighter)
        drawGlowLayer(
            from: start,
            to: end,
            width: Style.glowWidth,
            blur: Style.glowWidth * 2 / 3,
            alpha: 0.22,
            color: glowColor,
            in: context
        )
        drawGlowLayer(
            from: start,
            to: end,
            width: Style.glowWidth * 5 / 9,
            blur: Style.glowWidth / 3,
            alpha: 0.52,
            color: glowColor,
            in: context
        )

        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(Style.coreWidth)
        context.setStrokeColor(
            coreColor.withAlphaComponent(0.82).cgColor
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

    func drawGlowLayer(
        from start: CGPoint,
        to end: CGPoint,
        width: CGFloat,
        blur: CGFloat,
        alpha: CGFloat,
        color: UIColor,
        in context: CGContext
    ) {
        guard width > 0, color != .clear else { return }
        let color = color.withAlphaComponent(alpha)
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

    func fadeTrailBitmap() {
        guard hasTrailPixels, let context = trailBitmapContext else { return }
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

    func drawTouchEffects(
        now: TimeInterval,
        in context: CGContext
    ) {
        for trajectory in activeTrajectories.values {
            drawPulsingRings(for: trajectory, now: now, in: context)
            drawOrbitParticles(for: trajectory, now: now, in: context)
            drawHeadGlow(
                at: trajectory.location,
                coreColor: trajectory.coreColor,
                glowColor: trajectory.glowColor,
                in: context
            )
        }
    }

    func drawHeadGlow(
        at point: CGPoint,
        coreColor: UIColor,
        glowColor: UIColor,
        in context: CGContext
    ) {
        let headRadius = max(Style.coreWidth * 5 / 3, 3)
        let glowRadius = max(Style.glowWidth * 8 / 9, headRadius)
        let colors = [
            glowColor.withAlphaComponent(0.9).cgColor,
            glowColor.withAlphaComponent(0.54).cgColor,
            glowColor.withAlphaComponent(0).cgColor,
        ] as CFArray
        if Style.glowWidth > 0,
           let gradient = CGGradient(
               colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: colors,
               locations: [0, 0.4, 1]
           ) {
            context.drawRadialGradient(
                gradient,
                startCenter: point,
                startRadius: 0,
                endCenter: point,
                endRadius: glowRadius,
                options: []
            )
        }

        context.setFillColor(coreColor.cgColor)
        context.fillEllipse(
            in: CGRect(
                x: point.x - headRadius,
                y: point.y - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            )
        )
    }

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
            let alpha = 0.5
                * (1 - indexValue * 0.2)
                * (0.5 + pulse * 0.5)
            context.setStrokeColor(
                trajectory.glowColor.withAlphaComponent(alpha).cgColor
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
            let alpha = 0.6
                * (0.6 + sin(elapsed * 3 + indexValue) * 0.4)
            drawParticle(
                at: center,
                alpha: alpha,
                color: trajectory.glowColor,
                in: context
            )
        }
    }

    func drawParticle(
        at point: CGPoint,
        alpha: CGFloat,
        color: UIColor,
        in context: CGContext
    ) {
        let colors = [
            color.withAlphaComponent(alpha).cgColor,
            color.withAlphaComponent(0).cgColor,
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        ) else {
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
