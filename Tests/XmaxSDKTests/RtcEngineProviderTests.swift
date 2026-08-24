import Foundation
@preconcurrency import VolcEngineRTC
import XCTest
@testable import XmaxSDK

final class RtcEngineProviderTests: XCTestCase {
    func testAcquireCreatesAndReleaseDestroysEngine() async throws {
        let lifecycle = RtcEngineLifecycleRecorder()
        let provider = makeProvider(lifecycle: lifecycle)

        let lease = try await provider.acquire()

        XCTAssertEqual(lifecycle.createdAppIDs, ["test-app-id"])
        XCTAssertEqual(lifecycle.destroyCount, 0)

        await provider.release(lease)

        XCTAssertEqual(lifecycle.destroyCount, 1)
    }

    func testSecondAcquireWaitsUntilFirstLeaseIsReleased() async throws {
        let lifecycle = RtcEngineLifecycleRecorder()
        let provider = makeProvider(lifecycle: lifecycle)
        let firstLease = try await provider.acquire()
        let secondTask = Task {
            try await provider.acquire()
        }

        await Task.yield()
        XCTAssertEqual(lifecycle.createdAppIDs.count, 1)

        await provider.release(firstLease)
        let secondLease = try await secondTask.value

        XCTAssertEqual(lifecycle.createdAppIDs.count, 2)
        XCTAssertEqual(lifecycle.destroyCount, 1)

        await provider.release(secondLease)
        XCTAssertEqual(lifecycle.destroyCount, 2)
    }

    func testCancelledWaiterDoesNotAcquireEngine() async throws {
        let lifecycle = RtcEngineLifecycleRecorder()
        let provider = makeProvider(lifecycle: lifecycle)
        let firstLease = try await provider.acquire()
        let waitingTask = Task {
            try await provider.acquire()
        }

        await Task.yield()
        waitingTask.cancel()

        do {
            _ = try await waitingTask.value
            XCTFail("Expected the waiting acquisition to be cancelled")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await provider.release(firstLease)

        XCTAssertEqual(lifecycle.createdAppIDs.count, 1)
        XCTAssertEqual(lifecycle.destroyCount, 1)
    }

    func testReleaseIgnoresLeaseOwnedByAnotherProvider() async throws {
        let firstLifecycle = RtcEngineLifecycleRecorder()
        let secondLifecycle = RtcEngineLifecycleRecorder()
        let firstProvider = makeProvider(lifecycle: firstLifecycle)
        let secondProvider = makeProvider(lifecycle: secondLifecycle)
        let firstLease = try await firstProvider.acquire()
        let secondLease = try await secondProvider.acquire()

        await firstProvider.release(secondLease)
        XCTAssertEqual(firstLifecycle.destroyCount, 0)

        await firstProvider.release(firstLease)
        await secondProvider.release(secondLease)
        XCTAssertEqual(firstLifecycle.destroyCount, 1)
        XCTAssertEqual(secondLifecycle.destroyCount, 1)
    }

    func testAcquireRejectsEmptyAppID() async {
        let lifecycle = RtcEngineLifecycleRecorder()
        let provider = RtcEngineProvider(
            appID: " \n ",
            makeEngine: lifecycle.create,
            destroyEngine: lifecycle.destroy
        )

        do {
            _ = try await provider.acquire()
            XCTFail("Expected RTC App ID validation to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .rtcError,
                    message: "RTC App ID cannot be empty"
                )
            )
        }

        XCTAssertTrue(lifecycle.createdAppIDs.isEmpty)
        XCTAssertEqual(lifecycle.destroyCount, 0)
    }

    func testAcquireMapsEngineCreationFailure() async {
        let lifecycle = RtcEngineLifecycleRecorder(shouldFailCreation: true)
        let provider = makeProvider(lifecycle: lifecycle)

        do {
            _ = try await provider.acquire()
            XCTFail("Expected RTC Engine creation to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .rtcError,
                    message: "Failed to create RTC Engine"
                )
            )
        }

        XCTAssertEqual(lifecycle.createdAppIDs, ["test-app-id"])
        XCTAssertEqual(lifecycle.destroyCount, 0)
    }

    private func makeProvider(
        lifecycle: RtcEngineLifecycleRecorder
    ) -> RtcEngineProvider {
        RtcEngineProvider(
            appID: " test-app-id ",
            makeEngine: lifecycle.create,
            destroyEngine: lifecycle.destroy
        )
    }
}

private final class RtcEngineLifecycleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let shouldFailCreation: Bool
    private var appIDs: [String] = []
    private var destructions = 0

    init(shouldFailCreation: Bool = false) {
        self.shouldFailCreation = shouldFailCreation
    }

    var createdAppIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return appIDs
    }

    var destroyCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return destructions
    }

    func create(appID: String) -> ByteRTCEngine? {
        lock.lock()
        appIDs.append(appID)
        lock.unlock()

        return shouldFailCreation ? nil : ByteRTCEngine()
    }

    func destroy() {
        lock.lock()
        destructions += 1
        lock.unlock()
    }
}
