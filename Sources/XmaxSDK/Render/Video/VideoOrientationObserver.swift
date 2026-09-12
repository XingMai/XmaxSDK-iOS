import UIKit

/// 通过标准子控制器生命周期，在窗口旋转开始时通知视频视图。
@MainActor
final class VideoOrientationObserver: UIViewController {

    // 视频视图
    private weak var videoView: XmaxVideoView?
    private let deviceOrientation: () -> UIDeviceOrientation

    // 旋转状态
    private(set) var isTransitioning = false
    private var generatesOrientationNotifications = false

    init(
        videoView: XmaxVideoView,
        deviceOrientation: @escaping () -> UIDeviceOrientation = { UIDevice.current.orientation }
    ) {
        self.videoView = videoView
        self.deviceOrientation = deviceOrientation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        deviceOrientation = { UIDevice.current.orientation }
        super.init(coder: coder)
    }

    deinit {
        if generatesOrientationNotifications {
            Task { @MainActor in UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        }
    }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil, !generatesOrientationNotifications {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            generatesOrientationNotifications = true
        } else if parent == nil, generatesOrientationNotifications {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            generatesOrientationNotifications = false
        }
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        guard !coordinator.targetTransform.isIdentity else { return }

        isTransitioning = true
        let device = deviceOrientation()
        let target = Self.interfaceOrientation(for: device)
        XmaxLogger.media.debug(
            message: """
            旋转时序 [TEMP] (Rotation Timing)
            ├─ \(XmaxLogger.localized("阶段：", "Stage: "))rotation_begin
            ├─ \(XmaxLogger.localized("时间：", "Time: "))\(DispatchTime.now().uptimeNanoseconds / 1000000) ms
            └─ \(XmaxLogger.localized("方向：", "Orientation: "))device=\(device.rawValue), target=\(target?.rawValue ?? 0)
            """
        )
        if let target,
           target.isLandscape == (size.width > size.height) {
            videoView?.updateInterfaceOrientation(target)
        }

        let registered = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            isTransitioning = false
            videoView?.updateWindowOrientation()
            XmaxLogger.media.debug(
                message: """
                旋转时序 [TEMP] (Rotation Timing)
                ├─ \(XmaxLogger.localized("阶段：", "Stage: "))rotation_end
                └─ \(XmaxLogger.localized("时间：", "Time: "))\(DispatchTime.now().uptimeNanoseconds / 1000000) ms
                """
            )
        }
        if !registered { isTransitioning = false }
    }

    /// 设备方向与界面方向的左右横屏名称相反；平放和未知方向不参与推断。
    static func interfaceOrientation(for orientation: UIDeviceOrientation) -> UIInterfaceOrientation? {
        switch orientation {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeRight
        case .landscapeRight: .landscapeLeft
        default: nil
        }
    }
}
