//
//  TrajectoryBinding.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit

/// 将渲染层触摸输入转交给媒体交互层。
final class TrajectoryBinding: @unchecked Sendable {

    // 交互事件
    private let interactionListener: RenderInteractionListener

    // 视图绑定
    @MainActor private weak var overlayView: TrajectoryOverlayView?

    // 坐标映射
    @MainActor private var contentMode: VideoContentMode = .fill
    @MainActor private var videoSize: CGSize?

    /// 创建连接轨迹视图与媒体交互层的绑定。
    ///
    /// - Parameters:
    ///   - interactionListener: 接收交互采样帧的异步回调。
    ///   - videoFormat: 初始视频坐标映射规格。
    init(
        interactionListener: @escaping RenderInteractionListener,
        videoFormat: RealtimeVideoFormat
    ) {
        self.interactionListener = interactionListener
        videoSize = videoFormat.size
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
        overlayView.setVideoSize(videoSize)
    }

    /// 解除指定覆盖层的轨迹绑定。
    ///
    /// - Parameter overlayView: 需要解除绑定的轨迹覆盖层。
    @MainActor
    func detach(from overlayView: TrajectoryOverlayView) {
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
    func update(contentMode: VideoContentMode) {
        self.contentMode = contentMode
        overlayView?.setContentMode(contentMode)
    }

    /// 根据视频规格更新交互映射尺寸。
    ///
    /// - Parameter videoFormat: 新的映射视频规格。
    @MainActor
    func update(videoFormat: RealtimeVideoFormat) {
        update(videoSize: videoFormat.size)
    }

    /// 更新实际显示的视频尺寸并同步到覆盖层。
    ///
    /// - Parameter videoSize: 当前画面的像素尺寸。
    @MainActor
    func update(videoSize: CGSize) {
        guard self.videoSize != videoSize else { return }
        self.videoSize = videoSize
        overlayView?.setVideoSize(videoSize)
    }

    /// 将视口中的触控点封装为交互帧并异步交付。
    ///
    /// - Parameters:
    ///   - points: 本次采样的视口坐标点。
    ///   - viewportSize: 采样时的视口尺寸。
    @MainActor
    func submit(points: [CGPoint], viewportSize: CGSize) {
        guard !points.isEmpty else { return }
        let frame = InteractionFrame(
            points: points,
            viewportSize: viewportSize,
            contentMode: contentMode,
            displayedVideoSize: videoSize
        )
        let interactionListener = interactionListener
        Task {
            await interactionListener(frame)
        }
    }
}
