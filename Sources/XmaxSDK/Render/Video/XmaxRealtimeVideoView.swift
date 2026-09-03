import UIKit

/// 在本地预览和远端生成画面之间自动切换的 UIKit 视频容器。
@MainActor
public final class XmaxRealtimeVideoView: UIView {

    // 公共配置
    /// 当前显示的本地视频轨道。
    public var localTrack: RealtimeVideoTrack? {
        didSet {
            guard oldValue !== localTrack else { return }
            localVideoView.track = localTrack
        }
    }

    /// 当前显示的远端生成视频轨道。
    ///
    /// 设置新轨道后，容器会等待首帧实际提交显示再渐入远端画面；
    /// 设置为 `nil` 时立即恢复本地预览。
    public var remoteTrack: RealtimeVideoTrack? {
        didSet {
            guard oldValue !== remoteTrack else { return }
            updateRemoteTrack()
        }
    }

    /// 视频内容在容器中的显示模式。
    public var videoContentMode: VideoContentMode = .fill {
        didSet {
            guard oldValue != videoContentMode else { return }
            localVideoView.videoContentMode = videoContentMode
            remoteVideoView.videoContentMode = videoContentMode
        }
    }

    /// 是否允许在远端视频上绘制并发送轨迹交互。
    public var isInteractionEnabled = true {
        didSet {
            guard oldValue != isInteractionEnabled else { return }
            remoteVideoView.isInteractionEnabled = isInteractionEnabled
        }
    }

    /// 自定义远端轨迹视觉效果；设置为 `nil` 时恢复 SDK 内置效果。
    public var trajectoryRenderer: (any TrajectoryEffectRendering)? {
        get { remoteVideoView.trajectoryRenderer }
        set { remoteVideoView.trajectoryRenderer = newValue }
    }

    // 视频视图
    private lazy var localVideoView = XmaxVideoView(
        videoContentMode: videoContentMode,
        isInteractionEnabled: false
    )
    private lazy var remoteVideoView = XmaxVideoView(
        videoContentMode: videoContentMode,
        isInteractionEnabled: isInteractionEnabled
    )

    // 远端显示状态
    private var remoteTrackVersion: UInt64 = 0

    /// 创建实时视频容器。
    ///
    /// - Parameters:
    ///   - localTrack: 需要持续预览的本地视频轨道。
    ///   - remoteTrack: 需要覆盖显示的远端生成视频轨道。
    ///   - videoContentMode: 本地与远端视频的内容显示模式。
    ///   - isInteractionEnabled: 是否允许在远端视频上进行轨迹交互。
    public init(
        localTrack: RealtimeVideoTrack? = nil,
        remoteTrack: RealtimeVideoTrack? = nil,
        videoContentMode: VideoContentMode = .fill,
        isInteractionEnabled: Bool = true
    ) {
        self.localTrack = localTrack
        self.remoteTrack = remoteTrack
        self.videoContentMode = videoContentMode
        self.isInteractionEnabled = isInteractionEnabled
        super.init(frame: .zero)
        configureView()
    }

    /// 使用指定布局区域创建实时视频容器。
    public override init(frame: CGRect) {
        localTrack = nil
        remoteTrack = nil
        super.init(frame: frame)
        configureView()
    }

    /// 从 Interface Builder 恢复实时视频容器。
    public required init?(coder: NSCoder) {
        localTrack = nil
        remoteTrack = nil
        super.init(coder: coder)
        configureView()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        localVideoView.frame = bounds
        remoteVideoView.frame = bounds
    }
}

private extension XmaxRealtimeVideoView {
    func configureView() {
        backgroundColor = .black
        clipsToBounds = true
        addSubview(localVideoView)
        addSubview(remoteVideoView)
        localVideoView.track = localTrack
        updateRemoteTrack()
    }

    func updateRemoteTrack() {
        remoteTrackVersion &+= 1
        let version = remoteTrackVersion
        remoteVideoView.frameDisplayHandler = nil
        remoteVideoView.layer.removeAllAnimations()
        remoteVideoView.alpha = 0
        remoteVideoView.isHidden = true
        remoteVideoView.track = nil

        guard let remoteTrack else { return }
        remoteVideoView.frameDisplayHandler = { [weak self, weak remoteTrack] in
            guard let self,
                  version == remoteTrackVersion,
                  self.remoteTrack === remoteTrack else {
                return
            }
            showRemoteVideo()
        }
        remoteVideoView.track = remoteTrack
    }

    func showRemoteVideo() {
        remoteVideoView.frameDisplayHandler = nil
        guard remoteVideoView.isHidden || remoteVideoView.alpha < 1 else {
            return
        }
        remoteVideoView.layer.removeAllAnimations()
        remoteVideoView.isHidden = false
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.remoteVideoView.alpha = 1
        }
    }
}
