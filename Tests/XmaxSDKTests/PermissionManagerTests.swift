import Foundation
import XCTest
@testable import XmaxSDK

final class PermissionManagerTests: XCTestCase {
    func testAuthorizedPermissionReturnsWithoutRequestingAccess() async throws {
        let recorder = PermissionRequestRecorder(result: true)
        let manager = PermissionManager(authorizationClient: .init(
            authorizationStatus: { _ in .authorized },
            requestAccess: recorder.requestAccess
        ))

        try await manager.ensureCameraPermission()

        XCTAssertEqual(recorder.permissions, [])
    }

    func testNotDeterminedPermissionRequestsAndAcceptsGrant() async throws {
        let recorder = PermissionRequestRecorder(result: true)
        let manager = PermissionManager(authorizationClient: .init(
            authorizationStatus: { _ in .notDetermined },
            requestAccess: recorder.requestAccess
        ))

        try await manager.ensureMicrophonePermission()

        XCTAssertEqual(recorder.permissions, [.microphone])
    }

    func testDeniedCameraPermissionMapsToCameraError() async {
        let manager = PermissionManager(authorizationClient: .init(
            authorizationStatus: { _ in .denied },
            requestAccess: { _ in true }
        ))

        do {
            try await manager.ensureCameraPermission()
            XCTFail("Expected camera permission to be denied")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .cameraPermissionDenied,
                    message: "Camera permission is unavailable or was denied"
                )
            )
        }
    }

    func testRestrictedMicrophonePermissionMapsToMicrophoneError() async {
        let manager = PermissionManager(authorizationClient: .init(
            authorizationStatus: { _ in .restricted },
            requestAccess: { _ in true }
        ))

        do {
            try await manager.ensureMicrophonePermission()
            XCTFail("Expected microphone permission to be denied")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .microphonePermissionDenied,
                    message: "Microphone permission is unavailable or was denied"
                )
            )
        }
    }

    func testRejectedPermissionRequestMapsToPermissionError() async {
        let recorder = PermissionRequestRecorder(result: false)
        let manager = PermissionManager(authorizationClient: .init(
            authorizationStatus: { _ in .notDetermined },
            requestAccess: recorder.requestAccess
        ))

        do {
            try await manager.ensureCameraPermission()
            XCTFail("Expected permission request to be rejected")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .cameraPermissionDenied)
            XCTAssertEqual(recorder.permissions, [.camera])
        }
    }
}

private final class PermissionRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let result: Bool
    private var requestedPermissions: [MediaPermission] = []

    init(result: Bool) {
        self.result = result
    }

    var permissions: [MediaPermission] {
        lock.lock()
        defer { lock.unlock() }
        return requestedPermissions
    }

    func requestAccess(_ permission: MediaPermission) async throws -> Bool {
        lock.withLock {
            requestedPermissions.append(permission)
        }
        return result
    }
}
