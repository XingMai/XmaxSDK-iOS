import UIKit
import XCTest
@testable import XmaxSDK

@MainActor
final class RenderControllerTests: XCTestCase {
    func testSettingStreamAfterAttachBindsRemoteVideo() throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        defer { try? controller.resetRemoteTrack(registration.track) }
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")

        try registration.binding.attach(
            to: UIView(),
            contentMode: .fit
        )
        try controller.setRemoteStream(stream)

        XCTAssertEqual(
            rtcManager.calls,
            [.bindRemoteVideo(stream, .fit)]
        )
    }

    func testReplacingStreamUnbindsPreviousAndBindsCurrent() throws {
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
        try registration.binding.attach(
            to: UIView(),
            contentMode: .fill
        )
        try controller.setRemoteStream(firstStream)

        try controller.setRemoteStream(secondStream)

        XCTAssertEqual(
            rtcManager.calls,
            [
                .bindRemoteVideo(firstStream, .fill),
                .unbindRemoteVideo(firstStream),
                .bindRemoteVideo(secondStream, .fill)
            ]
        )
    }

    func testDetachPreservesStreamForLaterAttachment() throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        defer { try? controller.resetRemoteTrack(registration.track) }
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        try controller.setRemoteStream(stream)
        try registration.binding.attach(
            to: UIView(),
            contentMode: .fit
        )

        try registration.binding.detach()
        try registration.binding.attach(
            to: UIView(),
            contentMode: .fill
        )

        XCTAssertEqual(
            rtcManager.calls,
            [
                .bindRemoteVideo(stream, .fit),
                .unbindRemoteVideo(stream),
                .bindRemoteVideo(stream, .fill)
            ]
        )
    }

    func testResetUnbindsAndClearsStreamAndView() throws {
        let rtcManager = RtcManagingStub()
        let controller = RenderController(rtcManager: rtcManager)
        let registration = try registerRemoteTrack(with: controller)
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        try controller.setRemoteStream(stream)
        try registration.binding.attach(
            to: UIView(),
            contentMode: .fit
        )

        try controller.resetRemoteTrack(registration.track)
        try registration.binding.attach(
            to: UIView(),
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
