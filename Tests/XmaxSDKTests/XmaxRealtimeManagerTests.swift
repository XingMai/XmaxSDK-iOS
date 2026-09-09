import CoreGraphics
import UIKit
import XCTest
@testable import XmaxSDK

private extension XmaxRealtimeConnectionManager {
    func holdQueries(
        gate: DispatchSemaphore,
        entered: @Sendable () -> Void
    ) -> Bool {
        entered()
        return gate.wait(timeout: .now() + 5) == .success
    }
}

private extension XmaxRealtimeManager {
    func startGenerationDuringPreparationTest(
        localStream: RealtimeMediaStream?,
        entered: @Sendable () -> Void
    ) async throws {
        entered()
        let context = RealtimeContext(prompt: "video")
        if let localStream {
            _ = try await startGeneration(localStream: localStream, context: context)
        } else {
            try await startGeneration(context: context)
        }
    }
}

@MainActor
final class XmaxRealtimeManagerTests: XCTestCase {
    func testCancelledConditionUpdatesPreserveActiveGenerationForBothEntryPoints() async throws {
        let components = makeComponents()
        let local = try await components.manager.createLocalImageStream(
            fileURL: URL(fileURLWithPath: "/tmp/reference.png")
        )
        _ = try await components.manager.connect(localStream: local)
        let starting = Task {
            try await components.manager.startGeneration(context: RealtimeContext(prompt: "first"))
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        let start = try XCTUnwrap(decodedEvents(components.rtcManager).first {
            $0["event"] as? String == "start"
        })
        let taskID = try XCTUnwrap(start["uid"] as? String)
        components.rtcManager.emitSeiMessage(
            stream: RemoteStream(roomID: "room-id", userID: "bot-user"), message: taskID
        )
        try components.rtcManager.emitRemoteVideoFrame()
        try await starting.value
        let previousState = await components.manager.currentState

        for includesLocalStream in [false, true] {
            components.rtcManager.setSendRoomMessageError(
                XmaxError(code: .cancelled, message: "Condition update cancelled")
            )
            do {
                let context = RealtimeContext(prompt: "cancelled update")
                if includesLocalStream {
                    _ = try await components.manager.startGeneration(localStream: local, context: context)
                } else {
                    try await components.manager.startGeneration(context: context)
                }
                XCTFail("Expected condition update cancellation")
            } catch {
                XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
            }
            let current = await components.manager.currentState
            XCTAssertEqual(current, previousState)
            XCTAssertFalse(decodedEvents(components.rtcManager).contains {
                $0["event"] as? String == "stop"
            })
            components.rtcManager.setSendRoomMessageError(nil)
        }
        try await components.manager.startGeneration(context: RealtimeContext(prompt: "retry"))
        XCTAssertEqual(decodedEvents(components.rtcManager).filter {
            $0["event"] as? String == "start"
        }.count, 1)
        await components.manager.close()
    }

    func testTargetSizeSignalingFailurePreservesInterpolationAndGeneration() async throws {
        let components = makeComponents(frameInterpolationSupported: true)
        let local = try await components.manager.createLocalImageStream(
            fileURL: URL(fileURLWithPath: "/tmp/reference.png")
        )
        let remote = try await components.manager.connect(localStream: local)
        let starting = Task {
            try await components.manager.startGeneration(context: RealtimeContext(prompt: "first"))
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        let start = try XCTUnwrap(decodedEvents(components.rtcManager).first {
            $0["event"] as? String == "start"
        })
        let taskID = try XCTUnwrap(start["uid"] as? String)
        components.rtcManager.emitSeiMessage(
            stream: RemoteStream(roomID: "room-id", userID: "bot-user"), message: taskID
        )
        try components.rtcManager.emitRemoteVideoFrame()
        try await starting.value
        let state = await components.manager.currentState

        for enabled in [true, false] {
            let previousTarget = await components.connectionManager.currentTargetSize
            let previousFormat = remote.videoTrack?.videoFormat
            components.rtcManager.setSendRoomMessageError(XmaxError(code: .rtcError, message: "send failed"))
            do {
                try await components.manager.setFrameInterpolationEnabled(enabled)
                XCTFail("Expected signaling failure")
            } catch {
                XCTAssertEqual((error as? XmaxError)?.code, .rtcError)
                XCTAssertEqual((error as? XmaxError)?.severity, .recoverable)
            }
            let current = await components.manager.currentState
            let interpolationEnabled = await components.manager.isFrameInterpolationEnabled
            let target = await components.connectionManager.currentTargetSize
            XCTAssertEqual(current, state)
            XCTAssertEqual(interpolationEnabled, !enabled)
            XCTAssertEqual(target, previousTarget)
            XCTAssertEqual(remote.videoTrack?.videoFormat, previousFormat)
            components.rtcManager.setSendRoomMessageError(nil)
            try await components.manager.setFrameInterpolationEnabled(enabled)
        }
        await components.manager.close()
    }

    func testInterpolationBeforeGenerationUpdatesNextStartWithoutResizeEvent() async throws {
        let components = makeComponents(frameInterpolationSupported: true)
        let local = try await components.manager.createLocalImageStream(
            fileURL: URL(fileURLWithPath: "/tmp/reference.png")
        )
        try await components.manager.setFrameInterpolationEnabled(true)
        let remote = try await components.manager.connect(localStream: local)
        XCTAssertEqual(remote.videoTrack?.videoFormat?.size, CGSize(width: 702, height: 1242))
        try await components.manager.setFrameInterpolationEnabled(false)
        XCTAssertEqual(remote.videoTrack?.videoFormat, imageFormat)
        let target = await components.connectionManager.currentTargetSize
        XCTAssertEqual(target, imageFormat.size)
        XCTAssertFalse(decodedEvents(components.rtcManager).contains {
            $0["event"] as? String == "change_target_size"
        })
        await components.manager.close()
    }

    func testRuntimeInterpolationChangesTargetSizeWithoutRestartingGeneration() async throws {
        let components = makeComponents(
            frameInterpolationSupported: true
        )
        let local = try await components.manager.createLocalImageStream(
            fileURL: URL(fileURLWithPath: "/tmp/reference.png")
        )
        let remote = try await components.manager.connect(localStream: local)
        let targetFormat = RealtimeVideoFormat(width: 702, height: 1242, fps: 24)
        XCTAssertEqual(local.videoTrack?.videoFormat, imageFormat)
        XCTAssertEqual(remote.videoTrack?.videoFormat, imageFormat)

        let startTask = Task {
            try await components.manager.startGeneration(
                context: RealtimeContext(prompt: "first")
            )
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        let start = try XCTUnwrap(decodedEvents(components.rtcManager).first {
            $0["event"] as? String == "start"
        })
        let taskID = try XCTUnwrap(start["uid"] as? String)
        components.rtcManager.emitSeiMessage(
            stream: RemoteStream(roomID: "room-id", userID: "bot-user"),
            message: taskID
        )
        try components.rtcManager.emitRemoteVideoFrame()
        try await startTask.value
        let beforeToggle = await components.manager.currentState
        let encodingBeforeToggle = components.rtcManager.encodingConfigurations
        XCTAssertEqual(
            encodingBeforeToggle.last,
            VideoEncodingConfiguration(
                width: 832,
                height: 1472,
                frameRate: 24,
                minimumBitrate: 1488,
                maximumBitrate: 2977
            )
        )
        try await components.manager.setFrameInterpolationEnabled(true)
        try await components.manager.startGeneration(context: RealtimeContext(prompt: "second"))
        let change = try XCTUnwrap(decodedEvents(components.rtcManager).last {
            $0["event"] as? String == "change_condition"
        })
        let startParams = try XCTUnwrap(start["params"] as? [String: Any])
        XCTAssertEqual(startParams["size"] as? [Int], [832, 1472])
        XCTAssertNil(startParams["target_size"])
        let changeParams = try XCTUnwrap(change["params"] as? [String: Any])
        XCTAssertEqual(changeParams["size"] as? [Int], [832, 1472])
        XCTAssertEqual(changeParams["target_size"] as? [Int], [702, 1242])
        XCTAssertEqual(remote.videoTrack?.videoFormat, targetFormat)
        await components.mediaController.submitInteraction(InteractionFrame(
            points: [CGPoint(x: 50, y: 50)],
            viewportSize: CGSize(width: 100, height: 100),
            contentMode: .fit
        ))
        await waitForEvent("tracks", rtcManager: components.rtcManager)
        let tracks = try XCTUnwrap(decodedEvents(components.rtcManager).last {
            $0["event"] as? String == "tracks"
        })
        XCTAssertEqual(tracks["tracks"] as? [[Double]], [[416, 736]])

        try await components.manager.setFrameInterpolationEnabled(false)
        XCTAssertEqual(remote.videoTrack?.videoFormat, imageFormat)
        try await components.manager.setFrameInterpolationEnabled(true)
        XCTAssertEqual(remote.videoTrack?.videoFormat, targetFormat)
        try await components.manager.setFrameInterpolationEnabled(false)
        let events = decodedEvents(components.rtcManager)
        let resizeEvents = events.filter { $0["event"] as? String == "change_target_size" }
        XCTAssertEqual(resizeEvents.count, 4)
        for (event, size) in zip(resizeEvents, [[702, 1242], [832, 1472], [702, 1242], [832, 1472]]) {
            XCTAssertEqual(event["uid"] as? String, taskID)
            let params = try XCTUnwrap(event["params"] as? [String: Any])
            XCTAssertEqual(params["target_size"] as? [Int], size)
        }
        let afterToggle = await components.manager.currentState
        XCTAssertEqual(afterToggle, beforeToggle)
        XCTAssertEqual(components.rtcManager.encodingConfigurations, encodingBeforeToggle)
        XCTAssertEqual(events.filter { $0["event"] as? String == "start" }.count, 1)
        XCTAssertFalse(events.contains { $0["event"] as? String == "stop" })

        await components.manager.disconnect()
        let clearedTarget = await components.connectionManager.currentTargetSize
        XCTAssertNil(clearedTarget)
        let nextRemote = try await components.manager.connect(localStream: local)
        XCTAssertEqual(nextRemote.videoTrack?.videoFormat, imageFormat)
        let nextTarget = await components.connectionManager.currentTargetSize
        XCTAssertNil(nextTarget)
        await components.manager.close()
    }

    func testUnsupportedDeviceKeepsOriginalReturnSize() async throws {
        let components = makeComponents(frameInterpolationEnabled: true)
        let local = try await components.manager.createLocalImageStream(
            fileURL: URL(fileURLWithPath: "/tmp/reference.png")
        )
        let remote = try await components.manager.connect(localStream: local)
        XCTAssertEqual(remote.videoTrack?.videoFormat, imageFormat)
        let target = await components.connectionManager.currentTargetSize
        XCTAssertNil(target)
        await components.manager.close()
    }

    func testInterpolationDoesNotResizeStreamAlreadyWithinBudget() async throws {
        let components = makeComponents(
            frameInterpolationEnabled: true,
            frameInterpolationSupported: true
        )
        let local = try await components.manager.createLocalCameraStream(videoFormat: videoFormat)
        let remote = try await components.manager.connect(localStream: local)
        XCTAssertEqual(remote.videoTrack?.videoFormat, videoFormat)
        let target = await components.connectionManager.currentTargetSize
        XCTAssertNil(target)
        await components.manager.close()
    }

    func testDisconnectAllowsImmediateReconnectWhileGenerationIsCancelling() async throws {
        for _ in 0..<100 {
            let components = makeComponents()
            let localStream = try await components.manager.createLocalCameraStream(
                videoFormat: videoFormat,
                position: .front
            )
            let starting = Task.detached(priority: .background) {
                try await components.manager.startGeneration(
                    localStream: localStream,
                    context: RealtimeContext(prompt: "video")
                )
            }
            await waitForEvent("start", rtcManager: components.rtcManager)
            await components.manager.disconnect()

            // 不等待旧 startGeneration 的调用方收尾，立即重新连接。
            do {
                _ = try await components.manager.connect(localStream: localStream)
            } catch {
                XCTFail("Immediate reconnect failed: \(error)")
            }
            do {
                _ = try await starting.value
                XCTFail("Expected previous generation to be cancelled")
            } catch {
                XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
            }
            let state = await components.manager.currentState
            XCTAssertEqual(state.connectionState, .connected)
            await components.manager.close()
        }
    }

    func testCameraUsesModelDefaultFrameRate() async throws {
        let components = makeComponents(model: .x2_0)
        let manager: any XmaxRealtimeManaging = components.manager
        let stream = try await manager.createLocalCameraStream()
        let currentTrack = await components.mediaController.currentTrack
        XCTAssertTrue(currentTrack === stream.videoTrack)
        XCTAssertEqual(stream.videoTrack?.videoFormat?.fps, RealtimeModel.x2_0.defaultFrameRate)
        await manager.close()
    }

    func testPublicAudioVolumeControlsForwardNormalizedValues() async throws {
        let components = makeComponents()

        let initialLocalVolume = await components.manager.localAudioVolume
        let initialRemoteVolume = await components.manager.remoteAudioVolume
        XCTAssertEqual(initialLocalVolume, 0.45)
        XCTAssertEqual(initialRemoteVolume, 1)

        try await components.manager.setLocalAudioVolume(0.6)
        try await components.manager.setRemoteAudioVolume(0.35)

        let localVolume = await components.manager.localAudioVolume
        let remoteVolume = await components.manager.remoteAudioVolume
        XCTAssertEqual(localVolume, 0.6)
        XCTAssertEqual(remoteVolume, 0.35)

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

    func testUnsupportedInitialFrameInterpolationDoesNotReportFatalError()
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
        XCTAssertTrue(receivedErrors.isEmpty)
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
                        frameRate: videoFormat.fps,
                        minimumBitrate: 956,
                        maximumBitrate: 1911
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

    func testCloseDisconnectsAndReleasesLocalMediaAndRTC() async throws {
        let components = makeComponents()
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
        _ = try await components.manager.connect(localStream: localStream)

        await components.manager.close()

        let state = await components.manager.currentState
        let stillOwnsLocalStream = await components.mediaController.owns(
            localStream
        )
        XCTAssertEqual(state.connectionState, .disconnected)
        XCTAssertFalse(stillOwnsLocalStream)
        XCTAssertEqual(
            components.sessionService.calls.filter {
                $0 == .closeSession("session-id")
            }.count,
            1
        )
        XCTAssertEqual(
            components.rtcManager.calls.filter { $0 == .destroy }.count,
            1
        )
    }

    func testDisconnectCancelsOneClickGenerationDuringPreparation() async throws {
        try await assertDisconnectCancelsGenerationDuringPreparation(connectFirst: false)
    }

    func testDisconnectCancelsConnectedGenerationDuringPreparation() async throws {
        try await assertDisconnectCancelsGenerationDuringPreparation(connectFirst: true)
    }

    func testRepeatedCloseReusesSingleReleaseOperation() async throws {
        let components = makeComponents()
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
        _ = try await components.manager.connect(localStream: localStream)

        async let firstClose: Void = components.manager.close()
        async let secondClose: Void = components.manager.close()
        _ = await (firstClose, secondClose)

        XCTAssertEqual(
            components.sessionService.calls.filter {
                $0 == .closeSession("session-id")
            }.count,
            1
        )
        XCTAssertEqual(
            components.rtcManager.calls.filter { $0 == .destroy }.count,
            1
        )
    }

    func testCloseCancelsMediaWaitingForAnotherManagersEngineLease() async throws {
        let lifecycle = RtcEngineLifecycleRecorder()
        let engineManager = RtcEngineManager(
            appID: "test-app-id",
            makeEngine: lifecycle.create,
            destroyEngine: lifecycle.destroy
        )
        let firstLease = try await engineManager.acquire()
        let waitingRTC = RtcManager(engineManager: engineManager)
        let initializationStarted = expectation(description: "Media initialization started")
        let rtcStub = RtcManagingStub(
            initializationHandler: {
                initializationStarted.fulfill()
                try await waitingRTC.initialize()
            },
            destroyHandler: { await waitingRTC.destroy() }
        )
        let components = makeComponents(rtcManager: rtcStub)
        let creation = Task {
            try await components.manager.createLocalCameraStream(
                videoFormat: videoFormat,
                position: .front
            )
        }
        await fulfillment(of: [initializationStarted], timeout: 2)

        let closed = expectation(description: "Close finishes while the first lease is held")
        let closing = Task {
            await components.manager.close()
            closed.fulfill()
        }
        await fulfillment(of: [closed], timeout: 1)
        XCTAssertEqual(lifecycle.createdAppIDs.count, 1)
        XCTAssertEqual(lifecycle.destroyCount, 0)

        // 失败时也释放占用者，让旧实现中的排队任务退出，避免挂住测试进程。
        await engineManager.release(firstLease)
        await closing.value
        do {
            _ = try await creation.value
            XCTFail("Expected local media creation to be cancelled")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
        }
        let state = await components.manager.currentState
        let track = await components.mediaController.currentTrack
        XCTAssertEqual(state.connectionState, .disconnected)
        XCTAssertNil(track)
        XCTAssertFalse(rtcStub.calls.contains(.switchCamera(.front)))

        let nextLease = try await engineManager.acquire()
        await engineManager.release(nextLease)
        XCTAssertEqual(lifecycle.createdAppIDs.count, 2)
        XCTAssertEqual(lifecycle.destroyCount, 2)
    }

    func testConnectedIdleCameraSwitchKeepsConnection() async throws {
        let components = makeComponents()
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
        _ = try await components.manager.connect(localStream: localStream)

        let switchedStream = try await components.manager.switchCamera()

        XCTAssertEqual(switchedStream.videoTrack?.position, .back)
        XCTAssertEqual(
            components.rtcManager.calls.filter {
                if case .joinRoom = $0 { return true }
                return false
            }.count,
            1
        )
        XCTAssertFalse(components.rtcManager.calls.contains(.leaveRoom))
        XCTAssertTrue(decodedEvents(components.rtcManager).isEmpty)

        await components.manager.disconnect()
        try await components.manager.stopLocalCameraStream()
    }

    func testCameraSwitchIsRejectedWhileGenerationIsStarting() async throws {
        let components = makeComponents()
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

        do {
            _ = try await components.manager.switchCamera()
            XCTFail("Expected camera switching to be rejected")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Camera switching is unavailable while " +
                        "realtime generation is starting"
                )
            )
        }
        XCTAssertFalse(components.rtcManager.calls.contains(
            .switchCamera(.back)
        ))

        let taskID = try XCTUnwrap(
            decodedEvents(components.rtcManager).first {
                $0["event"] as? String == "start"
            }?["uid"] as? String
        )
        components.rtcManager.emitSeiMessage(
            stream: RemoteStream(
                roomID: "room-id",
                userID: "bot-user"
            ),
            message: taskID
        )
        try components.rtcManager.emitRemoteVideoFrame()
        try await startTask.value

        await components.manager.disconnect()
        try await components.manager.stopLocalCameraStream()
    }

    func testGeneratingCameraSwitchRestartsWithoutReconnect() async throws {
        let components = makeComponents()
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front,
            useMicrophone: true
        )
        _ = try await components.manager.connect(localStream: localStream)
        let firstStartTask = Task {
            try await components.manager.startGeneration(
                context: RealtimeContext(prompt: "prompt")
            )
        }
        await waitForEvent("start", rtcManager: components.rtcManager)
        let firstTaskID = try XCTUnwrap(
            decodedEvents(components.rtcManager).first {
                $0["event"] as? String == "start"
            }?["uid"] as? String
        )
        components.rtcManager.emitSeiMessage(
            stream: RemoteStream(
                roomID: "room-id",
                userID: "bot-user"
            ),
            message: firstTaskID
        )
        try components.rtcManager.emitRemoteVideoFrame()
        try await firstStartTask.value

        let switchTask = Task {
            try await components.manager.switchCamera()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(
            decodedEvents(components.rtcManager).filter {
                $0["event"] as? String == "start"
            }.count,
            1
        )
        await waitForEventCount(
            "start",
            count: 2,
            rtcManager: components.rtcManager
        )
        let startEvents = decodedEvents(components.rtcManager).filter {
            $0["event"] as? String == "start"
        }
        let restartedTaskID = try XCTUnwrap(
            startEvents.last?["uid"] as? String
        )
        XCTAssertNotEqual(restartedTaskID, firstTaskID)
        components.rtcManager.emitSeiMessage(
            stream: RemoteStream(
                roomID: "room-id",
                userID: "bot-user"
            ),
            message: restartedTaskID
        )
        try components.rtcManager.emitRemoteVideoFrame()

        let switchedStream = try await switchTask.value
        let state = await components.manager.currentState
        XCTAssertEqual(switchedStream.videoTrack?.position, .back)
        XCTAssertEqual(state.connectionState, .generating)
        XCTAssertEqual(state.taskID, restartedTaskID)
        XCTAssertEqual(
            decodedEvents(components.rtcManager).filter {
                $0["event"] as? String == "stop"
            }.count,
            1
        )
        XCTAssertEqual(
            components.sessionService.calls.filter {
                $0 == .createSession(.x2_0)
            }.count,
            1
        )
        XCTAssertEqual(
            components.rtcManager.calls.filter {
                if case .joinRoom = $0 { return true }
                return false
            }.count,
            1
        )
        XCTAssertFalse(components.rtcManager.calls.contains(.leaveRoom))

        XCTAssertEqual(
            components.rtcManager.calls.filter { $0 == .startAudioCapture }.count,
            1
        )
        XCTAssertFalse(components.rtcManager.calls.contains(.stopAudioCapture))

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

        await components.manager.disconnect()
        let stoppedState = await components.manager.currentState
        XCTAssertEqual(stoppedState.connectionState, .disconnected)
        XCTAssertNil(stoppedState.taskID)

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

        await components.manager.disconnect()
        XCTAssertTrue(components.videoSource.calls.contains(
            .setLocalAudioPreviewMuted(false)
        ))
        XCTAssertTrue(components.rtcManager.calls.contains(
            .subscribeRemoteAudio(
                userID: "bot-user",
                subscribe: false
            )
        ))
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

    func testCameraMicrophoneFollowsConnectionLifecycle() async throws {
        let components = makeComponents()
        let manager: any XmaxRealtimeManaging = components.manager
        let stream = try await manager.createLocalCameraStream(useMicrophone: true)
        let hasAudio = await components.mediaController.hasAudio
        XCTAssertTrue(hasAudio)
        XCTAssertFalse(components.rtcManager.calls.contains(.startAudioCapture))
        XCTAssertTrue(components.sessionService.calls.isEmpty)

        _ = try await manager.connect(localStream: stream)
        let calls = components.rtcManager.calls
        let captureIndex = try XCTUnwrap(calls.firstIndex(of: .startAudioCapture))
        let publishIndex = try XCTUnwrap(calls.firstIndex(of: .publishLocalAudio))
        XCTAssertLessThan(captureIndex, publishIndex)

        await manager.disconnect()
        let ownsPreview = await components.mediaController.owns(stream)
        XCTAssertTrue(ownsPreview)
        XCTAssertFalse(components.rtcManager.calls.contains(.stopVideoCapture))
        XCTAssertFalse(components.rtcManager.calls.contains(.destroy))

        _ = try await manager.connect(localStream: stream)
        await manager.close()
        XCTAssertEqual(
            components.rtcManager.calls.filter {
                $0 == .startAudioCapture || $0 == .stopAudioCapture
            },
            [.startAudioCapture, .stopAudioCapture, .startAudioCapture, .stopAudioCapture]
        )
        XCTAssertEqual(components.rtcManager.calls.last, .destroy)
    }

    func testCameraWithoutMicrophoneDoesNotCaptureOrPublishAudio() async throws {
        let permissions = PermissionManagingStub()
        let components = makeComponents(permissionManager: permissions)
        let manager: any XmaxRealtimeManaging = components.manager
        let stream = try await manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
        _ = try await manager.connect(localStream: stream)
        await manager.close()

        XCTAssertEqual(permissions.microphoneRequestCount, 0)
        XCTAssertFalse(components.rtcManager.calls.contains(.startAudioCapture))
        XCTAssertFalse(components.rtcManager.calls.contains(.stopAudioCapture))
        XCTAssertFalse(components.rtcManager.calls.contains(.publishLocalAudio))
    }

    func testCameraMicrophonePermissionFailureReleasesRTC() async {
        let expectedError = XmaxError(
            code: .microphonePermissionDenied,
            message: "Microphone access denied"
        )
        let components = makeComponents(
            permissionManager: PermissionManagingStub(microphoneError: expectedError)
        )
        do {
            _ = try await components.manager.createLocalCameraStream(useMicrophone: true)
            XCTFail("Expected microphone permission to fail")
        } catch {
            XCTAssertEqual(error as? XmaxError, expectedError)
        }
        let track = await components.mediaController.currentTrack
        XCTAssertNil(track)
        XCTAssertFalse(components.rtcManager.calls.contains(.startAudioCapture))
        XCTAssertEqual(components.rtcManager.calls.last, .destroy)
        XCTAssertTrue(components.sessionService.calls.isEmpty)
    }

    func testCameraMicrophoneStartFailureStopsCaptureBeforeCreatingSession() async throws {
        let expectedError = XmaxError(code: .rtcError, message: "Microphone start failed")
        let components = makeComponents(
            rtcManager: RtcManagingStub(startAudioCaptureError: expectedError)
        )
        let stream = try await components.manager.createLocalCameraStream(useMicrophone: true)
        do {
            _ = try await components.manager.connect(localStream: stream)
            XCTFail("Expected microphone start to fail")
        } catch {
            XCTAssertEqual(error as? XmaxError, expectedError)
        }
        XCTAssertTrue(components.rtcManager.calls.contains(.stopAudioCapture))
        XCTAssertFalse(components.rtcManager.calls.contains(.publishLocalAudio))
        XCTAssertFalse(components.sessionService.calls.contains(.createSession(.x2_0)))
        let ownsPreview = await components.mediaController.owns(stream)
        XCTAssertTrue(ownsPreview)
        await components.manager.close()
    }

    func testCameraConnectionFailureStopsMicrophoneAndPreservesPreview() async throws {
        let expectedError = XmaxError(code: .sessionError, message: "Session creation failed")
        let components = makeComponents(sessionCreateError: expectedError)
        let stream = try await components.manager.createLocalCameraStream(useMicrophone: true)
        do {
            _ = try await components.manager.connect(localStream: stream)
            XCTFail("Expected session creation to fail")
        } catch {
            XCTAssertEqual(error as? XmaxError, expectedError)
        }
        XCTAssertEqual(
            components.rtcManager.calls.filter {
                $0 == .startAudioCapture || $0 == .stopAudioCapture
            },
            [.startAudioCapture, .stopAudioCapture]
        )
        let ownsPreview = await components.mediaController.owns(stream)
        XCTAssertTrue(ownsPreview)
        await components.manager.close()
    }

    func testCancellingCameraConnectionStopsMicrophone() async throws {
        for closesManager in [false, true] {
            let joining = expectation(description: "RTC join started")
            let rtcManager = RtcManagingStub(joinRoomHandler: { _ in
                joining.fulfill()
                try await Task.sleep(nanoseconds: 30000000000)
            })
            let components = makeComponents(rtcManager: rtcManager)
            let stream = try await components.manager.createLocalCameraStream(useMicrophone: true)
            let connecting = Task {
                try await components.manager.connect(localStream: stream)
            }
            await fulfillment(of: [joining], timeout: 2)
            if closesManager {
                await components.manager.close()
            } else {
                await components.manager.disconnect()
            }
            do {
                _ = try await connecting.value
                XCTFail("Expected connection cancellation")
            } catch {
                XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
            }
            XCTAssertEqual(
                rtcManager.calls.filter { $0 == .startAudioCapture || $0 == .stopAudioCapture },
                [.startAudioCapture, .stopAudioCapture]
            )
            let ownsPreview = await components.mediaController.owns(stream)
            XCTAssertEqual(ownsPreview, !closesManager)
            await components.manager.close()
        }
    }

    func testMicrophoneStopFailureDoesNotPreventCloseFromReleasingRTC() async throws {
        let components = makeComponents(
            rtcManager: RtcManagingStub(stopAudioCaptureError: XmaxError(
                code: .rtcError, message: "Microphone stop failed"
            ))
        )
        let stream = try await components.manager.createLocalCameraStream(useMicrophone: true)
        _ = try await components.manager.connect(localStream: stream)
        await components.manager.close()

        XCTAssertTrue(components.rtcManager.calls.contains(.stopAudioCapture))
        XCTAssertTrue(components.rtcManager.calls.contains(.leaveRoom))
        XCTAssertEqual(components.rtcManager.calls.last, .destroy)
        let track = await components.mediaController.currentTrack
        XCTAssertNil(track)
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
                    frameRate: imageFormat.fps,
                    minimumBitrate: 1488,
                    maximumBitrate: 2977
                )
            ]
        )

        try await components.manager.stopLocalVideoStream()
    }

