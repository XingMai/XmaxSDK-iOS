import CoreGraphics
import XCTest
@testable import XmaxSDK

@MainActor
final class XmaxRealtimeManagerTests: XCTestCase {
    func testPublicAudioVolumeControlsForwardNormalizedValues() async throws {
        let components = makeComponents()

        try await components.manager.setLocalAudioVolume(0.6)
        try await components.manager.setRemoteAudioVolume(0.35)

        XCTAssertTrue(components.videoSource.calls.contains(
            .setLocalAudioVolume(0.6)
        ))

        let localStream = try await components.manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4")
        )
        _ = try await components.manager.connect(localStream: localStream)
        let startTask = Task {
            try await components.manager.startGeneration(
                context: RealtimeContext(prompt: "video")
            )
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        let startEvent = try XCTUnwrap(
            decodedEvents(components.rtcManager).first {
                $0["event"] as? String == "start"
            }
        )
        let taskID = try XCTUnwrap(startEvent["uid"] as? String)
        components.rtcManager.emitSeiMessage(
            stream: RemoteStream(
                roomID: "room-id",
                userID: "bot-user"
            ),
            message: taskID
        )
        XCTAssertFalse(components.rtcManager.calls.contains(
            .subscribeRemoteAudio(
                userID: "bot-user",
                subscribe: true
            )
        ))
        try components.rtcManager.emitRemoteVideoFrame()
        try await startTask.value

        XCTAssertTrue(components.rtcManager.calls.contains(
            .setRemoteAudioVolume(35, userID: "bot-user")
        ))

        await components.manager.disconnect()
        try await components.manager.stopLocalVideoStream()
    }

