//
//  XmaxVideo.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import SwiftUI

/// 在 SwiftUI 中显示本地或远端实时视频轨道。
@MainActor
public struct XmaxVideo: UIViewRepresentable {

    /// 当前显示的视频轨道。
    public let track: RealtimeVideoTrack?

    /// 视频内容在容器中的显示模式。
    public let videoContentMode: VideoContentMode

    /// 是否允许在远端视频上绘制并发送轨迹交互。
    public let isInteractionEnabled: Bool

    /// 创建 SwiftUI 视频渲染组件。
    ///
    /// - Parameters:
    ///   - track: 需要显示的视频轨道；传入空值时显示空白容器。
    ///   - videoContentMode: 视频内容显示模式。
    ///   - isInteractionEnabled: 是否允许在远端视频上进行轨迹交互。
    public init(
        track: RealtimeVideoTrack?,
        videoContentMode: VideoContentMode = .fill,
        isInteractionEnabled: Bool = true
    ) {
        self.track = track
        self.videoContentMode = videoContentMode
        self.isInteractionEnabled = isInteractionEnabled
    }

    /// 创建承载 SwiftUI 视频内容的 UIKit 视图。
    ///
    /// - Parameter context: SwiftUI 提供的视图创建上下文。
    /// - Returns: 配置当前轨道的 SDK 视频视图。
    public func makeUIView(context: Context) -> XmaxVideoView {
        let view = XmaxVideoView(
            track: track,
            videoContentMode: videoContentMode,
            isInteractionEnabled: isInteractionEnabled
        )
        return view
    }

    /// 将最新轨道和显示配置同步到 UIKit 视图。
    ///
    /// - Parameters:
    ///   - view: 需要更新的 SDK 视频视图。
    ///   - context: SwiftUI 提供的视图更新上下文。
    public func updateUIView(
        _ view: XmaxVideoView,
        context: Context
    ) {
        view.videoContentMode = videoContentMode
        view.isInteractionEnabled = isInteractionEnabled
        view.track = track
    }

    /// 在 SwiftUI 移除视图时解除视频轨道绑定。
    ///
    /// - Parameters:
    ///   - view: 即将移除的 SDK 视频视图。
    ///   - coordinator: 无额外状态的 SwiftUI 协调对象。
    public static func dismantleUIView(
        _ view: XmaxVideoView,
        coordinator: Void
    ) {
        view.track = nil
    }
}
