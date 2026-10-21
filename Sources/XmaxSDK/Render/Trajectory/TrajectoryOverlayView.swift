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

/// 采集多指触摸、驱动轨迹效果并按固定频率提交交互帧。
@MainActor
final class TrajectoryOverlayView: UIView {

    /// 定义触控轨迹的提交频率。
    private enum Sampling {

        /// 轨迹发送采样的最小间隔，单位为秒。
        static let interval: TimeInterval = 1.0 / 30.0
    }

    /// 保存一个活动触点的稳定标识与当前位置。
    private struct ActiveTouch {

        /// 触点对应的稳定轨迹标识。
        let id: TrajectoryID

        /// 触点在覆盖层中的位置，单位为点。
        var location: CGPoint
    }

    /// 按系统触摸对象保存的活动触点。
    private var activeTouches: [ObjectIdentifier: ActiveTouch] = [:]

    /// 将采样结果交付媒体交互层的绑定。
    private weak var binding: TrajectoryBinding?

    /// 视频在视图中的填充方式。
    private var videoContentMode: VideoContentMode = .fill

    /// 用于计算完整媒体显示区域的处理后尺寸。
    private var resolvedMediaSize: CGSize?

    /// 绘制触点和轨迹效果的渲染器。
    private var renderer: any TrajectoryEffectRendering

    /// 接入方设置的轨迹交互开关。
    private var requestedInteractionEnabled = true

    /// 最近一次发送采样的时刻，单位为秒。
    private var lastSampleTime: TimeInterval?

    /// 驱动轨迹采样和效果更新的显示时钟。
    private var displayLink: CADisplayLink?

    /// 创建多点触控采样和轨迹效果覆盖层。
    ///
    /// - Parameter renderer: 负责触点和轨迹视觉表现的渲染器。
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

    /// 标记归档初始化不可用；轨迹覆盖层需指定渲染器创建。
    ///
    /// - Parameter coder: 视图归档解码器。
    @available(*, unavailable)
    required init?(
        coder: NSCoder
    ) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 结束轨迹采样的显示刷新回调。
    isolated deinit {
        displayLink?.invalidate()
    }

    /// 清除当前轨迹并替换视觉效果渲染器。
    ///
    /// - Parameter renderer: 新的轨迹效果渲染器。
    func setRenderer(
        _ renderer: any TrajectoryEffectRendering
    ) {
        cancelInteraction()
        self.renderer.reset()
        self.renderer.view.removeFromSuperview()
        self.renderer = renderer
        installRendererView(renderer)
    }

    /// 设置轨迹提交绑定，并同步交互可用状态。
    ///
    /// - Parameter binding: 媒体交互绑定；传入 `nil` 清除当前轨迹。
    func setBinding(
        _ binding: TrajectoryBinding?
    ) {
        self.binding = binding
        if binding == nil {
            cancelInteraction()
        }
        updateInteractionState()
    }

    /// 更新视频显示模式并清除旧坐标下的活动轨迹。
    ///
    /// - Parameter contentMode: 新的缩放与裁剪方式。
    func setContentMode(
        _ contentMode: VideoContentMode
    ) {
        guard videoContentMode != contentMode else { return }
        videoContentMode = contentMode
        cancelInteraction()
        updateInteractionState()
    }

    /// 更新处理后的媒体尺寸并清除旧坐标下的活动轨迹。
    ///
    /// - Parameter resolvedMediaSize: 处理后的本地媒体尺寸；未知时为 `nil`。
    func setResolvedMediaSize(
        _ resolvedMediaSize: CGSize?
    ) {
        guard self.resolvedMediaSize != resolvedMediaSize else { return }
        self.resolvedMediaSize = resolvedMediaSize
        cancelInteraction()
        updateInteractionState()
    }

    /// 设置调用方期望的交互开关。
    ///
    /// - Parameter isEnabled: 是否允许触控轨迹交互。
    func setRequestedInteractionEnabled(
        _ isEnabled: Bool
    ) {
        guard requestedInteractionEnabled != isEnabled else { return }
        requestedInteractionEnabled = isEnabled
        if !isEnabled {
            cancelInteraction()
        }
        updateInteractionState()
    }

    /// 更新效果视图尺寸和可交互区域。
    override func layoutSubviews() {
        super.layoutSubviews()
        renderer.view.frame = bounds
        updateInteractionState()
    }

