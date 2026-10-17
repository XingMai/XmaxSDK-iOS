import Foundation
import XCTest

@testable import XmaxSDK

final class RtcRoomLifecycleTests: XCTestCase {
    func testJoinCancellationDestroysPendingRoomAndAllowsNextJoin() async throws {
        let started = expectation(description: "First join started")
        let first = RtcRoomStub(onJoin: { started.fulfill() })
        let nextStarted = expectation(description: "Next join started")
        let second = RtcRoomStub(onJoin: { nextStarted.fulfill() })
        let manager = makeManager { $0 == "first" ? first : second }
        try await manager.initialize()

        let joining = Task { try await manager.joinRoom(configuration: config("first")) }
        await fulfillment(of: [started], timeout: 2)
        joining.cancel()
        await expectFailure(joining, code: .cancelled)
        XCTAssertEqual(first.destroyCount, 1)

        let next = Task { try await manager.joinRoom(configuration: config("second")) }
        await fulfillment(of: [nextStarted], timeout: 2)
        first.emit(.joined, late: true)
        first.emit(.failure(XmaxError(code: .rtcError, message: "late")), late: true)
        second.emit(.joined)
        try await next.value
        try manager.publishLocalVideo()
        XCTAssertEqual(second.publishedVideo, [true])
        XCTAssertTrue(first.publishedVideo.isEmpty)
        await manager.destroy()
    }

    func testLeaveDuringJoinCancelsWaiterAndIgnoresLateSuccess() async throws {
        let started = expectation(description: "Join started")
        let room = RtcRoomStub(onJoin: { started.fulfill() })
        let manager = makeManager { _ in room }
        try await manager.initialize()

        let joining = Task { try await manager.joinRoom(configuration: config("room")) }
        await fulfillment(of: [started], timeout: 2)
        await manager.leaveRoom()
        await expectFailure(joining, code: .cancelled)
        room.emit(.joined, late: true)
        XCTAssertThrowsError(try manager.publishLocalVideo())
        await manager.leaveRoom()
        XCTAssertEqual(room.destroyCount, 1)
        await manager.destroy()
    }

    func testJoinTimeoutDestroysOnlyPendingRoom() async throws {
        let room = RtcRoomStub()
        let manager = makeManager(timeout: 10000000) { _ in room }
        try await manager.initialize()

        let joining = Task { try await manager.joinRoom(configuration: config("room")) }
        await expectFailure(joining, code: .timeout)
        XCTAssertEqual(room.destroyCount, 1)
        room.emit(.joined, late: true)
        XCTAssertThrowsError(try manager.sendRoomMessage("{}"))
        await manager.destroy()
    }

    func testImmediateJoinFailureCleansRoomAndReturnsOriginalError() async throws {
        let expected = XmaxError(code: .rtcError, message: "join rejected")
        let room = RtcRoomStub(onJoin: { throw expected })
        let manager = makeManager { _ in room }
        try await manager.initialize()

        do {
            try await manager.joinRoom(configuration: config("room"))
            XCTFail("Expected join failure")
        } catch {
            XCTAssertEqual(error as? XmaxError, expected)
        }
        XCTAssertEqual(room.destroyCount, 1)
        await manager.destroy()
    }

    func testAsynchronousJoinFailureCleansPendingRoom() async throws {
        let started = expectation(description: "Join started")
        let room = RtcRoomStub(onJoin: { started.fulfill() })
        let manager = makeManager { _ in room }
        try await manager.initialize()
        let joining = Task { try await manager.joinRoom(configuration: config("room")) }
        await fulfillment(of: [started], timeout: 2)

        room.emit(.failure(XmaxError(code: .rtcError, message: "token rejected")))
        await expectFailure(joining, code: .rtcError)
        XCTAssertEqual(room.destroyCount, 1)
        await manager.destroy()
    }

