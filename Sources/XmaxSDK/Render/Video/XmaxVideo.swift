import SwiftUI

/// 在 SwiftUI 中显示本地或远端实时视频轨道。
@MainActor
public struct XmaxVideo: UIViewRepresentable {

    // 公共配置
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

    public func makeUIView(context: Context) -> XmaxVideoView {
        let view = XmaxVideoView(
            track: track,
            videoContentMode: videoContentMode,
            isInteractionEnabled: isInteractionEnabled
        )
        return view
    }

    public func updateUIView(
        _ view: XmaxVideoView,
        context: Context
    ) {
        view.videoContentMode = videoContentMode
        view.isInteractionEnabled = isInteractionEnabled
        view.track = track
    }

    public static func dismantleUIView(
        _ view: XmaxVideoView,
        coordinator: Void
    ) {
        view.track = nil
    }
}
