import Foundation
@preconcurrency import VolcEngineRTC
import XCTest
@testable import XmaxSDK

final class RtcManagerTests: XCTestCase {
    func testInitializeIsIdempotentAndDestroyReleasesEngine() async throws {
        let lifecycle = RtcManagerEngineLifecycleRecorder()
        let engineManager = RtcEngineManager(
            appID: "test-app-id",
            makeEngine: lifecycle.create,
            destroyEngine: lifecycle.destroy
        )
        let manager = RtcManager(engineManager: engineManager)

        try await manager.initialize()
        try await manager.initialize()

        XCTAssertEqual(lifecycle.creationCount, 1)
        XCTAssertEqual(lifecycle.destroyCount, 0)

        await manager.destroy()

        XCTAssertEqual(lifecycle.destroyCount, 1)
    }

    func testCancellingOneInitializationKeepsOtherWaitersValid() async throws {
        let lifecycle = RtcManagerEngineLifecycleRecorder()
        let engineManager = RtcEngineManager(
            appID: "test-app-id",
            makeEngine: lifecycle.create,
            destroyEngine: lifecycle.destroy
        )
        let occupiedLease = try await engineManager.acquire()
        let manager = RtcManager(engineManager: engineManager)
        let first = Task { try await manager.initialize() }
        let second = Task { try await manager.initialize() }
        for _ in 0..<100 {
            await Task.yield()
        }
        first.cancel()
        await engineManager.release(occupiedLease)

        do {
            try await first.value
            XCTFail("Expected cancelled initialization to fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
        }
        try await second.value
        XCTAssertEqual(lifecycle.creationCount, 2)
        XCTAssertEqual(lifecycle.destroyCount, 1)

        try await manager.initialize()
        XCTAssertEqual(lifecycle.creationCount, 2)
        await manager.destroy()
        XCTAssertEqual(lifecycle.destroyCount, 2)
    }

    func testCancellationDuringEngineCreationReturnsLease() async throws {
        let lifecycle = RtcManagerEngineLifecycleRecorder()
        let creationStarted = expectation(description: "Engine creation started")
        let creationGate = DispatchSemaphore(value: 0)
        let engineManager = RtcEngineManager(
            appID: "test-app-id",
            makeEngine: { appID in
                let engine = lifecycle.create(appID: appID)
                if lifecycle.creationCount == 1 {
                    creationStarted.fulfill()
                    _ = creationGate.wait(timeout: .now() + 3)
                }
                return engine
            },
            destroyEngine: lifecycle.destroy
        )
        let manager = RtcManager(engineManager: engineManager)
        let initialization = Task { try await manager.initialize() }
        await fulfillment(of: [creationStarted], timeout: 2)
        initialization.cancel()
        creationGate.signal()

        do {
            try await initialization.value
            XCTFail("Expected cancelled initialization to fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
        }
        XCTAssertEqual(lifecycle.destroyCount, 1)

        try await manager.initialize()
        XCTAssertEqual(lifecycle.creationCount, 2)
        await manager.destroy()
        XCTAssertEqual(lifecycle.destroyCount, 2)
    }

    func testMediaOperationRequiresInitializedEngine() {
        let manager = RtcManager(
            engineManager: RtcEngineManager(
                appID: "test-app-id",
                makeEngine: { _ in ByteRTCEngine() },
                destroyEngine: {}
            )
        )

        XCTAssertThrowsError(
            try manager.configureVideoEncoding(
                VideoEncodingConfiguration(
                    width: 720,
                    height: 1280,
                    frameRate: 24
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .rtcError,
                    message: "RTC engine is not initialized"
                )
            )
        }
    }

    func testVideoCaptureRejectsInvalidFormatBeforeEngineAccess() {
        let manager = RtcManager()

        XCTAssertThrowsError(
            try manager.startVideoCapture(
                width: 0,
                height: 1280,
                frameRate: 24
            )
        ) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Video width, height, and frame rate must be positive"
                )
            )
        }
    }

    func testJoinAllowsEmptyTokenButRequiresRoomAndUserIDs() async {
        let manager = RtcManager()

        do {
            try await manager.joinRoom(
                configuration: RoomJoinConfiguration(
                    roomID: "",
                    userID: "user",
                    token: ""
                )
            )
            XCTFail("Expected an empty room ID to fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
        }

        do {
            try await manager.joinRoom(
                configuration: RoomJoinConfiguration(
                    roomID: "room",
                    userID: "",
                    token: ""
                )
            )
            XCTFail("Expected an empty user ID to fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
        }

        do {
            try await manager.joinRoom(
                configuration: RoomJoinConfiguration(
                    roomID: "room",
                    userID: "user",
                    token: ""
                )
            )
            XCTFail("Expected an uninitialized engine to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .rtcError,
                    message: "RTC engine is not initialized"
                )
            )
        }
    }

}

private final class RtcManagerEngineLifecycleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var creations = 0
    private var destructions = 0

    var creationCount: Int {
        lock.withLock { creations }
    }

    var destroyCount: Int {
        lock.withLock { destructions }
    }

    func create(appID: String) -> ByteRTCEngine? {
        lock.withLock {
            creations += 1
        }
        return ByteRTCEngine()
    }

    func destroy() {
        lock.withLock {
            destructions += 1
        }
    }
}
