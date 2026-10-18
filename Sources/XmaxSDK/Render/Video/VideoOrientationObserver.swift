//
//  VideoOrientationObserver.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit

/// 通过标准子控制器生命周期，在窗口旋转开始时通知视频视图。
@MainActor
final class VideoOrientationObserver: UIViewController {

    /// 视频视图
    private weak var videoView: XmaxVideoView?
    private let deviceOrientation: () -> UIDeviceOrientation

    /// 旋转状态
    private(set) var isTransitioning = false
    private var generatesOrientationNotifications = false

    /// 创建监听窗口旋转的子控制器。
    ///
    /// - Parameters:
    ///   - videoView: 需要提前更新显示方向的视频视图。
    ///   - deviceOrientation: 读取当前设备物理方向的操作。
    init(
        videoView: XmaxVideoView,
        deviceOrientation: @escaping () -> UIDeviceOrientation = { UIDevice.current.orientation }
    ) {
        self.videoView = videoView
        self.deviceOrientation = deviceOrientation
        super.init(nibName: nil, bundle: nil)
    }

    /// 从归档创建窗口方向观察器。
    ///
    /// - Parameter coder: 视图控制器归档解码器。
    required init?(coder: NSCoder) {
        deviceOrientation = { UIDevice.current.orientation }
        super.init(coder: coder)
    }

    /// 结束由当前观察器启动的设备方向通知。
    deinit {
        if generatesOrientationNotifications {
            Task { @MainActor in UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        }
    }

    /// 创建不接收交互且不参与无障碍访问的透明观察视图。
    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }

    /// 随父控制器绑定状态启动或停止设备方向通知。
    ///
    /// - Parameter parent: 新的父视图控制器；移除时为 `nil`。
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

    /// 在旋转开始时通知目标方向，结束后同步实际窗口方向。
    ///
    /// - Parameters:
    ///   - size: 旋转完成后的容器尺寸。
    ///   - coordinator: 管理系统旋转动画与完成回调的协调器。
    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        guard !coordinator.targetTransform.isIdentity else { return }

        isTransitioning = true
        let target = Self.interfaceOrientation(for: deviceOrientation())
        if let target,
           target.isLandscape == (size.width > size.height) {
            videoView?.updateInterfaceOrientation(target)
        }

        let registered = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            isTransitioning = false
            videoView?.updateWindowOrientation()
        }
        if !registered { isTransitioning = false }
    }

    /// 将设备物理方向转换为对应的界面方向。
    ///
    /// - Parameter orientation: 当前设备方向。
    /// - Returns: 对应界面方向；平放或未知方向返回 `nil`。
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
