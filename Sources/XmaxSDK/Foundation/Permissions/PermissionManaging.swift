//
//  PermissionManaging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 定义 SDK 所需平台权限的检查与申请能力。
protocol PermissionManaging: Sendable {

    /// 确认相机权限可用；尚未询问时发起系统授权请求。
    ///
    /// - Throws: 相机权限被拒绝、受限或申请失败时抛出相机权限错误。
    func ensureCameraPermission() async throws

    /// 确认麦克风权限可用；尚未询问时发起系统授权请求。
    ///
    /// - Throws: 麦克风权限被拒绝、受限或申请失败时抛出麦克风权限错误。
    func ensureMicrophonePermission() async throws
}
