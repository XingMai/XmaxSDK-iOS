import Foundation
@testable import XmaxSDK

final class PermissionProvidingStub: PermissionProviding, @unchecked Sendable {

    // 测试配置
    private let cameraError: (any Error)?
    private let microphoneError: (any Error)?

    // 并发状态
    private let lock = NSLock()
    private var storedCameraRequestCount = 0
    private var storedMicrophoneRequestCount = 0

    init(
        cameraError: (any Error)? = nil,
        microphoneError: (any Error)? = nil
    ) {
        self.cameraError = cameraError
        self.microphoneError = microphoneError
    }

    var cameraRequestCount: Int {
        lock.withLock { storedCameraRequestCount }
    }

    var microphoneRequestCount: Int {
        lock.withLock { storedMicrophoneRequestCount }
    }

    func ensureCameraPermission() async throws {
        try lock.withLock {
            storedCameraRequestCount += 1
            if let cameraError {
                throw cameraError
            }
        }
    }

    func ensureMicrophonePermission() async throws {
        try lock.withLock {
            storedMicrophoneRequestCount += 1
            if let microphoneError {
                throw microphoneError
            }
        }
    }
}
