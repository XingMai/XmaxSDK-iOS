import UIKit
import XmaxSDK

final class RealtimePreviewBackdropView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    // 显示配置
    private let videoContentMode: VideoContentMode
    private let trajectoryRenderer: (any TrajectoryEffectRendering)?

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    // 媒体视图
    private let videoViewportView = UIView()

    private lazy var localVideoView: XmaxVideoView = {
        let view = XmaxVideoView()
        view.videoContentMode = videoContentMode
        view.isHidden = true
        return view
    }()

    private lazy var remoteVideoView: XmaxVideoView = {
        let view = XmaxVideoView()
        view.videoContentMode = videoContentMode
        view.trajectoryRenderer = trajectoryRenderer
        view.backgroundColor = .feed(rgb: 0x101010)
        view.alpha = 0
        view.isHidden = true
        return view
    }()

    // 远端显示状态
    private var remoteVisibilityVersion: UInt64 = 0

    // 摄像头切换动画
    private lazy var cameraSwitchBlurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: nil)
        view.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }()

    private var cameraSwitchVersion: UInt64 = 0
    private var isCameraSwitchTransitionActive = false
    private var hasCompletedCameraSwitchFlip = false

    init(
        usesFileLayout: Bool,
        trajectoryRenderer: (any TrajectoryEffectRendering)? = nil
    ) {
        videoContentMode = usesFileLayout ? .fit : .fill
        self.trajectoryRenderer = trajectoryRenderer
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

        videoViewportView.clipsToBounds = true
        addSubview(videoViewportView)
        videoViewportView.addSubview(localVideoView)
        videoViewportView.addSubview(cameraSwitchBlurView)
        videoViewportView.addSubview(remoteVideoView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoViewportView.frame = bounds
        let contentFrame = videoViewportView.bounds
        localVideoView.frame = contentFrame
        cameraSwitchBlurView.frame = contentFrame
        remoteVideoView.frame = contentFrame
        localVideoView.layoutIfNeeded()
        remoteVideoView.layoutIfNeeded()
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

    func showRealtime() {
        guard remoteVideoView.track != nil else { return }
        guard remoteVideoView.isHidden || remoteVideoView.alpha < 1 else {
            return
        }
        remoteVisibilityVersion &+= 1
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

    func hideRealtime() {
        remoteVisibilityVersion &+= 1
        remoteVideoView.layer.removeAllAnimations()
        remoteVideoView.alpha = 0
        remoteVideoView.isHidden = true
    }

    func transitionToLocal(_ track: RealtimeVideoTrack?) async {
        updateLocal(track)
        remoteVisibilityVersion &+= 1
        let version = remoteVisibilityVersion
        remoteVideoView.layer.removeAllAnimations()

        guard !remoteVideoView.isHidden,
              remoteVideoView.alpha > 0 else {
            remoteVideoView.alpha = 0
            remoteVideoView.isHidden = true
            remoteVideoView.track = nil
            return
        }

        await withCheckedContinuation { continuation in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock { [weak self] in
                if let self,
                   version == self.remoteVisibilityVersion {
                    self.remoteVideoView.isHidden = true
                    self.remoteVideoView.track = nil
                }
                continuation.resume()
            }
            remoteVideoView.alpha = 0
            CATransaction.commit()
        }
    }

    func setCameraSwitchTransitionActive(_ isActive: Bool) {
        guard isCameraSwitchTransitionActive != isActive else { return }
        isCameraSwitchTransitionActive = isActive
        if isActive {
            beginCameraSwitchTransition()
        } else {
            finishCameraSwitchTransitionIfReady()
        }
    }

    private func clearRealtime() {
        hideRealtime()
        remoteVideoView.track = nil
    }
}

private extension RealtimePreviewBackdropView {
    func beginCameraSwitchTransition() {
        cameraSwitchVersion &+= 1
        let version = cameraSwitchVersion
        hasCompletedCameraSwitchFlip = false
        hideRealtime()

        localVideoView.layer.removeAllAnimations()
        cameraSwitchBlurView.layer.removeAllAnimations()
        cameraSwitchBlurView.isHidden = false
        UIView.performWithoutAnimation {
            localVideoView.layer.transform = CATransform3DIdentity
            cameraSwitchBlurView.layer.transform = CATransform3DIdentity
            cameraSwitchBlurView.alpha = 1
            cameraSwitchBlurView.effect = nil
        }

        UIView.animate(
            withDuration: 0.14,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseIn]
        ) {
            self.cameraSwitchBlurView.effect = UIBlurEffect(
                style: .systemChromeMaterialDark
            )
        } completion: { [weak self] _ in
            guard let self,
                  version == cameraSwitchVersion else {
                return
            }
            animateCameraSwitchFlip(version: version)
        }
    }

    func animateCameraSwitchFlip(version: UInt64) {
        var flipTransform = CATransform3DIdentity
        flipTransform.m34 = -1 / 600
        flipTransform = CATransform3DRotate(
            flipTransform,
            .pi,
            0,
            1,
            0
        )

        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.localVideoView.layer.transform = flipTransform
            self.cameraSwitchBlurView.layer.transform = flipTransform
        } completion: { [weak self] _ in
            guard let self,
                  version == cameraSwitchVersion else {
                return
            }
            UIView.performWithoutAnimation {
                self.localVideoView.layer.transform = CATransform3DIdentity
                self.cameraSwitchBlurView.layer.transform =
                    CATransform3DIdentity
            }
            hasCompletedCameraSwitchFlip = true
            finishCameraSwitchTransitionIfReady()
        }
    }

    func finishCameraSwitchTransitionIfReady() {
        guard !isCameraSwitchTransitionActive,
              hasCompletedCameraSwitchFlip else {
            return
        }
        let version = cameraSwitchVersion

        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            self.cameraSwitchBlurView.alpha = 0
        } completion: { [weak self] _ in
            guard let self,
                  version == cameraSwitchVersion,
                  !isCameraSwitchTransitionActive else {
                return
            }
            cameraSwitchBlurView.effect = nil
            cameraSwitchBlurView.alpha = 1
            cameraSwitchBlurView.isHidden = true
            hasCompletedCameraSwitchFlip = false
        }
    }
}
