import UIKit
import XCTest
@testable import XmaxSDK

@MainActor
final class RemoteVideoControllerTests: XCTestCase {
    func testSettingStreamAfterAttachBindsRemoteVideo() throws {
        let rtcManager = RtcManagingStub()
        let controller = RemoteVideoController(rtcManager: rtcManager)
        let view = UIView()
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")

        try controller.attach(to: view, contentMode: .fit)
        try controller.setRemoteStream(stream)

        XCTAssertEqual(
            rtcManager.calls,
            [.bindRemoteVideo(stream, .fit)]
        )
    }

    func testReplacingStreamUnbindsPreviousAndBindsCurrent() throws {
        let rtcManager = RtcManagingStub()
        let controller = RemoteVideoController(rtcManager: rtcManager)
        let firstStream = RemoteStream(
            roomID: "room-id",
            userID: "first-user"
        )
        let secondStream = RemoteStream(
            roomID: "room-id",
            userID: "second-user"
        )
        let view = UIView()
        try controller.attach(to: view, contentMode: .fill)
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
        let controller = RemoteVideoController(rtcManager: rtcManager)
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        try controller.setRemoteStream(stream)
        try controller.attach(to: UIView(), contentMode: .fit)

        try controller.detach()
        try controller.attach(to: UIView(), contentMode: .fill)

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
        let controller = RemoteVideoController(rtcManager: rtcManager)
        let stream = RemoteStream(roomID: "room-id", userID: "bot-user")
        try controller.setRemoteStream(stream)
        try controller.attach(to: UIView(), contentMode: .fit)

        try controller.reset()
        try controller.attach(to: UIView(), contentMode: .fill)

        XCTAssertEqual(
            rtcManager.calls,
            [
                .bindRemoteVideo(stream, .fit),
                .unbindRemoteVideo(stream)
            ]
        )
    }
}
