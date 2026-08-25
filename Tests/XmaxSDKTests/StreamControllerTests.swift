import XCTest
@testable import XmaxSDK

final class StreamControllerTests: XCTestCase {
    func testPublishLocalCameraStreamRequiresConfiguredRoom() {
        let rtcProvider = RtcProvidingStub()
        let controller = StreamController(rtcProvider: rtcProvider)

        XCTAssertThrowsError(
            try controller.publishLocalStream(includeAudio: false)
        ) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Configure an RTC room before publishing " +
                        "the local stream"
                )
            )
        }
        XCTAssertTrue(rtcProvider.calls.isEmpty)
    }

    func testPublishLocalCameraStreamPublishesVideoOnlyOnce() throws {
        let rtcProvider = RtcProvidingStub()
        let controller = StreamController(rtcProvider: rtcProvider)
        try controller.configureRoom(
            roomID: " room-id ",
            botName: nil
        )

        try controller.publishLocalStream(includeAudio: false)
        try controller.publishLocalStream(includeAudio: false)

        XCTAssertEqual(rtcProvider.calls, [.publishLocalVideo])
    }

    func testAudioPublicationFailureRollsBackNewVideoPublication() throws {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "Failed to publish local audio"
        )
        let rtcProvider = RtcProvidingStub(
            publishLocalAudioError: expectedError
        )
        let controller = StreamController(rtcProvider: rtcProvider)
        try controller.configureRoom(roomID: "room-id", botName: nil)

        XCTAssertThrowsError(
            try controller.publishLocalStream(includeAudio: true)
        ) { error in
            XCTAssertEqual(error as? XmaxError, expectedError)
        }
        XCTAssertEqual(
            rtcProvider.calls,
            [
                .publishLocalVideo,
                .publishLocalAudio,
                .unpublishLocalVideo
            ]
        )
    }

    func testSetLocalAudioEnabledUpdatesOnlyChangedState() throws {
        let rtcProvider = RtcProvidingStub()
        let controller = StreamController(rtcProvider: rtcProvider)
        try controller.configureRoom(roomID: "room-id", botName: nil)
        try controller.publishLocalStream(includeAudio: false)

        try controller.setLocalAudioEnabled(true)
        try controller.setLocalAudioEnabled(true)
        try controller.setLocalAudioEnabled(false)
        try controller.setLocalAudioEnabled(false)

        XCTAssertEqual(
            rtcProvider.calls,
            [
                .publishLocalVideo,
                .publishLocalAudio,
                .unpublishLocalAudio
            ]
        )
    }

    @MainActor
    func testRemoteVideoEventsSubscribeOnlyConfiguredBot() throws {
        let rtcProvider = RtcProvidingStub()
        let controller = StreamController(rtcProvider: rtcProvider)
        try controller.configureRoom(
            roomID: "room-id",
            botName: " bot-user "
        )

        rtcProvider.emitRemoteVideoPublished(
            userID: "another-user",
            published: true
        )
        rtcProvider.emitRemoteVideoPublished(
            userID: "bot-user",
            published: true
        )
        rtcProvider.emitRemoteVideoPublished(
            userID: "bot-user",
            published: true
        )
        rtcProvider.emitRemoteVideoPublished(
            userID: "bot-user",
            published: false
        )
        rtcProvider.emitRemoteVideoPublished(
            userID: "bot-user",
            published: true
        )

        XCTAssertEqual(
            rtcProvider.calls,
            [
                .subscribeRemoteVideo(
                    userID: "bot-user",
                    subscribe: true
                ),
                .subscribeRemoteVideo(
                    userID: "bot-user",
                    subscribe: true
                )
            ]
        )
    }

    @MainActor
    func testResetRoomClearsSubscriptionsAndLocalPublications() throws {
        let rtcProvider = RtcProvidingStub()
        let controller = StreamController(rtcProvider: rtcProvider)
        try controller.configureRoom(
            roomID: "room-id",
            botName: "bot-user"
        )
        try controller.publishLocalStream(includeAudio: true)
        rtcProvider.emitRemoteVideoPublished(
            userID: "bot-user",
            published: true
        )

        controller.resetRoom()
        controller.resetRoom()

        XCTAssertEqual(
            rtcProvider.calls,
            [
                .publishLocalVideo,
                .publishLocalAudio,
                .subscribeRemoteVideo(
                    userID: "bot-user",
                    subscribe: true
                ),
                .subscribeRemoteVideo(
                    userID: "bot-user",
                    subscribe: false
                ),
                .unpublishLocalAudio,
                .unpublishLocalVideo
            ]
        )
        XCTAssertThrowsError(
            try controller.publishLocalStream(includeAudio: false)
        ) { error in
            XCTAssertEqual(
                (error as? XmaxError)?.code,
                .invalidConfiguration
            )
        }
    }

    func testConfigureRoomRejectsReplacementWhilePublishing() throws {
        let controller = StreamController(rtcProvider: RtcProvidingStub())
        try controller.configureRoom(roomID: "first-room", botName: nil)
        try controller.publishLocalStream(includeAudio: false)

        XCTAssertThrowsError(
            try controller.configureRoom(
                roomID: "second-room",
                botName: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Reset the current RTC room before " +
                        "configuring another one"
                )
            )
        }
    }

    @MainActor
    func testGenerationConfirmationMatchesTaskRoomAndBot() async throws {
        let rtcProvider = RtcProvidingStub()
        var receivedStreams: [RemoteStream?] = []
        let controller = StreamController(
            rtcProvider: rtcProvider,
            remoteStreamListener: { stream in
                receivedStreams.append(stream)
            },
            generationTiming: StreamGenerationTiming(
                timeoutNanoseconds: 1_000_000_000,
                confirmationDelayNanoseconds: 0
            )
        )
        try controller.configureRoom(
            roomID: "room-id",
            botName: "bot-user"
        )
        let confirmation = try controller.beginGeneration(taskID: "task-id")
        let matchingStream = RemoteStream(
            roomID: "room-id",
            userID: "bot-user"
        )

        rtcProvider.emitSeiMessage(
            stream: RemoteStream(
                roomID: "another-room",
                userID: "bot-user"
            ),
            message: "task-id"
        )
        rtcProvider.emitSeiMessage(
            stream: matchingStream,
            message: "another-task"
        )
        rtcProvider.emitSeiMessage(
            stream: matchingStream,
            message: " task-id "
        )
        try await confirmation.value

        XCTAssertEqual(receivedStreams.count, 1)
        XCTAssertEqual(receivedStreams[0], matchingStream)
        _ = controller.stopGeneration(taskID: "task-id")
    }

    @MainActor
    func testGenerationConfirmationTimesOut() async throws {
        let controller = StreamController(
            rtcProvider: RtcProvidingStub(),
            generationTiming: StreamGenerationTiming(
                timeoutNanoseconds: 0,
                confirmationDelayNanoseconds: 0
            )
        )
        try controller.configureRoom(roomID: "room-id", botName: nil)
        let confirmation = try controller.beginGeneration(taskID: "task-id")

        do {
            try await confirmation.value
            XCTFail("Expected generation confirmation to time out")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .timeout,
                    message: "Realtime generation start timed out"
                )
            )
        }
        _ = controller.stopGeneration(taskID: "task-id")
    }

    @MainActor
    func testStoppingGenerationCancelsWaitAndClearsRemoteStream() async throws {
        var receivedStreams: [RemoteStream?] = []
        let controller = StreamController(
            rtcProvider: RtcProvidingStub(),
            remoteStreamListener: { stream in
                receivedStreams.append(stream)
            }
        )
        try controller.configureRoom(roomID: "room-id", botName: nil)
        let confirmation = try controller.beginGeneration(taskID: "task-id")

        let stoppedTaskID = controller.stopGeneration(taskID: "task-id")

        XCTAssertEqual(stoppedTaskID, "task-id")
        XCTAssertNil(receivedStreams.last ?? nil)
        do {
            try await confirmation.value
            XCTFail("Expected generation confirmation to be cancelled")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
        }
    }

    @MainActor
    func testExternalVideoFrameCarriesCurrentTaskIDAsSei() async throws {
        let rtcProvider = RtcProvidingStub()
        let controller = StreamController(rtcProvider: rtcProvider)
        try controller.configureRoom(roomID: "room-id", botName: nil)
        let confirmation = try controller.beginGeneration(taskID: "task-id")
        let format = try VideoFormat(
            width: 2,
            height: 2,
            pixelFormat: .nv12
        )
        let frame = try BufferVideoFrame(
            format: format,
            timestampUs: 0,
            planes: [
                try VideoFramePlane(
                    data: Data(repeating: 0, count: 4),
                    stride: 2
                ),
                try VideoFramePlane(
                    data: Data(repeating: 0, count: 2),
                    stride: 2
                )
            ]
        )

        try controller.pushLocalVideoFrame(frame)

        XCTAssertEqual(
            rtcProvider.calls,
            [.pushExternalVideoFrame(seiData: Data("task-id".utf8))]
        )
        _ = controller.stopGeneration(taskID: "task-id")
        do {
            try await confirmation.value
            XCTFail("Expected stopped confirmation to be cancelled")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
        }
    }
}
