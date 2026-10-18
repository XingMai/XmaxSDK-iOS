//
//  PermissionAuthorizationClient.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AVFoundation

/// SDK 需要检查的媒体权限。
enum MediaPermission: Equatable, Sendable {
    case camera
    case microphone
}

/// 平台媒体权限的中性授权状态。
enum MediaAuthorizationStatus: Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

/// 提供平台媒体权限查询与异步授权接口。
struct PermissionAuthorizationClient: Sendable {

    /// 授权接口
    let authorizationStatus: @Sendable (
        _ permission: MediaPermission
    ) -> MediaAuthorizationStatus
    let requestAccess: @Sendable (
        _ permission: MediaPermission
    ) async throws -> Bool

    /// 平台实现
    static let live = PermissionAuthorizationClient(
        authorizationStatus: { permission in
            let status = AVCaptureDevice.authorizationStatus(
                for: permission.mediaType
            )
            switch status {
            case .notDetermined:
                return .notDetermined
            case .restricted:
                return .restricted
            case .denied:
                return .denied
            case .authorized:
                return .authorized
            @unknown default:
                return .denied
            }
        },
        requestAccess: { permission in
            await AVCaptureDevice.requestAccess(for: permission.mediaType)
        }
    )
}

private extension MediaPermission {

    /// 系统媒体类型
    var mediaType: AVMediaType {
        switch self {
        case .camera:
            return .video
        case .microphone:
            return .audio
        }
    }
}
