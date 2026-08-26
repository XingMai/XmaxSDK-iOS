import UIKit
import XCTest
@testable import XmaxSDK

@MainActor
final class XmaxRealtimeConnectionManagerTests: XCTestCase {
    func testConnectCreatesSessionJoinsRoomAndPublishesLocalMedia() async throws {
        let rtcManager = RtcManagingStub()
        let sessionService = RealtimeSessionServicingStub(session: session)
        let components = makeManager(
            rtcManager: rtcManager,
            sessionService: sessionService
        )
        let format = RealtimeVideoFormat(
            width: 720,
            height: 1280,
            fps: 24
        )

        let stream = try await components.manager.connect(
            model: .x2_0,
            videoFormat: format,
            includeLocalAudio: true,
            isCurrent: { true },
            onHeartbeatFailure: { _, _ in }
        )

        XCTAssertEqual(stream.id, StreamID.remote.rawValue)
        XCTAssertEqual(stream.videoTrack?.id, "bot-user")
        XCTAssertEqual(stream.videoTrack?.videoFormat, format)
        let currentSessionID = await components.manager.currentSessionID
        XCTAssertEqual(currentSessionID, "session-id")
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
                .publishLocalVideo,
                .publishLocalAudio
            ]
        )
        XCTAssertEqual(
            sessionService.calls,
            [
                .createSession(.x2_0),
                .startHeartbeat("session-id")
            ]
        )
        let track = try XCTUnwrap(stream.videoTrack)
        XCTAssertEqual(
            VideoRenderRegistry.binding(for: track)?.libraryName,
            "test"
        )
        XCTAssertNotNil(TrajectoryRegistry.binding(for: track))

        _ = await components.manager.disconnect()
    }

    func testRemoteTrackBindingRendersSelectedRtcStream() async throws {
        let rtcManager = RtcManagingStub()
        let components = makeManager(
            rtcManager: rtcManager,
            sessionService: RealtimeSessionServicingStub(session: session)
        )
        let stream = try await components.manager.connect(
            model: .x2_0,
            videoFormat: videoFormat,
            includeLocalAudio: false,
            isCurrent: { true },
            onHeartbeatFailure: { _, _ in }
        )
        let view = XmaxVideoView(
            track: stream.videoTrack,
            videoContentMode: .fit
        )
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        window.addSubview(view)
        let remoteStream = RemoteStream(
            roomID: "room-id",
            userID: "bot-user"
        )

        try components.remoteVideoController.setRemoteStream(remoteStream)

        XCTAssertEqual(
            rtcManager.calls.last,
            .bindRemoteVideo(remoteStream, .fit)
        )
        _ = await components.manager.disconnect()
        XCTAssertTrue(
            rtcManager.calls.contains(.unbindRemoteVideo(remoteStream))
        )
    }

    func testDisconnectStopsHeartbeatAndReleasesConnectionResources() async throws {
        let rtcManager = RtcManagingStub()
        let sessionService = RealtimeSessionServicingStub(session: session)
        let components = makeManager(
            rtcManager: rtcManager,
            sessionService: sessionService
        )
        let stream = try await components.manager.connect(
            model: .x2_0,
            videoFormat: videoFormat,
            includeLocalAudio: true,
            isCurrent: { true },
            onHeartbeatFailure: { _, _ in }
        )
        let track = try XCTUnwrap(stream.videoTrack)

        let disconnectedSessionID = await components.manager.disconnect()
        let currentSessionID = await components.manager.currentSessionID

        XCTAssertEqual(disconnectedSessionID, "session-id")
        XCTAssertEqual(currentSessionID, "")
        XCTAssertNil(VideoRenderRegistry.binding(for: track))
        XCTAssertNil(TrajectoryRegistry.binding(for: track))
        XCTAssertEqual(
            sessionService.calls,
            [
                .createSession(.x2_0),
                .startHeartbeat("session-id"),
                .stopHeartbeat,
                .closeSession("session-id")
            ]
        )
        XCTAssertEqual(
            Array(rtcManager.calls.suffix(3)),
            [.unpublishLocalAudio, .unpublishLocalVideo, .leaveRoom]
        )
    }

    func testConnectionFailureRollsBackRoomAndClosesSession() async {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "publish failed"
        )
        let rtcManager = RtcManagingStub(
            publishLocalVideoError: expectedError
        )
        let sessionService = RealtimeSessionServicingStub(session: session)
        let components = makeManager(
            rtcManager: rtcManager,
            sessionService: sessionService
        )

        do {
            _ = try await components.manager.connect(
                model: .x2_0,
                videoFormat: videoFormat,
                includeLocalAudio: false,
                isCurrent: { true },
                onHeartbeatFailure: { _, _ in }
            )
            XCTFail("Expected local publication to fail")
        } catch {
            XCTAssertEqual(error as? XmaxError, expectedError)
        }

        XCTAssertEqual(
            sessionService.calls,
            [
                .createSession(.x2_0),
                .stopHeartbeat,
                .closeSession("session-id")
            ]
        )
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
                .publishLocalVideo,
                .leaveRoom
            ]
        )
    }

    func testCancelledConnectionClosesLateSessionWithoutJoiningRoom() async {
        let rtcManager = RtcManagingStub()
        let sessionService = RealtimeSessionServicingStub(session: session)
        let components = makeManager(
            rtcManager: rtcManager,
            sessionService: sessionService
        )

        do {
            _ = try await components.manager.connect(
                model: .x2_0,
                videoFormat: videoFormat,
                includeLocalAudio: false,
                isCurrent: { false },
                onHeartbeatFailure: { _, _ in }
            )
            XCTFail("Expected stale connection to be cancelled")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .cancelled,
                    message: "Realtime connection was cancelled"
                )
            )
        }

        XCTAssertTrue(rtcManager.calls.isEmpty)
        XCTAssertEqual(
            sessionService.calls,
            [
                .createSession(.x2_0),
                .closeSession("session-id")
            ]
        )
    }

    func testDisconnectUsesFallbackSessionWhenActiveResourcesAreMissing() async {
        let sessionService = RealtimeSessionServicingStub(session: session)
        let components = makeManager(sessionService: sessionService)

        let sessionID = await components.manager.disconnect(
            fallbackSessionID: "fallback-session"
        )

        XCTAssertEqual(sessionID, "fallback-session")
        XCTAssertEqual(
            sessionService.calls,
            [
                .stopHeartbeat,
                .closeSession("fallback-session")
            ]
        )
    }

    func testUpdatingRemoteVideoFormatUpdatesActiveTrack() async throws {
        let components = makeManager(
            sessionService: RealtimeSessionServicingStub(session: session)
        )
        let stream = try await components.manager.connect(
            model: .x2_0,
            videoFormat: videoFormat,
            includeLocalAudio: false,
            isCurrent: { true },
            onHeartbeatFailure: { _, _ in }
        )
        let updatedFormat = RealtimeVideoFormat(
            width: 540,
            height: 960,
            fps: 15
        )

        await components.manager.updateRemoteVideoFormat(updatedFormat)

        XCTAssertEqual(stream.videoTrack?.videoFormat, updatedFormat)
        _ = await components.manager.disconnect()
    }
}

private extension XmaxRealtimeConnectionManagerTests {
    struct Components {
        let manager: XmaxRealtimeConnectionManager
        let remoteVideoController: RemoteVideoController
    }

    var session: RealtimeSession {
        RealtimeSession(
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
    }

    var videoFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 720, height: 1280, fps: 24)
    }

    func makeManager(
        rtcManager: RtcManagingStub = RtcManagingStub(),
        sessionService: RealtimeSessionServicingStub
    ) -> Components {
        let remoteVideoController = RemoteVideoController(
            rtcManager: rtcManager
        )
        let transportController = TransportController(
            rtcManager: rtcManager
        )
        return Components(
            manager: XmaxRealtimeConnectionManager(
                rtcManager: rtcManager,
                sessionService: sessionService,
                interactionController: InteractionController(),
                remoteVideoController: remoteVideoController,
                transportController: transportController
            ),
            remoteVideoController: remoteVideoController
        )
    }
}
