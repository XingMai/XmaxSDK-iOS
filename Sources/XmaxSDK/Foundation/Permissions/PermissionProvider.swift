import Foundation

/// 检查并申请 SDK 使用相机和麦克风所需的平台权限。
final class PermissionProvider: PermissionProviding, Sendable {

    private let authorizationClient: PermissionAuthorizationClient

    init(authorizationClient: PermissionAuthorizationClient = .live) {
        self.authorizationClient = authorizationClient
    }

    func ensureCameraPermission() async throws {
        try await ensurePermission(
            .camera,
            errorCode: .cameraPermissionDenied,
            errorMessage: "Camera permission is unavailable or was denied"
        )
    }

    func ensureMicrophonePermission() async throws {
        try await ensurePermission(
            .microphone,
            errorCode: .microphonePermissionDenied,
            errorMessage: "Microphone permission is unavailable or was denied"
        )
    }

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
                XmaxLogger.error(
                    "权限申请失败\n└─ 原因：\((error as NSError).localizedDescription)",
                    category: "Permission"
                )
            }
        case .restricted, .denied:
            break
        }

        throw XmaxError(code: errorCode, message: errorMessage)
    }
}
