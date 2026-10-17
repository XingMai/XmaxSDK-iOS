//
//  XmaxRealtimeVideo.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import SwiftUI

/// 在 SwiftUI 中自动切换本地预览和远端生成画面。
@MainActor
public struct XmaxRealtimeVideo: UIViewRepresentable {

    // 公共配置
    /// 当前显示的本地视频轨道。
    public let localTrack: RealtimeVideoTrack?

    /// 当前显示的远端生成视频轨道。
    public let remoteTrack: RealtimeVideoTrack?

    /// 视频内容在容器中的显示模式。
    public let videoContentMode: VideoContentMode

    /// 是否允许在远端视频上绘制并发送轨迹交互。
    public let isInteractionEnabled: Bool

    /// 创建 SwiftUI 实时视频组件。
    ///
    /// - Parameters:
    ///   - localTrack: 需要持续预览的本地视频轨道。
    ///   - remoteTrack: 需要覆盖显示的远端生成视频轨道。
    ///   - videoContentMode: 本地与远端视频的内容显示模式。
    ///   - isInteractionEnabled: 是否允许在远端视频上进行轨迹交互。
    public init(
        localTrack: RealtimeVideoTrack?,
        remoteTrack: RealtimeVideoTrack?,
        videoContentMode: VideoContentMode = .fill,
        isInteractionEnabled: Bool = true
    ) {
        self.localTrack = localTrack
        self.remoteTrack = remoteTrack
        self.videoContentMode = videoContentMode
        self.isInteractionEnabled = isInteractionEnabled
    }

    /// 创建承载 SwiftUI 视频内容的 UIKit 视图。
    ///
    /// - Parameter context: SwiftUI 提供的视图创建上下文。
    /// - Returns: 配置本地与远端轨道的 SDK 实时视频视图。
    public func makeUIView(context: Context) -> XmaxRealtimeVideoView {
        XmaxRealtimeVideoView(
            localTrack: localTrack,
            remoteTrack: remoteTrack,
            videoContentMode: videoContentMode,
            isInteractionEnabled: isInteractionEnabled
        )
    }

    /// 将最新轨道和显示配置同步到 UIKit 视图。
    ///
    /// - Parameters:
    ///   - view: 需要更新的 SDK 视频视图。
    ///   - context: SwiftUI 提供的视图更新上下文。
    public func updateUIView(
        _ view: XmaxRealtimeVideoView,
        context: Context
    ) {
        view.videoContentMode = videoContentMode
        view.isInteractionEnabled = isInteractionEnabled
        view.localTrack = localTrack
        view.remoteTrack = remoteTrack
    }

    /// 在 SwiftUI 移除视图时解除视频轨道绑定。
    ///
    /// - Parameters:
    ///   - view: 即将移除的 SDK 视频视图。
    ///   - coordinator: 无额外状态的 SwiftUI 协调对象。
    public static func dismantleUIView(
        _ view: XmaxRealtimeVideoView,
        coordinator: Void
    ) {
        view.localTrack = nil
        view.remoteTrack = nil
    }
}
