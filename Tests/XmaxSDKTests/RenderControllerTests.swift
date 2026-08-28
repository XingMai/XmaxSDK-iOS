import UIKit
import XCTest
@testable import XmaxSDK

@MainActor
final class RenderControllerTests: XCTestCase {
    func testSettingStreamBeforeAttachStartsRemoteFrameDelivery() throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")

        try controller.setRemoteStream(stream)

        XCTAssertEqual(
            rtcManager.calls,
            [.setRemoteVideoFrameListener(stream, enabled: true)]
        )
    }

    func testSettingStreamAfterAttachStartsRemoteFrameDelivery() throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        defer { try? controller.resetRemoteTrack(registration.track) }
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        let videoView = XmaxVideoView()

        try registration.binding.attach(
            to: videoView,
            contentMode: .fit
        )
        try controller.setRemoteStream(stream)

        XCTAssertEqual(
            rtcManager.calls,
            [.setRemoteVideoFrameListener(stream, enabled: true)]
        )
    }

    func testReplacingStreamStopsPreviousAndStartsCurrentFrames() throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        defer { try? controller.resetRemoteTrack(registration.track) }
        let firstStream = RemoteStream(
            roomID: "room-id",
            userID: "first-user"
        )
        let secondStream = RemoteStream(
            roomID: "room-id",
            userID: "second-user"
        )
        let videoView = XmaxVideoView()
        try registration.binding.attach(
            to: videoView,
            contentMode: .fill
        )
        try controller.setRemoteStream(firstStream)

        try controller.setRemoteStream(secondStream)

        XCTAssertEqual(
            rtcManager.calls,
            [
                .setRemoteVideoFrameListener(firstStream, enabled: true),
                .setRemoteVideoFrameListener(firstStream, enabled: false),
                .setRemoteVideoFrameListener(secondStream, enabled: true)
            ]
        )
    }

    func testDetachPreservesStreamForLaterAttachment() throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        defer { try? controller.resetRemoteTrack(registration.track) }
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        let firstVideoView = XmaxVideoView()
        let secondVideoView = XmaxVideoView()
        try controller.setRemoteStream(stream)
        try registration.binding.attach(
            to: firstVideoView,
            contentMode: .fit
        )

        try registration.binding.detach()
        try registration.binding.attach(
            to: secondVideoView,
            contentMode: .fill
        )

        XCTAssertEqual(
            rtcManager.calls,
            [.setRemoteVideoFrameListener(stream, enabled: true)]
        )
    }

    func testRemoteFrameReadyWaitsForProcessedFrame() async throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(
            rtcManager: rtcManager,
            remoteFrameReadyTimeoutNanoseconds: 1_000_000_000
        )
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        try controller.setRemoteStream(stream)

        let readiness = Task {
            try await controller.waitUntilRemoteFrameReady()
        }
        try rtcManager.emitRemoteVideoFrame()

        try await readiness.value
    }

    func testRemoteFrameReadyTimesOutWithoutFrame() async throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(
            rtcManager: rtcManager,
            remoteFrameReadyTimeoutNanoseconds: 0
        )
        try controller.setRemoteStream(
            RemoteStream(roomID: "room-id", userID: "bot-user")
        )

        do {
            try await controller.waitUntilRemoteFrameReady()
            XCTFail("Expected remote first frame wait to time out")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .timeout)
        }
    }

    func testCancelledRemoteFrameWaitDoesNotReportMissingStream() async {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let readiness = Task {
            try await controller.waitUntilRemoteFrameReady()
        }
        readiness.cancel()

        do {
            try await readiness.value
            XCTFail("Expected remote frame wait to be cancelled")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
        }
    }

    func testUpdatingContentModeDoesNotRegisterRemoteFramesAgain() throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        defer { try? controller.resetRemoteTrack(registration.track) }
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        let videoView = XmaxVideoView()
        try controller.setRemoteStream(stream)
        try registration.binding.attach(
            to: videoView,
            contentMode: .fit
        )

        try registration.binding.attach(
            to: videoView,
            contentMode: .fill
        )

        XCTAssertEqual(
            rtcManager.calls,
            [.setRemoteVideoFrameListener(stream, enabled: true)]
        )
    }

    func testResetStopsFramesAndClearsStreamAndView() throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        let firstVideoView = XmaxVideoView()
        let secondVideoView = XmaxVideoView()
        try controller.setRemoteStream(stream)
        try registration.binding.attach(
            to: firstVideoView,
            contentMode: .fit
        )

        try controller.resetRemoteTrack(registration.track)
        try registration.binding.attach(
            to: secondVideoView,
            contentMode: .fill
        )

        XCTAssertEqual(
            rtcManager.calls,
            [
                .setRemoteVideoFrameListener(stream, enabled: true),
                .setRemoteVideoFrameListener(stream, enabled: false)
            ]
        )
    }

    func testViewLifecycleFrameBindingFailureReportsRTCError() throws {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "Failed to bind the remote RTC frame sink"
        )
        let rtcManager = RtcManagingStub(
            setRemoteVideoFrameListenerError: expectedError
        )
        let recorder = RenderErrorRecorder()
        let controller = RenderController(
            rtcManager: rtcManager,
            errorListener: { recorder.record($0) }
        )
        let registration = try registerRemoteTrack(with: controller)
        defer { try? controller.resetRemoteTrack(registration.track) }
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        let videoView = XmaxVideoView()
        try controller.setRemoteStream(stream)

        XCTAssertThrowsError(
            try registration.binding.attach(
                to: videoView,
                contentMode: .fill
            )
        )
        XCTAssertEqual(recorder.recordedErrors, [expectedError])
    }

    func testGenerationFrameBindingFailureIsOnlyThrown() throws {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "Failed to bind the remote RTC frame sink"
        )
        let rtcManager = RtcManagingStub(
            setRemoteVideoFrameListenerError: expectedError
        )
        let recorder = RenderErrorRecorder()
        let controller = RenderController(
            rtcManager: rtcManager,
            errorListener: { recorder.record($0) }
        )
        let registration = try registerRemoteTrack(with: controller)
        defer { try? controller.resetRemoteTrack(registration.track) }
        let videoView = XmaxVideoView()
        try registration.binding.attach(
            to: videoView,
            contentMode: .fill
        )
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")

        XCTAssertThrowsError(try controller.setRemoteStream(stream))
        XCTAssertTrue(recorder.recordedErrors.isEmpty)
    }
}

private final class RenderErrorRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [XmaxError] = []

    var recordedErrors: [XmaxError] {
        lock.withLock { errors }
    }

    func record(_ error: XmaxError) {
        lock.withLock {
            errors.append(error)
        }
    }
}

private extension RenderControllerTests {
    func registerRemoteTrack(
        with controller: RenderController
    ) throws -> (
        track: RealtimeVideoTrack,
        binding: VideoRenderBinding
    ) {
        let track = RealtimeVideoTrack(
            id: "video-remote",
            videoFormat: RealtimeVideoFormat(
                width: 720,
                height: 1_280,
                fps: 24
            )
        )
        controller.registerRemoteTrack(
            track,
            interactionListener: { _ in }
        )
        return (
            track,
            try XCTUnwrap(VideoRenderRegistry.binding(for: track))
        )
    }
}
