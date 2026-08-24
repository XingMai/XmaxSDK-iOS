/// 定义 SDK 所需平台权限的检查与申请能力。
protocol PermissionProviding: Sendable {

    /// 确保已获得相机访问权限。
    func ensureCameraPermission() async throws

    /// 确保已获得麦克风访问权限。
    func ensureMicrophonePermission() async throws
}
