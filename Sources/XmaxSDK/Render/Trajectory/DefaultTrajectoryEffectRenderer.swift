//
//  DefaultTrajectoryEffectRenderer.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit

/// SDK 内置的发光轨迹效果。
@MainActor
public final class DefaultTrajectoryEffectRenderer: UIView,
    TrajectoryEffectRendering {

    /// 定义轨迹颜色、线宽及淡出效果参数。
    private enum Style {

        /// 效果颜色
        static let coreColor = UIColor.white
        static let glowColor = UIColor(
            red: 0,
            green: 1,
            blue: 100.0 / 255.0,
            alpha: 1
        )

        /// 轨迹宽度
        static let coreWidth: CGFloat = 3
        static let glowWidth: CGFloat = 18

        /// 淡出配置
        static let fadeStep: CGFloat = 0.05
        static let idleFadeFrameLimit = 64
    }

    /// 保存活动轨迹的当前位置和开始时间。
    private struct ActiveTrajectory {

        /// 轨迹状态
        var location: CGPoint
        let startTime: TimeInterval
    }

    /// 效果视图
    public var view: UIView { self }

    /// 轨迹资源
    private var activeTrajectories: [TrajectoryID: ActiveTrajectory] = [:]
    private var trailBitmapContext: CGContext?
    private var trailBitmapSize: CGSize = .zero
    private var trailBitmapScale: CGFloat = 0

    /// 动画状态
    private var hasTrailPixels = false
    private var idleFadeFrameCount = 0
    private var displayLink: CADisplayLink?

    /// 创建 SDK 内置发光轨迹渲染视图。
    ///
    /// - Parameter frame: 视图初始布局区域。
    public override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    /// 标记归档初始化不可用；效果视图需通过代码创建。
    ///
    /// - Parameter coder: 视图归档解码器。
    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 结束轨迹动画的显示刷新回调。
    isolated deinit {
        displayLink?.invalidate()
    }

    /// 按当前视图尺寸更新轨迹位图缓冲区。
    public override func layoutSubviews() {
        super.layoutSubviews()
        rebuildTrailBitmapIfNeeded()
    }

    /// 在视图离开窗口时清理轨迹，进入窗口时准备位图。
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            reset()
        } else {
            rebuildTrailBitmapIfNeeded()
        }
    }

    /// 开始绘制指定触点对应的轨迹。
    ///
    /// - Parameter points: 新开始的轨迹触点。
    public func renderBegan(_ points: [TrajectoryPoint]) {
        for point in points {
            activeTrajectories[point.id] = ActiveTrajectory(
                location: point.location,
                startTime: point.timestamp
            )
        }
        startDisplayLink()
        setNeedsDisplay()
    }

    /// 更新活动轨迹的触点位置。
    ///
    /// - Parameter points: 当前活动轨迹的最新触点。
    public func renderMoved(_ points: [TrajectoryPoint]) {
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

    /// 结束指定轨迹的活动绘制。
    ///
    /// - Parameter identifiers: 需要结束的轨迹标识。
    public func renderEnded(_ identifiers: [TrajectoryID]) {
        identifiers.forEach {
            activeTrajectories.removeValue(forKey: $0)
        }
        setNeedsDisplay()
    }

    /// 清除全部轨迹和动画资源。
    public func reset() {
        activeTrajectories.removeAll()
        clearTrailBitmap()
        stopDisplayLink()
        setNeedsDisplay()
    }

    /// 绘制累计轨迹位图和当前触点的动态效果。
    ///
    /// - Parameter rect: 需要重绘的视图区域。
    public override func draw(_ rect: CGRect) {
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

private extension DefaultTrajectoryEffectRenderer {
    /// 推进轨迹淡出并在无可见效果时停止刷新。
    @objc func tick() {
        fadeTrailBitmap()
        setNeedsDisplay()
        if activeTrajectories.isEmpty, !hasTrailPixels {
            stopDisplayLink()
        }
    }

    /// 启动轨迹效果的显示刷新回调。
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

    /// 停止轨迹效果的显示刷新回调。
    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// 按视图尺寸和屏幕缩放系数创建或更新轨迹位图。
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

    /// 向轨迹位图绘制带发光效果的线段。
    ///
    /// - Parameters:
    ///   - start: 线段起点，使用视图坐标。
    ///   - end: 线段终点，使用视图坐标。
    func drawTrailSegment(from start: CGPoint, to end: CGPoint) {
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

        context.setShadow(offset: .zero, blur: 0, color: nil)
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

    /// 绘制指定线宽、模糊半径和透明度的发光线段。
    ///
    /// - Parameters:
    ///   - start: 线段起点。
    ///   - end: 线段终点。
    ///   - width: 线宽，单位为点。
    ///   - blur: 阴影模糊半径，单位为点。
    ///   - alpha: 发光透明度。
    ///   - context: 目标绘图上下文。
    func drawGlowLayer(
        from start: CGPoint,
        to end: CGPoint,
        width: CGFloat,
        blur: CGFloat,
        alpha: CGFloat,
        in context: CGContext
    ) {
        guard width > 0, Style.glowColor != .clear else { return }
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

    /// 逐帧降低累计轨迹的不透明度并清除已淡出的位图。
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

    /// 清空轨迹位图并重置淡出状态。
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

    /// 绘制全部活动触点的光环、粒子和中心亮点。
    ///
    /// - Parameters:
    ///   - now: 当前单调时钟时间，单位为秒。
    ///   - context: 目标绘图上下文。
    func drawTouchEffects(
        now: TimeInterval,
        in context: CGContext
    ) {
        for trajectory in activeTrajectories.values {
            drawPulsingRings(for: trajectory, now: now, in: context)
            drawOrbitParticles(for: trajectory, now: now, in: context)
            drawHeadGlow(at: trajectory.location, in: context)
        }
    }

    /// 绘制触点中心亮点及径向发光。
    ///
    /// - Parameters:
    ///   - point: 触点的视图坐标。
    ///   - context: 目标绘图上下文。
    func drawHeadGlow(at point: CGPoint, in context: CGContext) {
        let headRadius = max(Style.coreWidth * 5 / 3, 3)
        let glowRadius = max(Style.glowWidth * 8 / 9, headRadius)
        let colors = [
            Style.glowColor.withAlphaComponent(0.9).cgColor,
            Style.glowColor.withAlphaComponent(0.54).cgColor,
            Style.glowColor.withAlphaComponent(0).cgColor,
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

    /// 按轨迹持续时间绘制脉动光环。
    ///
    /// - Parameters:
    ///   - trajectory: 需要绘制的活动轨迹。
    ///   - now: 当前单调时钟时间，单位为秒。
    ///   - context: 目标绘图上下文。
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

    /// 绘制围绕触点缓慢运动的发光粒子。
    ///
    /// - Parameters:
    ///   - trajectory: 需要绘制的活动轨迹。
    ///   - now: 当前单调时钟时间，单位为秒。
    ///   - context: 目标绘图上下文。
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
            drawParticle(at: center, alpha: alpha, in: context)
        }
    }

    /// 绘制一个径向渐变的发光粒子。
    ///
    /// - Parameters:
    ///   - point: 粒子中心的视图坐标。
    ///   - alpha: 粒子中心透明度。
    ///   - context: 目标绘图上下文。
    func drawParticle(
        at point: CGPoint,
        alpha: CGFloat,
        in context: CGContext
    ) {
        let colors = [
            Style.glowColor.withAlphaComponent(alpha).cgColor,
            Style.glowColor.withAlphaComponent(0).cgColor,
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
