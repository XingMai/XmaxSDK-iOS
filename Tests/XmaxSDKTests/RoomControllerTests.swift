import XCTest
@testable import XmaxSDK

final class RoomControllerTests: XCTestCase {
    func testJoinForwardsConnectionAndLeaveReleasesRoom() async throws {
        let rtcManager = RtcManagingStub()
        let controller = RoomController(rtcManager: rtcManager)

        try await controller.join(
            connection: connection,
            ensureActive: {}
        )
        await controller.leave()
        await controller.leave()

        XCTAssertEqual(
            rtcManager.calls,
            [
                .joinRoom(
                    RoomJoinConfiguration(
                        roomID: "room-id",
                        userID: "user-id",
                        token: "room-token"
                    )
                ),
                .leaveRoom
            ]
        )
    }

    func testJoinRejectsAnotherRoomUntilLeave() async throws {
        let rtcManager = RtcManagingStub()
        let controller = RoomController(rtcManager: rtcManager)
        try await controller.join(
            connection: connection,
            ensureActive: {}
        )

        do {
            try await controller.join(
                connection: connection,
                ensureActive: {}
            )
            XCTFail("Expected duplicate room join to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Leave the current RTC room before " +
                        "joining another one"
                )
            )
        }

        await controller.leave()
    }

    func testJoinFailureRollsBackRoomResources() async {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "join failed"
        )
        let rtcManager = RtcManagingStub(joinRoomError: expectedError)
        let controller = RoomController(rtcManager: rtcManager)

        do {
            try await controller.join(
                connection: connection,
                ensureActive: {}
            )
            XCTFail("Expected room join to fail")
        } catch {
            XCTAssertEqual(error as? XmaxError, expectedError)
        }

        XCTAssertEqual(
            rtcManager.calls,
            [
                .joinRoom(
                    RoomJoinConfiguration(
                        roomID: "room-id",
                        userID: "user-id",
                        token: "room-token"
                    )
                ),
                .leaveRoom
            ]
        )
    }

    func testInactiveJoinAfterAsyncBoundaryLeavesRoom() async {
        let expectedError = XmaxError(
            code: .cancelled,
            message: "connection replaced"
        )
        let counter = LockedInvocationCounter()
        let rtcManager = RtcManagingStub()
        let controller = RoomController(rtcManager: rtcManager)

        do {
            try await controller.join(
                connection: connection,
                ensureActive: {
                    if counter.increment() == 2 {
                        throw expectedError
                    }
                }
            )
            XCTFail("Expected inactive join to fail")
        } catch {
            XCTAssertEqual(error as? XmaxError, expectedError)
        }

        XCTAssertEqual(counter.value, 2)
        XCTAssertEqual(rtcManager.calls.last, .leaveRoom)
    }

    func testGenerationSignalsUseJoinedUserAndRoomProtocol() async throws {
        let rtcManager = RtcManagingStub()
        let controller = RoomController(rtcManager: rtcManager)
        try await controller.join(
            connection: connection,
            ensureActive: {}
        )
        let format = RealtimeVideoFormat(
            width: 720,
            height: 1280,
            fps: 24
        )

        try await controller.startGeneration(
            taskID: "task-id",
            videoFormat: format,
            context: RealtimeContext(prompt: "first")
        )
        try await controller.changeGenerationCondition(
            taskID: "task-id",
            videoFormat: format,
            context: RealtimeContext(prompt: "second")
        )
        try await controller.sendTracks(
            taskID: "task-id",
            points: [RealtimePoint(x: 10, y: 20)]
        )
        try await controller.stopGeneration(taskID: "task-id")

        let events = try rtcManager.controllerMessages.map(decode)
        XCTAssertEqual(
            events.compactMap { $0["event"] as? String },
            ["start", "change_condition", "tracks", "stop"]
        )
        XCTAssertTrue(
            events.allSatisfy { $0["user_id"] as? String == "user-id" }
        )
        await controller.leave()
    }

    func testGenerationSignalRequiresJoinedRoom() async {
        let rtcManager = RtcManagingStub()
        let controller = RoomController(rtcManager: rtcManager)

        do {
            try await controller.startGeneration(
                taskID: "task-id",
                videoFormat: RealtimeVideoFormat(
                    width: 720,
                    height: 1280,
                    fps: 24
                ),
                context: RealtimeContext(prompt: "prompt")
            )
            XCTFail("Expected generation signal to require a room")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .rtcError,
                    message: "RTC room is not joined"
                )
            )
        }
        XCTAssertTrue(rtcManager.controllerMessages.isEmpty)
    }

    func testEmptyOptionalSignalsAreIgnored() async throws {
        let rtcManager = RtcManagingStub()
        let controller = RoomController(rtcManager: rtcManager)
        try await controller.join(
            connection: connection,
            ensureActive: {}
        )

        try await controller.stopGeneration(taskID: "")
        try await controller.sendTracks(taskID: "task-id", points: [])

        XCTAssertTrue(rtcManager.controllerMessages.isEmpty)
        await controller.leave()
    }
}

private extension RoomControllerTests {
    var connection: RealtimeSessionConnection {
        RealtimeSessionConnection(
            roomID: "room-id",
            userID: "user-id",
            token: "room-token",
            botName: "bot-user"
        )
    }

    func decode(_ message: String) throws -> [String: Any] {
        let data = try XCTUnwrap(message.data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}

private final class LockedInvocationCounter: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    @discardableResult
    func increment() -> Int {
        lock.withLock {
            storedValue += 1
            return storedValue
        }
    }
}

private extension RtcManagingStub {
    var controllerMessages: [String] {
        calls.compactMap { call in
            guard case .sendRoomMessage(let message) = call else {
                return nil
            }
            return message
        }
    }
}
