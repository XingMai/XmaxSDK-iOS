//
//  PermissionManager.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 检查并申请 SDK 使用相机和麦克风所需的平台权限。
final class PermissionManager: PermissionManaging, Sendable {

    // 依赖
    private let authorizationClient: PermissionAuthorizationClient

    /// 创建媒体权限管理器。
    ///
    /// - Parameter authorizationClient: 查询授权状态和发起授权请求的平台接口。
    init(authorizationClient: PermissionAuthorizationClient = .live) {
        self.authorizationClient = authorizationClient
    }

    /// 确认相机权限可用；尚未询问时发起系统授权请求。
    ///
    /// - Throws: 相机权限被拒绝、受限或申请失败时抛出相机权限错误。
    func ensureCameraPermission() async throws {
        try await ensurePermission(
            .camera,
            errorCode: .cameraPermissionDenied,
            errorMessage: "Camera permission is unavailable or was denied"
        )
    }

    /// 确认麦克风权限可用；尚未询问时发起系统授权请求。
    ///
    /// - Throws: 麦克风权限被拒绝、受限或申请失败时抛出麦克风权限错误。
    func ensureMicrophonePermission() async throws {
        try await ensurePermission(
            .microphone,
            errorCode: .microphonePermissionDenied,
            errorMessage: "Microphone permission is unavailable or was denied"
        )
    }

    /// 检查权限并在需要时申请授权，未获授权则返回对应错误。
    ///
    /// - Parameters:
    ///   - permission: 需要访问的媒体权限。
    ///   - errorCode: 未授权时使用的 SDK 错误码。
    ///   - errorMessage: 未授权时提供给调用方的错误说明。
    /// - Throws: 权限受限、被拒绝或授权请求失败时抛出指定权限错误。
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
                    message: "权限申请失败 (Permission Request Failed)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)"
                )
            }
        case .restricted, .denied:
            break
        }

        throw XmaxError(code: errorCode, message: errorMessage)
    }
}
