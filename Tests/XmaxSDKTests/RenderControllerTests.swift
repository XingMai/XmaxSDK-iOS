import UIKit
import XCTest
@testable import XmaxSDK

@MainActor
final class RenderControllerTests: XCTestCase {
    func testSettingStreamAfterAttachBindsRemoteVideo() async throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        let view = UIView()

        try registration.binding.attach(
            to: view,
            contentMode: .fit
        )
        controller.setRemoteStream(stream)
        await controller.waitForPendingRenderUpdates()

        XCTAssertEqual(
            rtcManager.calls,
            [.bindRemoteVideo(stream, .fit)]
        )
        await controller.resetRemoteTrack(registration.track)
    }

    func testReplacingStreamUnbindsPreviousAndBindsCurrent() async throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        let firstStream = RemoteStream(
            roomID: "room-id",
            userID: "first-user"
        )
        let secondStream = RemoteStream(
            roomID: "room-id",
            userID: "second-user"
        )
        let view = UIView()
        try registration.binding.attach(
            to: view,
            contentMode: .fill
        )
        controller.setRemoteStream(firstStream)

        controller.setRemoteStream(secondStream)
        await controller.waitForPendingRenderUpdates()

        XCTAssertEqual(
            rtcManager.calls,
            [
                .bindRemoteVideo(firstStream, .fill),
                .unbindRemoteVideo(firstStream),
                .bindRemoteVideo(secondStream, .fill)
            ]
        )
        await controller.resetRemoteTrack(registration.track)
    }

    func testDetachPreservesStreamForLaterAttachment() async throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        let firstView = UIView()
        let secondView = UIView()
        controller.setRemoteStream(stream)
        try registration.binding.attach(
            to: firstView,
            contentMode: .fit
        )

        try registration.binding.detach()
        try registration.binding.attach(
            to: secondView,
            contentMode: .fill
        )
        await controller.waitForPendingRenderUpdates()

        XCTAssertEqual(
            rtcManager.calls,
            [
                .bindRemoteVideo(stream, .fit),
                .unbindRemoteVideo(stream),
                .bindRemoteVideo(stream, .fill)
            ]
        )
        await controller.resetRemoteTrack(registration.track)
    }

    func testResetUnbindsAndClearsStreamAndView() async throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        let firstView = UIView()
        let secondView = UIView()
        controller.setRemoteStream(stream)
        try registration.binding.attach(
            to: firstView,
            contentMode: .fit
        )

        await controller.resetRemoteTrack(registration.track)
        try registration.binding.attach(
            to: secondView,
            contentMode: .fill
        )

        XCTAssertEqual(
            rtcManager.calls,
            [
                .bindRemoteVideo(stream, .fit),
                .unbindRemoteVideo(stream)
            ]
        )
    }

    func testViewLifecycleRemoteCanvasBindingFailureReportsRTCError() async throws {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "Failed to bind the remote RTC canvas"
        )
        let rtcManager = RtcManagingStub(
            bindRemoteVideoError: expectedError
        )
        let recorder = RenderErrorRecorder()
        let controller = RenderController(
            rtcManager: rtcManager,
            errorListener: { recorder.record($0) }
        )
        let registration = try registerRemoteTrack(with: controller)
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        let view = UIView()
        controller.setRemoteStream(stream)

        XCTAssertNoThrow(
            try registration.binding.attach(
                to: view,
                contentMode: .fill
            )
        )
        await controller.waitForPendingRenderUpdates()
        XCTAssertEqual(recorder.recordedErrors, [expectedError])
        await controller.resetRemoteTrack(registration.track)
    }

    func testGenerationRemoteCanvasBindingFailureReportsRTCError() async throws {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "Failed to bind the remote RTC canvas"
        )
        let rtcManager = RtcManagingStub(
            bindRemoteVideoError: expectedError
        )
        let recorder = RenderErrorRecorder()
        let controller = RenderController(
            rtcManager: rtcManager,
            errorListener: { recorder.record($0) }
        )
        let registration = try registerRemoteTrack(with: controller)
        let view = UIView()
        try registration.binding.attach(
            to: view,
            contentMode: .fill
        )
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")

        controller.setRemoteStream(stream)
        await controller.waitForPendingRenderUpdates()

        XCTAssertEqual(recorder.recordedErrors, [expectedError])
        await controller.resetRemoteTrack(registration.track)
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
