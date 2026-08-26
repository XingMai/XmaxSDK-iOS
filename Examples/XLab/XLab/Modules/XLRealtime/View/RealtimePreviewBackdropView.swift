import SnapKit
import UIKit
import XmaxSDK

final class RealtimePreviewBackdropView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    // 显示配置
    private let videoContentMode: VideoContentMode

    // 运行状态
    private var remoteVisibilityVersion: UInt64 = 0

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    // 媒体视图
    private lazy var localVideoView: XmaxVideoView = {
        let view = XmaxVideoView()
        view.videoContentMode = videoContentMode
        view.isHidden = true
        return view
    }()

    private lazy var remoteVideoView: XmaxVideoView = {
        let view = XmaxVideoView()
        view.videoContentMode = videoContentMode
        view.backgroundColor = .feed(rgb: 0x101010)
        view.alpha = 0
        view.isHidden = true
        return view
    }()

    init(usesFileLayout: Bool) {
        videoContentMode = usesFileLayout ? .fit : .fill
        super.init(frame: .zero)
        clipsToBounds = true
        gradientLayer.colors = [
            UIColor.feed(rgb: 0x171719).cgColor,
            UIColor.feed(rgb: 0x0D0D0F).cgColor,
            UIColor.feed(rgb: 0x050506).cgColor
        ]
        gradientLayer.locations = [0, 0.48, 1]
        gradientLayer.startPoint = CGPoint(x: 0.25, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.75, y: 1)

        addSubview(localVideoView)
        addSubview(remoteVideoView)

        localVideoView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        remoteVideoView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func displayLocal(_ track: RealtimeVideoTrack?) {
        updateLocal(track)
        clearRealtime()
    }

    func updateLocal(_ track: RealtimeVideoTrack?) {
        localVideoView.isHidden = false
        localVideoView.track = track
    }

    func prepareRealtime(_ track: RealtimeVideoTrack?) {
        remoteVisibilityVersion &+= 1
        remoteVideoView.layer.removeAllAnimations()
        remoteVideoView.alpha = 0
        remoteVideoView.isHidden = true
        remoteVideoView.track = track
    }

    func showRealtime(animated: Bool) {
        guard remoteVideoView.track != nil else { return }
        guard remoteVideoView.isHidden || remoteVideoView.alpha < 1 else {
            return
        }
        remoteVisibilityVersion &+= 1
        let version = remoteVisibilityVersion
        remoteVideoView.layer.removeAllAnimations()
        remoteVideoView.isHidden = false

        let changes = {
            self.remoteVideoView.alpha = 1
        }
        guard animated, window != nil else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut],
            animations: changes
        ) { _ in
            guard version == self.remoteVisibilityVersion else { return }
        }
    }

    private func clearRealtime() {
        remoteVisibilityVersion &+= 1
        remoteVideoView.layer.removeAllAnimations()
        remoteVideoView.alpha = 0
        remoteVideoView.isHidden = true
        remoteVideoView.track = nil
    }
}
