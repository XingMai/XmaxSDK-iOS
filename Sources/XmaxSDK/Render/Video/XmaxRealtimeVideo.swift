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

    public func makeUIView(context: Context) -> XmaxRealtimeVideoView {
        XmaxRealtimeVideoView(
            localTrack: localTrack,
            remoteTrack: remoteTrack,
            videoContentMode: videoContentMode,
            isInteractionEnabled: isInteractionEnabled
        )
    }

    public func updateUIView(
        _ view: XmaxRealtimeVideoView,
        context: Context
    ) {
        view.videoContentMode = videoContentMode
        view.isInteractionEnabled = isInteractionEnabled
        view.localTrack = localTrack
        view.remoteTrack = remoteTrack
    }

    public static func dismantleUIView(
        _ view: XmaxRealtimeVideoView,
        coordinator: Void
    ) {
        view.localTrack = nil
        view.remoteTrack = nil
    }
}