    func testDestroyDuringJoinReleasesRoomAndEngineOnce() async throws {
        let started = expectation(description: "Join started")
        let destroyed = expectation(description: "Engine destroyed")
        let room = RtcRoomStub(onJoin: { started.fulfill() })
        let platform = RtcPlatformStub(makeRoom: { _ in room })
        let manager = RtcManager(
            engineManager: RtcEngineManager(
                makeEngine: { _ in platform },
                destroyEngine: { destroyed.fulfill() }
            ))
        try await manager.initialize()
        let joining = Task { try await manager.joinRoom(configuration: config("room")) }
        await fulfillment(of: [started], timeout: 2)

        await manager.destroy()
        await expectFailure(joining, code: .cancelled)
        await fulfillment(of: [destroyed], timeout: 2)
        await manager.destroy()
        XCTAssertEqual(room.destroyCount, 1)
        XCTAssertThrowsError(try manager.useExternalVideoSource())
    }

    func testRoomReceivesAccountAndMessagesWithoutVendorConversion() async throws {
        let started = expectation(description: "Join started")
        let flushed = expectation(description: "Messages flushed")
        let room = RtcRoomStub(onJoin: { started.fulfill() }, onFlush: { flushed.fulfill() })
        let manager = makeManager { _ in room }
        try await manager.initialize()
        let configuration = config("room")
        let joining = Task { try await manager.joinRoom(configuration: configuration) }
        await fulfillment(of: [started], timeout: 2)
        room.emit(.joined)
        try await joining.value

        try manager.sendRoomMessage("{\"event\":\"start\"}")
        try await manager.awaitPendingMessages()
        await fulfillment(of: [flushed], timeout: 2)
        XCTAssertEqual(room.configurations, [configuration])
        XCTAssertEqual(room.messages, ["{\"event\":\"start\"}"])
        await manager.destroy()
    }

    func testOldRoomEventsCannotReachListenerAfterRejoin() async throws {
        let firstStarted = expectation(description: "First join")
        let secondStarted = expectation(description: "Second join")
        let first = RtcRoomStub(onJoin: { firstStarted.fulfill() })
        let second = RtcRoomStub(onJoin: { secondStarted.fulfill() })
        let manager = makeManager { $0 == "first" ? first : second }
        let listener = await MainActor.run { RoomEventRecorder() }
        manager.setEventListener(listener)
        try await manager.initialize()

        let firstJoin = Task { try await manager.joinRoom(configuration: config("first")) }
        await fulfillment(of: [firstStarted], timeout: 2)
        first.emit(.joined)
        try await firstJoin.value
        await manager.leaveRoom()

        let secondJoin = Task { try await manager.joinRoom(configuration: config("second")) }
        await fulfillment(of: [secondStarted], timeout: 2)
        second.emit(.joined)
        try await secondJoin.value
        first.emit(.publication(userID: "old", published: true), late: true)
        first.emit(.failure(XmaxError(code: .rtcError, message: "old failure")), late: true)
        let delivered = expectation(description: "Current event delivered")
        await MainActor.run { listener.onPublication = { delivered.fulfill() } }
        second.emit(.publication(userID: "current", published: true))
        await fulfillment(of: [delivered], timeout: 2)

        await MainActor.run {
            XCTAssertEqual(listener.users, ["current"])
            XCTAssertTrue(listener.failures.isEmpty)
        }
        await manager.destroy()
    }

    private func makeManager(
        timeout: UInt64 = RtcManager.joinTimeoutNanoseconds,
        makeRoom: @escaping @Sendable (String) throws -> any RtcRoom
    ) -> RtcManager {
        let platform = RtcPlatformStub(makeRoom: makeRoom)
        return RtcManager(
            engineManager: RtcEngineManager(makeEngine: { _ in platform }, destroyEngine: {}),
            joinTimeoutNanoseconds: timeout
        )
    }

    private func expectFailure(_ task: Task<Void, any Error>, code: XmaxErrorCode) async {
        do {
            try await task.value
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, code)
        }
    }
}

private func config(_ roomID: String) -> RoomJoinConfiguration {
    RoomJoinConfiguration(roomID: roomID, userID: "string-account", token: "token")
}

@MainActor
private final class RoomEventRecorder: RtcEventListener {
    var users: [String] = []
    var failures: [XmaxError] = []
    var onPublication: (() -> Void)?

    func onRemoteVideoPublished(userID: String, published: Bool) {
        users.append(userID)
        onPublication?()
    }

    func onRtcFailure(_ error: XmaxError) {
        failures.append(error)
    }
}
