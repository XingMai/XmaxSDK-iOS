import UIKit

/// 显示本地或远端实时视频轨道的 UIKit 容器。
@MainActor
public final class XmaxVideoView: UIView {

    // 公共配置
    /// 当前显示的视频轨道。
    public var track: RealtimeVideoTrack? {
        didSet {
            guard oldValue !== track else {
                return
            }
            detach(track: oldValue)
            attachCurrentTrackIfNeeded()
        }
    }

    /// 视频内容在容器中的显示模式。
    public var videoContentMode: VideoContentMode = .fill {
        didSet {
            guard oldValue != videoContentMode else {
                return
            }
            attachCurrentTrackIfNeeded()
        }
    }

    // 渲染状态
    private weak var attachedTrack: RealtimeVideoTrack?

    /// 创建视频渲染容器。
    ///
    /// - Parameters:
    ///   - track: 需要显示的视频轨道；可以稍后设置。
    ///   - videoContentMode: 视频内容显示模式。
    public init(
        track: RealtimeVideoTrack? = nil,
        videoContentMode: VideoContentMode = .fill
    ) {
        self.track = track
        self.videoContentMode = videoContentMode
        super.init(frame: .zero)
        configureView()
    }

    /// 使用指定布局区域创建视频渲染容器。
    public override init(frame: CGRect) {
        track = nil
        super.init(frame: frame)
        configureView()
    }

    /// 从 Interface Builder 恢复视频渲染容器。
    public required init?(coder: NSCoder) {
        track = nil
        super.init(coder: coder)
        configureView()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            detach(track: attachedTrack)
        } else {
            attachCurrentTrackIfNeeded()
        }
    }
}

private extension XmaxVideoView {
    func configureView() {
        backgroundColor = .black
        clipsToBounds = true
    }

    func attachCurrentTrackIfNeeded() {
        guard window != nil,
              let track,
              let binding = VideoRenderRegistry.binding(for: track) else {
            return
        }

        do {
            try binding.attach(
                to: self,
                contentMode: videoContentMode
            )
            attachedTrack = track
        } catch {
            attachedTrack = nil
            Self.logRenderingFailure(
                operation: "绑定视频渲染视图",
                error: error
            )
        }
    }

    func detach(track: RealtimeVideoTrack?) {
        guard let track,
              attachedTrack === track else {
            return
        }

        do {
            try VideoRenderRegistry.binding(for: track)?.detach(from: self)
        } catch {
            Self.logRenderingFailure(
                operation: "解除视频渲染视图",
                error: error
            )
        }
        attachedTrack = nil
    }

    static func logRenderingFailure(
        operation: String,
        error: any Error
    ) {
        XmaxLogger.error(
            "\(operation)失败\n└─ 原因：" +
                (error as NSError).localizedDescription,
            category: "Rendering"
        )
    }
}
