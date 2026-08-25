import XCTest
@testable import XmaxSDK

final class RoomHeartbeatTests: XCTestCase {
    func testHeartbeatSendsCurrentUserAfterInterval() async throws {
        let rtcProvider = RtcProvidingStub()
        let manualSleeper = ManualRoomHeartbeatSleeper()
        let heartbeat = RoomHeartbeat(
            rtcProvider: rtcProvider,
            sleeper: manualSleeper.sleeper
        )

        heartbeat.start(userID: "user-id")
        await waitUntil { await manualSleeper.isWaiting }
        await manualSleeper.resume()
        await waitUntil { rtcProvider.heartbeatMessages.count == 1 }
        heartbeat.stop()

        let event = try decode(rtcProvider.heartbeatMessages[0])
        XCTAssertEqual(event["event"] as? String, "heartbeat")
        XCTAssertEqual(event["user_id"] as? String, "user-id")
    }

    func testStopPreventsWaitingHeartbeatFromSending() async {
        let rtcProvider = RtcProvidingStub()
        let manualSleeper = ManualRoomHeartbeatSleeper()
        let heartbeat = RoomHeartbeat(
            rtcProvider: rtcProvider,
            sleeper: manualSleeper.sleeper
        )

        heartbeat.start(userID: "user-id")
        await waitUntil { await manualSleeper.isWaiting }
        heartbeat.stop()
        await Task.yield()

        XCTAssertTrue(rtcProvider.heartbeatMessages.isEmpty)
    }

    func testHeartbeatContinuesAfterSendFailure() async {
        let rtcProvider = RtcProvidingStub(
            sendRoomMessageError: XmaxError(
                code: .rtcError,
                message: "send failed"
            )
        )
        let manualSleeper = ManualRoomHeartbeatSleeper()
        let heartbeat = RoomHeartbeat(
            rtcProvider: rtcProvider,
            sleeper: manualSleeper.sleeper
        )

        heartbeat.start(userID: "user-id")
        await waitUntil { await manualSleeper.isWaiting }
        await manualSleeper.resume()
        await waitUntil { rtcProvider.heartbeatMessages.count == 1 }
        await waitUntil { await manualSleeper.isWaiting }
        await manualSleeper.resume()
        await waitUntil { rtcProvider.heartbeatMessages.count == 2 }
        heartbeat.stop()

        XCTAssertEqual(rtcProvider.heartbeatMessages.count, 2)
    }
}

private extension RoomHeartbeatTests {
    func decode(_ message: String) throws -> [String: Any] {
        let data = try XCTUnwrap(message.data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous condition")
    }
}

private actor ManualRoomHeartbeatSleeper {

    // 等待状态
    private var waiter: CheckedContinuation<Void, Never>?
    private var cancellationPending = false

    nonisolated var sleeper: RoomHeartbeatSleeper {
        RoomHeartbeatSleeper { [weak self] in
            guard let self else {
                throw CancellationError()
            }
            try await self.sleep()
        }
    }

    var isWaiting: Bool {
        waiter != nil
    }

    func resume() {
        waiter?.resume()
        waiter = nil
    }
}

private extension ManualRoomHeartbeatSleeper {
    func sleep() async throws {
        try await withTaskCancellationHandler {
            await suspend()
            try Task.checkCancellation()
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func suspend() async {
        await withCheckedContinuation { continuation in
            if cancellationPending {
                cancellationPending = false
                continuation.resume()
            } else {
                waiter = continuation
            }
        }
    }

    func cancel() {
        if let waiter {
            self.waiter = nil
            waiter.resume()
        } else {
            cancellationPending = true
        }
    }
}

private extension RtcProvidingStub {
    var heartbeatMessages: [String] {
        calls.compactMap { call in
            guard case .sendRoomMessage(let message) = call else {
                return nil
            }
            return message
        }
    }
}
