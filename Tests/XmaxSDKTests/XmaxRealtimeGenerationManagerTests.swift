import XCTest
@testable import XmaxSDK

@MainActor
final class XmaxRealtimeGenerationManagerTests: XCTestCase {
    func testStartSendsSignalRestartsMediaAndWaitsForMatchingSei() async throws {
        let components = try await makeComponents()
        let restartCounter = GenerationInvocationCounter()
        let context = RealtimeContext(prompt: "first prompt")

        let startTask = Task {
            try await components.manager.start(
                videoFormat: videoFormat,
                context: context,
                ensureCurrent: {},
                onGenerationStarted: {
                    restartCounter.increment()
                }
            )
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        components.rtcManager.emitSeiMessage(
            stream: remoteStream,
            message: "task-fixed"
        )

        let taskID = try await startTask.value

        XCTAssertEqual(taskID, "task-fixed")
        XCTAssertEqual(restartCounter.value, 1)
        XCTAssertEqual(components.remoteStreams.values, [remoteStream])
        let startEvent = try XCTUnwrap(
            decodedEvents(components.rtcManager).first {
                $0["event"] as? String == "start"
            }
        )
        XCTAssertEqual(startEvent["uid"] as? String, "task-fixed")
        await components.manager.stop(taskID: taskID)
        await components.roomController.leave()
    }

    func testStartTimeoutStopsTaskAndSendsStopSignal() async throws {
        let components = try await makeComponents(
            timing: StreamGenerationTiming(
                timeoutNanoseconds: 0
            )
        )

        do {
            _ = try await components.manager.start(
                videoFormat: videoFormat,
                context: RealtimeContext(prompt: "prompt"),
                ensureCurrent: {},
                onGenerationStarted: {}
            )
            XCTFail("Expected generation start to time out")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .timeout,
                    message: "Realtime generation start timed out"
                )
            )
        }

        XCTAssertEqual(
            decodedEvents(components.rtcManager).compactMap {
                $0["event"] as? String
            },
            ["start", "stop"]
        )
        XCTAssertNil(components.remoteStreams.values.last ?? nil)
        await components.roomController.leave()
    }

    func testUpdateReusesTaskWithoutAddingUnspecifiedFields() async throws {
        let components = try await makeComponents()
        let startTask = Task {
            try await components.manager.start(
                videoFormat: videoFormat,
                context: RealtimeContext(prompt: "first"),
                ensureCurrent: {},
                onGenerationStarted: {}
            )
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        components.rtcManager.emitSeiMessage(
            stream: remoteStream,
            message: "task-fixed"
        )
        let taskID = try await startTask.value

        try await components.manager.update(
            taskID: taskID,
            videoFormat: videoFormat,
            context: RealtimeContext(prompt: "second")
        )
        try await components.manager.update(
            taskID: taskID,
            videoFormat: videoFormat,
            context: RealtimeContext(prompt: "third")
        )

        let changes = decodedEvents(components.rtcManager).filter {
            $0["event"] as? String == "change_condition"
        }
        XCTAssertTrue(changes.allSatisfy { $0["condition_version"] == nil })
        XCTAssertTrue(
            changes.allSatisfy { $0["uid"] as? String == taskID }
        )
        await components.manager.stop(taskID: taskID)
        await components.roomController.leave()
    }

    func testStopClearsRemoteStreamAndSendsActualTaskID() async throws {
        let components = try await makeComponents()
        let startTask = Task {
            try await components.manager.start(
                videoFormat: videoFormat,
                context: RealtimeContext(prompt: "prompt"),
                ensureCurrent: {},
                onGenerationStarted: {}
            )
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        components.rtcManager.emitSeiMessage(
            stream: remoteStream,
            message: "task-fixed"
        )
        let taskID = try await startTask.value

        await components.manager.stop(taskID: taskID)

        XCTAssertNil(components.remoteStreams.values.last ?? nil)
        let stopEvent = try XCTUnwrap(
            decodedEvents(components.rtcManager).last {
                $0["event"] as? String == "stop"
            }
        )
        XCTAssertEqual(stopEvent["uid"] as? String, taskID)
        await components.roomController.leave()
    }

    func testFirstGenerationRequiresContext() async throws {
        let components = try await makeComponents()

        do {
            _ = try await components.manager.start(
                videoFormat: videoFormat,
                context: nil,
                ensureCurrent: {},
                onGenerationStarted: {}
            )
            XCTFail("Expected first generation to require context")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "A realtime context is required for the first " +
                        "generation"
                )
            )
        }
        XCTAssertTrue(components.rtcManager.generationMessages.isEmpty)
        await components.roomController.leave()
    }

    func testStoppedGenerationReusesContextUntilReset() async throws {
        let components = try await makeComponents()
        let firstStart = Task {
            try await components.manager.start(
                videoFormat: videoFormat,
                context: RealtimeContext(prompt: "cached prompt"),
                ensureCurrent: {},
                onGenerationStarted: {}
            )
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        components.rtcManager.emitSeiMessage(
            stream: remoteStream,
            message: "task-fixed"
        )
        let firstTaskID = try await firstStart.value
        await components.manager.stop(taskID: firstTaskID)

        let secondStart = Task {
            try await components.manager.start(
                videoFormat: videoFormat,
                context: nil,
                ensureCurrent: {},
                onGenerationStarted: {}
            )
        }
        await waitForEventCount(
            "start",
            count: 2,
            rtcManager: components.rtcManager
        )
        components.rtcManager.emitSeiMessage(
            stream: remoteStream,
            message: "task-fixed"
        )
        let secondTaskID = try await secondStart.value
        await components.manager.reset(taskID: secondTaskID)

        do {
            _ = try await components.manager.start(
                videoFormat: videoFormat,
                context: nil,
                ensureCurrent: {},
                onGenerationStarted: {}
            )
            XCTFail("Expected reset to clear cached context")
        } catch {
            XCTAssertEqual(
                (error as? XmaxError)?.code,
                .invalidConfiguration
            )
        }
        await components.roomController.leave()
    }

    func testTaskIDUsesCompactBase64URLFormat() {
        let first = XmaxRealtimeGenerationManager.createTaskID()
        let second = XmaxRealtimeGenerationManager.createTaskID()
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
                "abcdefghijklmnopqrstuvwxyz0123456789-_"
        )

        XCTAssertTrue(first.hasPrefix("task-"))
        XCTAssertEqual(first.count, 27)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(
            first.dropFirst(5).unicodeScalars.allSatisfy {
                allowed.contains($0)
            }
        )
    }
}

