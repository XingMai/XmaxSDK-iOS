//
//  TrajectoryBinding.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit

/// 将渲染层触摸输入转交给媒体交互层。
final class TrajectoryBinding: @unchecked Sendable {

    /// 接收交互采样帧的异步回调。
    private let interactionListener: RenderInteractionListener

    /// 当前绑定的轨迹覆盖层。
    @MainActor private weak var overlayView: TrajectoryOverlayView?

    /// 当前媒体显示方式，用于触点坐标映射。
    @MainActor private var contentMode: VideoContentMode = .fill

    /// 用于轨迹坐标映射的处理后媒体尺寸。
    private let resolvedMediaSize: CGSize

    /// 创建连接轨迹视图与媒体交互层的绑定。
    init(
        interactionListener: @escaping RenderInteractionListener,
        resolvedMediaSize: CGSize
    ) {
        self.interactionListener = interactionListener
        self.resolvedMediaSize = resolvedMediaSize
    }

    /// 绑定轨迹覆盖层并同步坐标映射配置。
    ///
    /// - Parameters:
    ///   - overlayView: 接收触控输入的轨迹覆盖层。
    ///   - contentMode: 视频缩放与裁剪方式。
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
        overlayView.setResolvedMediaSize(resolvedMediaSize)
    }

    /// 解除指定覆盖层的轨迹绑定。
    ///
    /// - Parameter overlayView: 需要解除绑定的轨迹覆盖层。
    @MainActor
    func detach(
        from overlayView: TrajectoryOverlayView
    ) {
        guard self.overlayView === overlayView else { return }
        self.overlayView = nil
        overlayView.setBinding(nil)
    }

    /// 解除当前轨迹覆盖层并使绑定失效。
    @MainActor
    func invalidate() {
        overlayView?.setBinding(nil)
        overlayView = nil
    }

    /// 更新视频显示模式对应的交互映射。
    ///
    /// - Parameter contentMode: 新的缩放与裁剪方式。
    @MainActor
    func update(
        contentMode: VideoContentMode
    ) {
        self.contentMode = contentMode
        overlayView?.setContentMode(contentMode)
    }

    /// 将视口中的触控点封装为交互帧并异步交付。
    ///
    /// - Parameters:
    ///   - points: 本次采样的视口坐标点。
    ///   - viewportSize: 采样时的视口尺寸。
    @MainActor
    func submit(
        points: [CGPoint],
        viewportSize: CGSize
    ) {
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