    /// 判断触点是否落在可见视频交互区域。
    ///
    /// - Parameters:
    ///   - point: 覆盖层坐标系中的触点。
    ///   - event: 当前命中测试事件。
    /// - Returns: 触点同时位于视图和有效视频区域时返回 `true`。
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

    /// 登记新触点并立即绘制和提交首个采样。
    ///
    /// - Parameters:
    ///   - touches: 本次开始的触摸集合。
    ///   - event: 对应的 UIKit 事件。
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

    /// 更新移动触点并驱动轨迹绘制和采样。
    ///
    /// - Parameters:
    ///   - touches: 本次移动的触摸集合。
    ///   - event: 对应的 UIKit 事件。
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

    /// 结束已抬起触点的轨迹。
    ///
    /// - Parameters:
    ///   - touches: 本次结束的触摸集合。
    ///   - event: 对应的 UIKit 事件。
    override func touchesEnded(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesEnded(touches, with: event)
        finish(touches)
    }

    /// 结束系统取消的触点轨迹。
    ///
    /// - Parameters:
    ///   - touches: 本次取消的触摸集合。
    ///   - event: 对应的 UIKit 事件。
    override func touchesCancelled(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        super.touchesCancelled(touches, with: event)
        finish(touches)
    }
}

private extension TrajectoryOverlayView {

    /// 移除结束触点，并在无活动触点时停止采样。
    ///
    /// - Parameter touches: 需要结束的触摸集合。
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

    /// 按采样间隔提交当前所有活动触点。
    ///
    /// - Parameters:
    ///   - now: 当前单调时钟时间，单位为秒。
    ///   - force: 是否跳过采样间隔限制立即提交。
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

    /// 清空活动触点、采样状态和全部视觉效果。
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

    /// 启动用于连续轨迹采样的显示刷新回调。
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

    /// 停止轨迹采样的显示刷新回调。
    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// 在屏幕刷新时尝试提交轨迹采样。
    @objc func displayLinkDidTick() {
        submitIfNeeded(now: CACurrentMediaTime())
        if activeTouches.isEmpty {
            stopDisplayLink()
        }
    }

    /// 根据调用方配置、绑定和视频区域更新触摸可用性。
    func updateInteractionState() {
        isUserInteractionEnabled = requestedInteractionEnabled
            && binding != nil
            && interactionFrame != nil
    }

    /// 将轨迹效果视图安装为不拦截触摸的子视图。
    ///
    /// - Parameter renderer: 提供视觉视图的轨迹效果渲染器。
    func installRendererView(
        _ renderer: any TrajectoryEffectRendering
    ) {
        let rendererView = renderer.view
        rendererView.frame = bounds
        rendererView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        rendererView.isUserInteractionEnabled = false
        addSubview(rendererView)
    }

    /// 将活动触点转换为效果渲染器使用的采样模型。
    ///
    /// - Parameters:
    ///   - activeTouch: 当前活动触点。
    ///   - timestamp: 采样单调时钟时间，单位为秒。
    /// - Returns: 包含视口坐标和相对于处理后完整媒体区域的归一化坐标的触点。
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

    /// 将触点约束到当前可交互的视频区域。
    ///
    /// - Parameter point: 待约束的覆盖层坐标。
    /// - Returns: 约束后的触点；没有交互区域时保留原位置。
    func clamped(
        _ point: CGPoint
    ) -> CGPoint {
        guard let interactionFrame else { return point }
        return CGPoint(
            x: min(max(point.x, interactionFrame.minX), interactionFrame.maxX),
            y: min(max(point.y, interactionFrame.minY), interactionFrame.maxY)
        )
    }

    /// 按处理后媒体比例及填充方式计算的完整显示区域。
    var displayedMediaFrame: CGRect? {
        guard let resolvedMediaSize else { return nil }
        return InteractionCoordinateMapper.displayedFrame(
            viewportSize: bounds.size,
            resolvedMediaSize: resolvedMediaSize,
            contentMode: videoContentMode
        )
    }

    /// 媒体显示区域与视图边界的交集，用于限制有效触摸范围。
    var interactionFrame: CGRect? {
        guard let displayedMediaFrame else { return nil }
        let frame = displayedMediaFrame.intersection(bounds)
        return frame.isNull || frame.isEmpty ? nil : frame
    }
}