private extension XmaxRealtimeGenerationManagerTests {
    struct Components {
        let manager: XmaxRealtimeGenerationManager
        let roomController: RoomController
        let rtcManager: RtcManagingStub
        let remoteStreams: RemoteStreamRecorder
    }

    var videoFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 720, height: 1280, fps: 24)
    }

    var remoteStream: RemoteStream {
        RemoteStream(roomID: "room-id", userID: "bot-user")
    }

    func makeComponents(
        timing: StreamGenerationTiming = StreamGenerationTiming(
            timeoutNanoseconds: 1_000_000_000
        )
    ) async throws -> Components {
        let rtcManager = RtcManagingStub()
        let roomController = RoomController(rtcManager: rtcManager)
        try await roomController.join(
            connection: RealtimeSessionConnection(
                roomID: "room-id",
                userID: "user-id",
                token: "room-token",
                botName: "bot-user"
            ),
            ensureActive: {}
        )
        let remoteStreams = RemoteStreamRecorder()
        let streamController = StreamController(
            rtcManager: rtcManager,
            remoteStreamListener: { stream in
                remoteStreams.append(stream)
            },
            generationTiming: timing
        )
        try streamController.configureRoom(
            roomID: "room-id",
            botName: "bot-user"
        )
        let transportController = TransportController(
            roomController: roomController,
            streamController: streamController,
            encodingController: EncodingController(rtcManager: rtcManager),
            qualityController: QualityController(rtcManager: rtcManager)
        )
        return Components(
            manager: XmaxRealtimeGenerationManager(
                transportController: transportController,
                taskIDGenerator: { "task-fixed" }
            ),
            roomController: roomController,
            rtcManager: rtcManager,
            remoteStreams: remoteStreams
        )
    }

    func waitForEvent(
        _ event: String,
        rtcManager: RtcManagingStub
    ) async {
        for _ in 0..<1_000 {
            if decodedEvents(rtcManager).contains(where: {
                $0["event"] as? String == event
            }) {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for room event: \(event)")
    }

    func waitForEventCount(
        _ event: String,
        count: Int,
        rtcManager: RtcManagingStub
    ) async {
        for _ in 0..<1_000 {
            let currentCount = decodedEvents(rtcManager).filter {
                $0["event"] as? String == event
            }.count
            if currentCount >= count {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for room event count: \(event)")
    }

    func decodedEvents(
        _ rtcManager: RtcManagingStub
    ) -> [[String: Any]] {
        rtcManager.generationMessages.compactMap { message in
            guard let data = message.data(using: .utf8) else {
                return nil
            }
            return try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        }
    }
}

private final class RemoteStreamRecorder: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var storedValues: [RemoteStream?] = []

    var values: [RemoteStream?] {
        lock.withLock { storedValues }
    }

    func append(_ stream: RemoteStream?) {
        lock.withLock {
            storedValues.append(stream)
        }
    }
}

private final class GenerationInvocationCounter: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock {
            storedValue += 1
        }
    }
}

private extension RtcManagingStub {
    var generationMessages: [String] {
        calls.compactMap { call in
            guard case .sendRoomMessage(let message) = call else {
                return nil
            }
            return message
        }
    }
}
