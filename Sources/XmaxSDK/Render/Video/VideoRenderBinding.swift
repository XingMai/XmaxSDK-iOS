//
//  VideoRenderBinding.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit

/// 将实时视频轨道绑定到具体 UIKit 渲染视图。
@MainActor
final class VideoRenderBinding {

    // 渲染操作
    private let attachHandler: (UIView, VideoContentMode) throws -> Void
    private let detachHandler: (UIView) throws -> Void

    // 运行状态
    private weak var attachedView: UIView?

    /// 创建轨道与视图之间的渲染绑定。
    ///
    /// - Parameters:
    ///   - attachHandler: 将内容绑定到视图并应用显示模式的操作。
    ///   - detachHandler: 从视图解除内容的操作。
    init(
        attachHandler: @escaping (UIView, VideoContentMode) throws -> Void,
        detachHandler: @escaping (UIView) throws -> Void
    ) {
        self.attachHandler = attachHandler
        self.detachHandler = detachHandler
    }

    /// 解除旧视图后，将内容绑定到目标视图。
    ///
    /// - Parameters:
    ///   - view: 新的渲染目标视图。
    ///   - contentMode: 视频缩放与裁剪方式。
    /// - Throws: 旧视图解绑或新视图绑定失败时抛出错误。
    func attach(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        if let attachedView, attachedView !== view {
            try detachHandler(attachedView)
            self.attachedView = nil
        }

        try attachHandler(view, contentMode)
        attachedView = view
    }

    /// 仅在指定视图为当前绑定目标时解除渲染。
    ///
    /// - Parameter view: 需要解除绑定的视图。
    /// - Throws: 底层解绑操作失败时抛出错误。
    func detach(from view: UIView) throws {
        guard attachedView === view else {
            return
        }
        try detach()
    }

    /// 清除图片预览并解除当前视图的渲染绑定。
    ///
    /// - Throws: 底层解绑操作失败时抛出错误。
    func detach() throws {
        guard let attachedView else {
            return
        }
        (attachedView as? XmaxVideoView)?.clearImageFrame()
        try detachHandler(attachedView)
        self.attachedView = nil
    }
}

extension VideoRenderBinding {
    /// 创建在 SDK 视频视图中显示静态图片的绑定。
    ///
    /// - Parameter imageFrame: 用于生成图片预览的像素帧。
    convenience init(imageFrame: VideoFrame) {
        self.init(
            attachHandler: { view, contentMode in
                guard let videoView = view as? XmaxVideoView else {
                    throw XmaxError(
                        code: .invalidConfiguration,
                        message: "Image tracks require an XmaxVideoView"
                    )
                }
                try videoView.displayImageFrame(
                    imageFrame,
                    contentMode: contentMode
                )
            },
            detachHandler: { view in
                (view as? XmaxVideoView)?.clearImageFrame()
            }
        )
    }
}