    func testFileVideoEncoderFailureReleasesLocalStream() async throws {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "Failed to configure video encoding"
        )
        let components = makeComponents(
            rtcManager: RtcManagingStub(encodingError: expectedError)
        )

        do {
            _ = try await components.manager.createLocalVideoStream(
                fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
                videoFormat: nil
            )
            XCTFail("Expected video encoding configuration to fail")
        } catch {
            XCTAssertEqual(error as? XmaxError, expectedError)
        }

        let currentTrack = await components.mediaController.currentTrack
        XCTAssertNil(currentTrack)
        XCTAssertTrue(components.videoSource.calls.contains(.start))
        XCTAssertTrue(components.videoSource.calls.contains(.stop))
        XCTAssertEqual(components.rtcManager.calls.last, .destroy)
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
            message: "session closed",
            severity: .fatal
        )

        await components.sessionService.failHeartbeat(
            sessionID: "session-id",
            error: XmaxError(
                code: .sessionError,
                message: "session closed"
            )
        )

        let state = await components.manager.currentState
        XCTAssertEqual(state.connectionState, .error)
        XCTAssertEqual(receivedErrors, [expectedError])
        XCTAssertFalse(components.rtcManager.calls.contains(.destroy))
        try await components.manager.stopLocalCameraStream()
    }

    func testDisconnectGenerationFailureDoesNotReportFatalError() async throws {
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
        let signalingError = XmaxError(
            code: .rtcError,
            message: "sendRoomMessage failed: -1"
        )
        components.rtcManager.setSendRoomMessageError(signalingError)

        await components.manager.disconnect()

        XCTAssertTrue(receivedErrors.isEmpty)
        try await components.manager.stopLocalCameraStream()
    }

    func testDisconnectSessionCleanupFailureDoesNotReportError() async throws {
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

        XCTAssertTrue(receivedErrors.isEmpty)
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
        XCTAssertNil(receivedError)
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
        let connectionManager: XmaxRealtimeConnectionManager
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
        rtcManager: RtcManagingStub = RtcManagingStub(),
        permissionManager: PermissionManagingStub = PermissionManagingStub(),
        model: RealtimeModel = .x2_0,
        sessionCreateError: (any Error)? = nil,
        sessionCloseError: (any Error)? = nil,
        frameInterpolationEnabled: Bool = false,
        frameInterpolationSupported: Bool = false
    ) -> Components {
        let errorHandler = RealtimeErrorHandler()
        let mediaService = MediaServicingStub(
            resolvedSize: CGSize(width: 1_024, height: 768),
            frameInterpolationSupported: frameInterpolationSupported
        )
        let renderController = RenderController(
            rtcManager: rtcManager,
            frameInterpolationEnabled: frameInterpolationEnabled,
            frameInterpolationSupportChecker: { mediaService.supportsFrameInterpolation(for: $0) },
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
            permissionManager: permissionManager,
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
            interactionListener: { taskID, points in
                try await streamController.sendTracks(taskID: taskID, points: points)
            },
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
                    model: model,
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
            connectionManager: connectionManager,
            mediaController: mediaController,
            rtcManager: rtcManager,
            sessionService: sessionService,
            imageSource: imageSource,
            videoSource: videoSource
        )
    }

    func assertDisconnectCancelsGenerationDuringPreparation(
        connectFirst: Bool
    ) async throws {
        let components = makeComponents()
        let localStream = try await components.manager.createLocalCameraStream(
            videoFormat: videoFormat,
            position: .front
        )
        if connectFirst {
            _ = try await components.manager.connect(localStream: localStream)
        }

        // 卡住连接状态查询，确保断开发生在生成准备阶段，而非进房之后。
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let queryBlocked = expectation(description: "Connection queries blocked")
        let holding = Task.detached {
            await components.connectionManager.holdQueries(
                gate: gate,
                entered: { queryBlocked.fulfill() }
            )
        }
        await fulfillment(of: [queryBlocked], timeout: 2)

        let startEntered = expectation(description: "Generation call entered")
        let starting = Task {
            try await components.manager.startGenerationDuringPreparationTest(
                localStream: connectFirst ? nil : localStream,
                entered: { startEntered.fulfill() }
            )
        }
        await fulfillment(of: [startEntered], timeout: 2)

        let disconnecting = expectation(description: "Pending generation cancelled")
        await components.manager.setStateListener { state in
            if state.connectionState == .disconnecting {
                disconnecting.fulfill()
            }
        }
        let closing = Task { await components.manager.disconnect() }
        await fulfillment(of: [disconnecting], timeout: 2)
        gate.signal()
        let gateReleased = await holding.value
        XCTAssertTrue(gateReleased)
        await closing.value

        do {
            try await starting.value
            XCTFail("Expected generation preparation to be cancelled")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
        }
        let state = await components.manager.currentState
        let ownsLocalStream = await components.mediaController.owns(localStream)
        XCTAssertEqual(state.connectionState, .disconnected)
        XCTAssertTrue(ownsLocalStream)
        XCTAssertFalse(decodedEvents(components.rtcManager).contains {
            $0["event"] as? String == "start"
        })
        if !connectFirst {
            XCTAssertFalse(components.sessionService.calls.contains {
                if case .createSession = $0 { return true }
                return false
            })
        }
        await components.manager.setStateListener(nil)
        await components.manager.close()
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
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for room event: \(event)")
    }

    func waitForEventCount(
        _ event: String,
        count: Int,
        rtcManager: RtcManagingStub
    ) async {
        for _ in 0..<1_000 {
            let matchingEvents = decodedEvents(rtcManager).filter {
                $0["event"] as? String == event
            }
            if matchingEvents.count >= count {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail(
            "Timed out waiting for room event: \(event), count: \(count)"
        )
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
