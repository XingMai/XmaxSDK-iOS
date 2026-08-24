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

/// 隔离系统权限 API，便于 Provider 保持中性且可测试。
struct PermissionAuthorizationClient: Sendable {

    let authorizationStatus: @Sendable (
        _ permission: MediaPermission
    ) -> MediaAuthorizationStatus
    let requestAccess: @Sendable (
        _ permission: MediaPermission
    ) async throws -> Bool

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

    var mediaType: AVMediaType {
        switch self {
        case .camera:
            return .video
        case .microphone:
            return .audio
        }
    }
}
