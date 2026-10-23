//
//  PermissionManager.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Checks and requests camera and microphone permissions.
final class PermissionManager: PermissionManaging, Sendable {

    /// The platform authorization client.
    private let authorizationClient: PermissionAuthorizationClient

    /// Creates a media permission manager.
    init(
        authorizationClient: PermissionAuthorizationClient = .live
    ) {
        self.authorizationClient = authorizationClient
    }

    /// Requests camera access if necessary and verifies authorization.
    ///
    /// - Throws: A camera permission error if access is denied, restricted, or not granted.
    func ensureCameraPermission() async throws {
        try await ensurePermission(
            .camera,
            errorCode: .cameraPermissionDenied,
            errorMessage: "Camera permission is unavailable or was denied"
        )
    }

    /// Requests microphone access if necessary and verifies authorization.
    ///
    /// - Throws: A microphone permission error if access is denied, restricted, or not granted.
    func ensureMicrophonePermission() async throws {
        try await ensurePermission(
            .microphone,
            errorCode: .microphonePermissionDenied,
            errorMessage: "Microphone permission is unavailable or was denied"
        )
    }

    /// Checks authorization and requests access when necessary.
    ///
    /// - Parameters:
    ///   - permission: The media permission to request.
    ///   - errorCode: The error code for missing authorization.
    ///   - errorMessage: The error message for missing authorization.
    ///
    /// - Throws: The specified permission error if access is restricted, denied, or not granted.
    private func ensurePermission(
        _ permission: MediaPermission,
        errorCode: XmaxErrorCode,
        errorMessage: String
    ) async throws {
        switch authorizationClient.authorizationStatus(permission) {
        case .authorized:
            return
        case .notDetermined:
            do {
                if try await authorizationClient.requestAccess(permission) {
                    return
                }
            } catch {
                XmaxLogger.permission.error(
                    message:
                        "权限申请失败 (Permission Request Failed)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)"
                )
            }
        case .restricted, .denied:
            break
        }

        throw XmaxError(
            code: errorCode,
            message: errorMessage
        )
    }
}
