import CoreGraphics
import XCTest
@testable import XmaxSDK

@MainActor
final class XmaxRealtimeManagerTests: XCTestCase {
    func testPublicInterfaceForwardsCameraLifecycle() async throws {
        let components = makeComponents()
        let manager: any XmaxRealtimeManaging = components.manager

        let stream = try await manager.createLocalCameraStream(
            videoFormat: videoFormat
        )
        let switchedStream = try await manager.switchCamera()
        try await manager.stopLocalCameraStream()

        XCTAssertEqual(manager.options.model, .x2_0)
        XCTAssertTrue(stream.videoTrack === switchedStream.videoTrack)
        XCTAssertEqual(switchedStream.videoTrack?.position, .back)
        XCTAssertEqual(components.rtcProvider.calls.first, .initialize)
        XCTAssertEqual(components.rtcProvider.calls.last, .destroy)
    }

    func testConnectAndDisconnectPreserveLocalCameraPreview() async throws {
        let components = makeComponents()
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )

        let remoteStream = try await components.manager.connect(
            localStream: localStream
        )
        let connectedState = await components.manager.currentState

        XCTAssertEqual(remoteStream.id, StreamID.remote.rawValue)
        XCTAssertEqual(connectedState.connectionState, .connected)
        XCTAssertEqual(connectedState.sessionID, "session-id")

        await components.manager.disconnect()
        let disconnectedState = await components.manager.currentState
        let stillOwnsLocalStream = await components.mediaManager.owns(
            localStream
        )

        XCTAssertEqual(disconnectedState.connectionState, .disconnected)
        XCTAssertEqual(disconnectedState.sessionID, "session-id")
        XCTAssertTrue(stillOwnsLocalStream)
        XCTAssertFalse(components.rtcProvider.calls.contains(.destroy))

        try await components.manager.stopLocalCameraStream()
        XCTAssertEqual(components.rtcProvider.calls.last, .destroy)
    }

    func testGenerationLifecycleTransitionsAndUpdatesCondition() async throws {
        let components = makeComponents()
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
        _ = try await components.manager.connect(localStream: localStream)

        let startTask = Task {
            try await components.manager.startGeneration(
                context: RealtimeContext(prompt: "first")
            )
        }
        await waitForEvent("start", rtcProvider: components.rtcProvider)
        let startEvent = try XCTUnwrap(
            decodedEvents(components.rtcProvider).first {
                $0["event"] as? String == "start"
            }
        )
        let taskID = try XCTUnwrap(startEvent["uid"] as? String)
        components.rtcProvider.emitSeiMessage(
            stream: RemoteStream(
                roomID: "room-id",
                userID: "bot-user"
            ),
            message: taskID
        )
        try await startTask.value

        let generatingState = await components.manager.currentState
        XCTAssertEqual(generatingState.connectionState, .generating)
        XCTAssertEqual(generatingState.taskID, taskID)

        try await components.manager.startGeneration(
            context: RealtimeContext(prompt: "second")
        )
        let changeEvent = try XCTUnwrap(
            decodedEvents(components.rtcProvider).last {
                $0["event"] as? String == "change_condition"
            }
        )
        XCTAssertEqual(changeEvent["uid"] as? String, taskID)
        XCTAssertEqual(changeEvent["condition_version"] as? Int, 1)

        await components.manager.stopGeneration()
        let stoppedState = await components.manager.currentState
        XCTAssertEqual(stoppedState.connectionState, .connected)
        XCTAssertNil(stoppedState.taskID)

        await components.manager.disconnect()
        try await components.manager.stopLocalCameraStream()
    }

    func testRepeatedDisconnectReusesSingleTermination() async throws {
        let components = makeComponents()
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
        _ = try await components.manager.connect(localStream: localStream)

        async let firstDisconnect: Void = components.manager.disconnect()
        async let secondDisconnect: Void = components.manager.disconnect()
        _ = await (firstDisconnect, secondDisconnect)

        XCTAssertEqual(
            components.sessionService.calls.filter {
                $0 == .closeSession("session-id")
            }.count,
            1
        )
        XCTAssertEqual(
            components.rtcProvider.calls.filter { $0 == .leaveRoom }.count,
            1
        )
        try await components.manager.stopLocalCameraStream()
    }

    func testHeartbeatFailureReportsErrorAndTerminatesConnection() async throws {
        let components = makeComponents()
        var receivedErrors: [XmaxError] = []
        await components.manager.setErrorListener { error in
            receivedErrors.append(error)
        }
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
        _ = try await components.manager.connect(localStream: localStream)
        let expectedError = XmaxError(
            code: .sessionError,
            message: "session closed"
        )

        await components.sessionService.failHeartbeat(
            sessionID: "session-id",
            error: expectedError
        )

        let state = await components.manager.currentState
        XCTAssertEqual(state.connectionState, .error)
        XCTAssertEqual(receivedErrors, [expectedError])
        XCTAssertFalse(components.rtcProvider.calls.contains(.destroy))
        try await components.manager.stopLocalCameraStream()
    }

    func testStateListenerReceivesCurrentAndLifecycleStates() async throws {
        let components = makeComponents()
        var states: [RealtimeConnectionState] = []
        await components.manager.setStateListener { state in
            states.append(state.connectionState)
        }
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )

        _ = try await components.manager.connect(localStream: localStream)
        await components.manager.disconnect()

        XCTAssertEqual(
            states,
            [.idle, .connecting, .connected, .disconnecting, .disconnected]
        )
        try await components.manager.stopLocalCameraStream()
    }

    func testConnectRejectsStreamOwnedByAnotherManager() async throws {
        let components = makeComponents()
        var receivedError: XmaxError?
        await components.manager.setErrorListener { error in
            receivedError = error
        }
        let foreignTrack = RealtimeVideoTrack(
            id: "foreign",
            videoFormat: videoFormat
        )

        do {
            _ = try await components.manager.connect(
                localStream: RealtimeMediaStream(
                    id: StreamID.local.rawValue,
                    videoTrack: foreignTrack
                )
            )
            XCTFail("Expected foreign stream to be rejected")
        } catch {
            XCTAssertEqual(
                (error as? XmaxError)?.code,
                .invalidConfiguration
            )
        }
        XCTAssertEqual(receivedError?.code, .invalidConfiguration)
    }

    func testQualityListenersReceiveRtcEvents() async {
        let components = makeComponents()
        var receivedQuality: RealtimeNetworkQuality?
        var receivedAlarm: RealtimePerformanceAlarm?
        await components.manager.setNetworkQualityListener { quality in
            receivedQuality = quality
        }
        await components.manager.setPerformanceAlarmListener { alarm in
            receivedAlarm = alarm
        }

        components.rtcProvider.emitNetworkQuality(
            uplink: .good,
            downlink: .poor
        )
        components.rtcProvider.emitPerformanceAlarm(
            limited: true,
            suggestedWidth: 540,
            suggestedHeight: 960,
            suggestedFrameRate: 15
        )

        XCTAssertEqual(
            receivedQuality,
            RealtimeNetworkQuality(uplink: .good, downlink: .poor)
        )
        XCTAssertEqual(receivedAlarm?.status, .limited)
        XCTAssertEqual(receivedAlarm?.suggestedVideoFormat?.fps, 15)
    }
}

