//
//  PermissionManaging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 定义 SDK 所需平台权限的检查与申请能力。
protocol PermissionManaging: Sendable {

    /// 确保已获得相机访问权限。
    func ensureCameraPermission() async throws

    /// 确保已获得麦克风访问权限。
    func ensureMicrophonePermission() async throws
}
