//
//  PermissionAuthorizationClient.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AVFoundation

/// SDK 需要检查的媒体权限。
enum MediaPermission: Equatable, Sendable {

    /// 摄像头采集权限。
    case camera

    /// 麦克风采集权限。
    case microphone
}

/// 平台媒体权限的中性授权状态。
enum MediaAuthorizationStatus: Sendable {

    /// 用户尚未作出授权选择。
    case notDetermined

    /// 系统限制访问，无法通过权限弹窗获取授权。
    case restricted

    /// 用户已拒绝访问。
    case denied

    /// 用户已允许访问。
    case authorized
}

/// 提供平台媒体权限查询与异步授权接口。
struct PermissionAuthorizationClient: Sendable {

    /// 查询指定媒体权限的当前授权状态。
    let authorizationStatus: @Sendable (
        _ permission: MediaPermission
    ) -> MediaAuthorizationStatus

    /// 请求指定媒体权限，并返回是否获得授权。
    let requestAccess: @Sendable (
        _ permission: MediaPermission
    ) async throws -> Bool

    /// 使用 AVFoundation 查询和申请媒体权限。
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

    /// 权限对应的 AVFoundation 媒体类型。
    var mediaType: AVMediaType {
        switch self {
        case .camera:
            return .video
        case .microphone:
            return .audio
        }
    }
}