private extension XmaxRealtimeManagerTests {
    struct Components {
        let manager: XmaxRealtimeManager
        let mediaManager: XmaxRealtimeMediaManager
        let rtcProvider: RtcProvidingStub
        let sessionService: RealtimeSessionServicingStub
    }

    var videoFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 1_024, height: 768, fps: 24)
    }

    func makeComponents() -> Components {
        let rtcProvider = RtcProvidingStub()
        let cameraManager = XmaxRealtimeCameraManager(
            rtcProvider: rtcProvider,
            permissionProvider: PermissionProvidingStub(),
            mediaService: MediaServicingStub(
                resolvedSize: CGSize(width: 1_024, height: 768)
            ),
            encodingController: EncodingController(rtcProvider: rtcProvider)
        )
        let mediaManager = XmaxRealtimeMediaManager(
            rtcProvider: rtcProvider,
            cameraManager: cameraManager
        )
        let roomController = RoomController(rtcProvider: rtcProvider)
        let remoteVideoController = RemoteVideoController(
            rtcProvider: rtcProvider
        )
        let streamController = StreamController(
            rtcProvider: rtcProvider,
            remoteStreamListener: { stream in
                try remoteVideoController.setRemoteStream(stream)
            },
            generationTiming: StreamGenerationTiming(
                timeoutNanoseconds: 1_000_000_000,
                confirmationDelayNanoseconds: 0
            )
        )
        let sessionService = RealtimeSessionServicingStub(
            session: RealtimeSession(
                id: "session-id",
                userID: "user-id",
                status: "ACTIVE",
                connection: RealtimeSessionConnection(
                    roomID: "room-id",
                    userID: "user-id",
                    token: "room-token",
                    botName: "bot-user"
                ),
                closeReason: nil
            )
        )
        let connectionManager = XmaxRealtimeConnectionManager(
            rtcProvider: rtcProvider,
            sessionService: sessionService,
            roomController: roomController,
            remoteVideoController: remoteVideoController,
            streamController: streamController
        )
        return Components(
            manager: XmaxRealtimeManager(
                options: RealtimeConfiguration(model: .x2_0),
                qualityController: QualityController(
                    rtcProvider: rtcProvider
                ),
                streamController: streamController,
                mediaManager: mediaManager,
                connectionManager: connectionManager,
                generationManager: XmaxRealtimeGenerationManager(
                    roomController: roomController,
                    streamController: streamController
                )
            ),
            mediaManager: mediaManager,
            rtcProvider: rtcProvider,
            sessionService: sessionService
        )
    }

    func waitForEvent(
        _ event: String,
        rtcProvider: RtcProvidingStub
    ) async {
        for _ in 0..<1_000 {
            if decodedEvents(rtcProvider).contains(where: {
                $0["event"] as? String == event
            }) {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for room event: \(event)")
    }

    func decodedEvents(
        _ rtcProvider: RtcProvidingStub
    ) -> [[String: Any]] {
        rtcProvider.managerMessages.compactMap { message in
            guard let data = message.data(using: .utf8) else {
                return nil
            }
            return try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        }
    }
}

private extension RtcProvidingStub {
    var managerMessages: [String] {
        calls.compactMap { call in
            guard case .sendRoomMessage(let message) = call else {
                return nil
            }
            return message
        }
    }
}
