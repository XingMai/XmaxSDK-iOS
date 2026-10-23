//
//  PermissionManaging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// An interface for SDK media permissions.
protocol PermissionManaging: Sendable {

    /// Requests camera access if necessary and verifies authorization.
    ///
    /// - Throws: A camera permission error if access is denied, restricted, or not granted.
    func ensureCameraPermission() async throws

    /// Requests microphone access if necessary and verifies authorization.
    ///
    /// - Throws: A microphone permission error if access is denied, restricted, or not granted.
    func ensureMicrophonePermission() async throws
}
