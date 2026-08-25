import Foundation
@testable import XmaxSDK

final class PermissionProvidingStub: PermissionProviding, @unchecked Sendable {

    // 测试配置
    private let cameraError: (any Error)?

    // 并发状态
    private let lock = NSLock()
    private var storedCameraRequestCount = 0

    init(cameraError: (any Error)? = nil) {
        self.cameraError = cameraError
    }

    var cameraRequestCount: Int {
        lock.withLock { storedCameraRequestCount }
    }

    func ensureCameraPermission() async throws {
        try lock.withLock {
            storedCameraRequestCount += 1
            if let cameraError {
                throw cameraError
            }
        }
    }

    func ensureMicrophonePermission() async throws {}
}
