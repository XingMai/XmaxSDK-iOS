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
}