    func testPublicAudioVolumeControlsRejectOutOfRangeValues() async {
        let components = makeComponents()

        for volume: Float in [-0.01, 1.01, .infinity, .nan] {
            do {
                try await components.manager.setLocalAudioVolume(volume)
                XCTFail("Expected invalid audio volume to fail")
            } catch {
                XCTAssertEqual(
                    error as? XmaxError,
                    XmaxError(
                        code: .invalidConfiguration,
                        message: "Audio volume must be between 0 and 1"
                    )
                )
            }
        }
    }

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
        XCTAssertEqual(components.rtcManager.calls.first, .initialize)
        XCTAssertEqual(components.rtcManager.calls.last, .destroy)
    }

    func testUnsupportedInitialFrameInterpolationDoesNotStopStreamCreation()
        async throws {
        let components = makeComponents(
            frameInterpolationEnabled: true,
            frameInterpolationSupported: false
        )
        var receivedErrors: [XmaxError] = []
        await components.manager.setErrorListener { error in
            receivedErrors.append(error)
        }

        let stream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat
        )
        let interpolationEnabled =
            await components.manager.isFrameInterpolationEnabled

        XCTAssertNotNil(stream.videoTrack)
        XCTAssertFalse(interpolationEnabled)
        XCTAssertEqual(
            receivedErrors.map(\.code),
            [.frameInterpolationUnsupported]
        )
        try await components.manager.stopLocalCameraStream()
    }

    func testPublicInterfaceForwardsImageLifecycle() async throws {
        let components = makeComponents()
        let manager: any XmaxRealtimeManaging = components.manager
        let fileURL = URL(fileURLWithPath: "/tmp/reference.png")

        let stream = try await manager.createLocalImageStream(
            fileURL: fileURL
        )
        try await manager.stopLocalImageStream()

        XCTAssertEqual(stream.videoTrack?.videoFormat, imageFormat)
        XCTAssertNil(stream.videoTrack?.position)
        XCTAssertEqual(components.rtcManager.calls.first, .initialize)
        XCTAssertEqual(components.rtcManager.calls.last, .destroy)
    }

    func testPublicInterfaceAcceptsEncodedImageData() async throws {
        let components = makeComponents()
        let imageData = Data("encoded-image".utf8)

        let stream = try await components.manager.createLocalImageStream(
            imageData: imageData
        )

        XCTAssertEqual(stream.videoTrack?.videoFormat, imageFormat)
        XCTAssertEqual(
            components.imageSource.calls,
            [.prepareData(imageData, nil), .start]
        )
        try await components.manager.stopLocalImageStream()
    }

    func testPublicInterfaceAcceptsUIKitImage() async throws {
        let components = makeComponents()
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 2, height: 2)
        ).image { context in
            UIColor.red.setFill()
            context.cgContext.fill(
                CGRect(x: 0, y: 0, width: 2, height: 2)
            )
        }

        let stream = try await components.manager.createLocalImageStream(
            image: image
        )

        XCTAssertEqual(stream.videoTrack?.videoFormat, imageFormat)
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(
            components.imageSource.calls,
            [
                .prepareDecoded(
                    CGSize(width: cgImage.width, height: cgImage.height),
                    nil
                ),
                .start
            ]
        )
        try await components.manager.stopLocalImageStream()
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
        XCTAssertTrue(
            components.rtcManager.calls.contains(
                .configureVideoEncoding(
                    VideoEncodingConfiguration(
                        width: videoFormat.width,
                        height: videoFormat.height,
                        frameRate: videoFormat.fps
                    )
                )
            )
        )

        await components.manager.disconnect()
        let disconnectedState = await components.manager.currentState
        let stillOwnsLocalStream = await components.mediaController.owns(
            localStream
        )

        XCTAssertEqual(disconnectedState.connectionState, .disconnected)
        XCTAssertEqual(disconnectedState.sessionID, "session-id")
        XCTAssertTrue(stillOwnsLocalStream)
        XCTAssertFalse(components.rtcManager.calls.contains(.destroy))

        try await components.manager.stopLocalCameraStream()
        XCTAssertEqual(components.rtcManager.calls.last, .destroy)
    }

    func testConnectedCameraReplacementUpdatesEncoderConfig() async throws {
        let components = makeComponents()
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
        _ = try await components.manager.connect(localStream: localStream)

        _ = try await components.manager.replaceLocalCameraStream(
            videoFormat: RealtimeVideoFormat(
                width: 1_280,
                height: 720,
                fps: 30
            ),
            position: .back
        )

        let configurations = components.rtcManager.calls.compactMap {
            call -> VideoEncodingConfiguration? in
            guard case .configureVideoEncoding(let configuration) = call else {
                return nil
            }
            return configuration
        }
        XCTAssertEqual(
            configurations,
            [
                VideoEncodingConfiguration(
                    width: videoFormat.width,
                    height: videoFormat.height,
                    frameRate: videoFormat.fps
                ),
                VideoEncodingConfiguration(
                    width: videoFormat.width,
                    height: videoFormat.height,
                    frameRate: 30
                )
            ]
        )

        await components.manager.disconnect()
        try await components.manager.stopLocalCameraStream()
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
        await waitForEvent("start", rtcManager: components.rtcManager)
        let startEvent = try XCTUnwrap(
            decodedEvents(components.rtcManager).first {
                $0["event"] as? String == "start"
            }
        )
        let taskID = try XCTUnwrap(startEvent["uid"] as? String)
        components.rtcManager.emitSeiMessage(
            stream: RemoteStream(
                roomID: "room-id",
                userID: "bot-user"
            ),
            message: taskID
        )
        try components.rtcManager.emitRemoteVideoFrame()
        try await startTask.value

        let generatingState = await components.manager.currentState
        XCTAssertEqual(generatingState.connectionState, .generating)
        XCTAssertEqual(generatingState.taskID, taskID)

        try await components.manager.startGeneration(
            context: RealtimeContext(prompt: "second")
        )
        let changeEvent = try XCTUnwrap(
            decodedEvents(components.rtcManager).last {
                $0["event"] as? String == "change_condition"
            }
        )
        XCTAssertEqual(changeEvent["uid"] as? String, taskID)
        XCTAssertNil(changeEvent["condition_version"])

        await components.manager.stopGeneration()
        let stoppedState = await components.manager.currentState
        XCTAssertEqual(stoppedState.connectionState, .connected)
        XCTAssertNil(stoppedState.taskID)

        await components.manager.disconnect()
        try await components.manager.stopLocalCameraStream()
    }

    func testVideoGenerationKeepsTimelineRunningAndControlsAudio() async throws {
        let components = makeComponents()
        let localStream = try await components.manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: nil
        )
        _ = try await components.manager.connect(localStream: localStream)

        let startTask = Task {
            try await components.manager.startGeneration(
                context: RealtimeContext(prompt: "video")
            )
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        let startEvent = try XCTUnwrap(
            decodedEvents(components.rtcManager).first {
                $0["event"] as? String == "start"
            }
        )
        let taskID = try XCTUnwrap(startEvent["uid"] as? String)
        components.rtcManager.emitSeiMessage(
            stream: RemoteStream(
                roomID: "room-id",
                userID: "bot-user"
            ),
            message: taskID
        )
        try components.rtcManager.emitRemoteVideoFrame()
        try await startTask.value

        XCTAssertTrue(components.videoSource.calls.contains(
            .setLocalAudioPreviewMuted(true)
        ))
        XCTAssertFalse(components.videoSource.calls.contains(
            .setLocalAudioPreviewMuted(false)
        ))
        XCTAssertTrue(components.rtcManager.calls.contains(.publishLocalAudio))
        XCTAssertTrue(components.rtcManager.calls.contains(
            .subscribeRemoteAudio(
                userID: "bot-user",
                subscribe: true
            )
        ))

        await components.manager.stopGeneration()
        XCTAssertTrue(components.videoSource.calls.contains(
            .setLocalAudioPreviewMuted(false)
        ))
        XCTAssertTrue(components.rtcManager.calls.contains(
            .subscribeRemoteAudio(
                userID: "bot-user",
                subscribe: false
            )
        ))
        await components.manager.disconnect()
        try await components.manager.stopLocalVideoStream()
    }

    func testGenerationEntryConnectsOnlyAfterUserStartsGeneration()
        async throws {
        let components = makeComponents()
        let localStream = try await components.manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: nil
        )

        XCTAssertFalse(
            components.sessionService.calls.contains(.createSession(.x2_0))
        )

        let startTask = Task {
            try await components.manager.startGeneration(
                localStream: localStream,
                context: RealtimeContext(prompt: "video")
            )
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        let startEvent = try XCTUnwrap(
            decodedEvents(components.rtcManager).first {
                $0["event"] as? String == "start"
            }
        )
        let taskID = try XCTUnwrap(startEvent["uid"] as? String)
        components.rtcManager.emitSeiMessage(
            stream: RemoteStream(
                roomID: "room-id",
                userID: "bot-user"
            ),
            message: taskID
        )
        try components.rtcManager.emitRemoteVideoFrame()

        let remoteStream = try await startTask.value

        XCTAssertEqual(remoteStream.id, StreamID.remote.rawValue)
        XCTAssertTrue(
            components.sessionService.calls.contains(.createSession(.x2_0))
        )

        await components.manager.stopGeneration()
        await components.manager.disconnect()
        try await components.manager.stopLocalVideoStream()
    }

    func testGenerationEntryRestoresLocalAudioWhenConnectionFails()
        async throws {
        let components = makeComponents(
            sessionCreateError: XmaxError(
                code: .sessionError,
                message: "connect failed"
            )
        )
        let localStream = try await components.manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: nil
        )
        do {
            _ = try await components.manager.startGeneration(
                localStream: localStream,
                context: RealtimeContext(prompt: "video")
            )
            XCTFail("Expected connection to fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .sessionError)
        }

        XCTAssertTrue(components.videoSource.calls.contains(
            .setLocalAudioPreviewMuted(true)
        ))
        XCTAssertTrue(components.videoSource.calls.contains(
            .setLocalAudioPreviewMuted(false)
        ))

        try await components.manager.stopLocalVideoStream()
    }

    func testFileVideoConfiguresEncoderBeforeConnecting() async throws {
        let components = makeComponents()

        _ = try await components.manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: nil
        )

        let configurations = components.rtcManager.calls.compactMap {
            call -> VideoEncodingConfiguration? in
            guard case .configureVideoEncoding(let configuration) = call else {
                return nil
            }
            return configuration
        }
        XCTAssertEqual(
            configurations,
            [
                VideoEncodingConfiguration(
                    width: imageFormat.width,
                    height: imageFormat.height,
                    frameRate: imageFormat.fps
                )
            ]
        )

        try await components.manager.stopLocalVideoStream()
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
            components.rtcManager.calls.filter { $0 == .leaveRoom }.count,
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
        XCTAssertFalse(components.rtcManager.calls.contains(.destroy))
        try await components.manager.stopLocalCameraStream()
    }

    func testStopGenerationFailureReportsError() async throws {
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
        let startTask = Task {
            try await components.manager.startGeneration(
                context: RealtimeContext(prompt: "prompt")
            )
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        let startEvent = try XCTUnwrap(
            decodedEvents(components.rtcManager).first {
                $0["event"] as? String == "start"
            }
        )
        let taskID = try XCTUnwrap(startEvent["uid"] as? String)
        components.rtcManager.emitSeiMessage(
            stream: RemoteStream(
                roomID: "room-id",
                userID: "bot-user"
            ),
            message: taskID
        )
        try components.rtcManager.emitRemoteVideoFrame()
        try await startTask.value
        let expectedError = XmaxError(
            code: .rtcError,
            message: "sendRoomMessage failed: -1"
        )
        components.rtcManager.setSendRoomMessageError(expectedError)

        await components.manager.stopGeneration()

        XCTAssertEqual(receivedErrors, [expectedError])
        await components.manager.disconnect()
        try await components.manager.stopLocalCameraStream()
    }

    func testDisconnectFailureReportsError() async throws {
        let expectedError = XmaxError(
            code: .networkError,
            message: "close session failed"
        )
        let components = makeComponents(sessionCloseError: expectedError)
        var receivedErrors: [XmaxError] = []
        await components.manager.setErrorListener { error in
            receivedErrors.append(error)
        }
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
        _ = try await components.manager.connect(localStream: localStream)

        await components.manager.disconnect()

        XCTAssertEqual(receivedErrors, [expectedError])
        let state = await components.manager.currentState
        XCTAssertEqual(state.connectionState, .disconnected)
        XCTAssertEqual(state.sessionID, "session-id")
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

    func testCameraPreviewReadyListenerReceivesRtcEvent() async {
        let components = makeComponents()
        var callbackCount = 0
        await components.manager.setCameraPreviewReadyListener {
            callbackCount += 1
        }

        components.rtcManager.emitCameraPreviewReady()
        await components.manager.setCameraPreviewReadyListener(nil)
        components.rtcManager.emitCameraPreviewReady()

        XCTAssertEqual(callbackCount, 1)
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

        components.rtcManager.emitNetworkQuality(
            uplink: .good,
            downlink: .poor
        )
        components.rtcManager.emitPerformanceAlarm(
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
        let mediaController: MediaController
        let rtcManager: RtcManagingStub
        let sessionService: RealtimeSessionServicingStub
        let imageSource: ImageSourceControllingStub
        let videoSource: MediaSourceControllingStub
    }

    var videoFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 1_024, height: 768, fps: 24)
    }

    var imageFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 832, height: 1_472, fps: 24)
    }

    func makeComponents(
        sessionCreateError: (any Error)? = nil,
        sessionCloseError: (any Error)? = nil,
        frameInterpolationEnabled: Bool = false,
        frameInterpolationSupported: Bool = false
    ) -> Components {
        let errorHandler = RealtimeErrorHandler()
        let rtcManager = RtcManagingStub()
        let mediaService = MediaServicingStub(
            resolvedSize: CGSize(width: 1_024, height: 768),
            frameInterpolationSupported: frameInterpolationSupported
        )
        let renderController = RenderController(
            rtcManager: rtcManager,
            frameInterpolationEnabled: frameInterpolationEnabled,
            errorListener: { errorHandler.forward($0) }
        )
        let streamController = StreamController(
            rtcManager: rtcManager,
            errorListener: { errorHandler.forward($0) },
            remoteStreamListener: { stream in
                try renderController.setRemoteStream(stream)
            },
            generationTiming: StreamGenerationTiming(
                timeoutNanoseconds: 1_000_000_000
            )
        )
        let cameraController = CameraController(
            rtcManager: rtcManager,
            permissionManager: PermissionManagingStub(),
            mediaService: mediaService,
            errorListener: { errorHandler.forward($0) }
        )
        let imageSource = ImageSourceControllingStub(
            resolvedFormat: imageFormat
        )
        let imageController = ImageController(
            rtcManager: rtcManager,
            imageSourceController: imageSource
        )
        let videoSource = MediaSourceControllingStub(
            configuration: MediaSourceConfiguration(
                videoFormat: imageFormat,
                hasAudio: true
            )
        )
        let videoController = VideoController(
            rtcManager: rtcManager,
            permissionManager: PermissionManagingStub(),
            mediaSourceController: videoSource
        )
        let mediaController = MediaController(
            rtcManager: rtcManager,
            cameraController: cameraController,
            imageController: imageController,
            videoController: videoController
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
            ),
            createError: sessionCreateError,
            closeError: sessionCloseError
        )
        let connectionManager = XmaxRealtimeConnectionManager(
            sessionService: sessionService,
            interactionController: mediaController,
            renderController: renderController,
            streamController: streamController
        )
        return Components(
            manager: XmaxRealtimeManager(
                options: RealtimeConfiguration(
                    model: .x2_0,
                    isFrameInterpolationEnabled:
                        frameInterpolationEnabled
                ),
                streamController: streamController,
                mediaController: mediaController,
                renderController: renderController,
                mediaService: mediaService,
                connectionManager: connectionManager,
                errorHandler: errorHandler,
                generationManager: XmaxRealtimeGenerationManager(
                    interactionController: mediaController,
                    streamController: streamController
                )
            ),
            mediaController: mediaController,
            rtcManager: rtcManager,
            sessionService: sessionService,
            imageSource: imageSource,
            videoSource: videoSource
        )
    }

    func makeBGRAFrame(timestampUs: Int64) throws -> VideoFrame {
        try VideoFrame(
            format: VideoFormat(
                width: 1,
                height: 1,
                pixelFormat: .bgra
            ),
            timestampUs: timestampUs,
            planes: [
                VideoFramePlane(
                    data: Data([0, 0, 0, 255]),
                    stride: 4
                )
            ]
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

    func decodedEvents(
        _ rtcManager: RtcManagingStub
    ) -> [[String: Any]] {
        rtcManager.managerMessages.compactMap { message in
            guard let data = message.data(using: .utf8) else {
                return nil
            }
            return try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
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
    var managerMessages: [String] {
        calls.compactMap { call in
            guard case .sendRoomMessage(let message) = call else {
                return nil
            }
            return message
        }
    }
}
