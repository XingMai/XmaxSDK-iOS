import Foundation
@preconcurrency import VolcEngineRTC
import XCTest
@testable import XmaxSDK

final class RtcProviderTests: XCTestCase {
    func testInitializeIsIdempotentAndDestroyReleasesEngine() async throws {
        let lifecycle = RtcProviderEngineLifecycleRecorder()
        let engineProvider = RtcEngineProvider(
            appID: "test-app-id",
            makeEngine: lifecycle.create,
            destroyEngine: lifecycle.destroy
        )
        let provider = RtcProvider(engineProvider: engineProvider)

        try await provider.initialize()
        try await provider.initialize()

        XCTAssertEqual(lifecycle.creationCount, 1)
        XCTAssertEqual(lifecycle.destroyCount, 0)

        await provider.destroy()

        XCTAssertEqual(lifecycle.destroyCount, 1)
    }

    func testMediaOperationRequiresInitializedEngine() {
        let provider = RtcProvider(
            engineProvider: RtcEngineProvider(
                appID: "test-app-id",
                makeEngine: { _ in ByteRTCEngine() },
                destroyEngine: {}
            )
        )

        XCTAssertThrowsError(
            try provider.configureVideoEncoding(
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
        let provider = RtcProvider()

        XCTAssertThrowsError(
            try provider.startVideoCapture(
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
        let provider = RtcProvider()

        do {
            try await provider.joinRoom(
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
            try await provider.joinRoom(
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
            try await provider.joinRoom(
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

    func testRenderLibraryNameMatchesIntegratedPod() {
        XCTAssertEqual(RtcProvider().renderLibraryName, "VolcEngineRTC")
    }
}

private final class RtcProviderEngineLifecycleRecorder: @unchecked Sendable {
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
