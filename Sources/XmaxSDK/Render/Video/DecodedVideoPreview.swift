//
//  DecodedVideoPreview.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 将解码帧投递到当前绑定的 SDK 视频视图。
@MainActor
final class DecodedVideoPreviewPresenter {

    // 预览资源
    private weak var view: XmaxVideoView?
    private var contentMode = VideoContentMode.fill
    private var mirrored = false

    /// 绑定视频视图并应用预览缩放及镜像设置。
    ///
    /// - Parameters:
    ///   - view: 接收解码帧的 SDK 视频视图。
    ///   - contentMode: 画面的缩放与裁剪方式。
    func attach(
        to view: XmaxVideoView,
        contentMode: VideoContentMode
    ) {
        self.view = view
        self.contentMode = contentMode
        view.prepareDecodedVideoPreview(contentMode: contentMode)
        view.setDecodedVideoPreviewMirrored(mirrored)
    }

    /// 清除指定视图的解码预览并解除当前绑定。
    ///
    /// - Parameter view: 需要解除预览的视图。
    func detach(from view: XmaxVideoView) {
        view.clearDecodedVideoPreview()
        if self.view === view {
            self.view = nil
        }
    }

    /// 向当前绑定视图提交解码帧。
    ///
    /// - Parameter frame: 待显示的中性视频帧。
    func display(_ frame: VideoFrame) {
        view?.displayDecodedVideoFrame(frame, contentMode: contentMode)
    }

    /// 更新预览镜像并应用到当前视图。
    ///
    /// - Parameter mirrored: 是否水平镜像画面。
    func setMirrored(_ mirrored: Bool) {
        self.mirrored = mirrored
        view?.setDecodedVideoPreviewMirrored(mirrored)
    }

    /// 清除预览内容并释放视图绑定。
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

    /// 创建向主线程合并投递预览帧的分发器。
    ///
    /// - Parameter presenter: 负责将帧呈现到视频视图的组件。
    init(presenter: DecodedVideoPreviewPresenter) {
        self.presenter = presenter
    }

    /// 更新待显示帧，并在需要时安排主线程投递。
    ///
    /// - Parameter frame: 最新可显示的视频帧。
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

    /// 丢弃尚未提交的预览帧。
    func reset() {
        lock.withLock {
            pendingFrame = nil
        }
    }

    /// 安排一次主线程预览帧投递。
    private func scheduleDelivery() {
        Task { @MainActor [weak self] in
            self?.deliverLatestFrame()
        }
    }

    /// 显示最新待投递帧，并按需继续调度后续帧。
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
