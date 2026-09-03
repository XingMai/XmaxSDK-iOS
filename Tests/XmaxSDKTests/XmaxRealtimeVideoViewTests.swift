import UIKit
import XCTest
@testable import XmaxSDK

@MainActor
final class XmaxRealtimeVideoViewTests: XCTestCase {
    func testTracksAreBoundToLayeredVideoViews() {
        let localTrack = RealtimeVideoTrack(id: "local")
        let remoteTrack = RealtimeVideoTrack(id: "remote")
        let view = XmaxRealtimeVideoView(
            localTrack: localTrack,
            remoteTrack: remoteTrack
        )

        let videoViews = view.subviews.compactMap { $0 as? XmaxVideoView }

        XCTAssertEqual(videoViews.count, 2)
        XCTAssertTrue(videoViews[0].track === localTrack)
        XCTAssertTrue(videoViews[1].track === remoteTrack)
        XCTAssertTrue(videoViews[1].isHidden)
    }

    func testRemoteVideoAppearsAfterFirstFrameAndHidesWhenCleared() throws {
        let remoteTrack = RealtimeVideoTrack(id: "remote")
        VideoRenderRegistry.register(
            remoteTrack,
            binding: VideoRenderBinding(imageFrame: try makeImageFrame())
        )
        defer { VideoRenderRegistry.unregister(remoteTrack) }
        let view = XmaxRealtimeVideoView(remoteTrack: remoteTrack)
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }

        window.addSubview(view)

        let remoteVideoView = try XCTUnwrap(
            view.subviews.compactMap { $0 as? XmaxVideoView }.last
        )
        XCTAssertFalse(remoteVideoView.isHidden)
        XCTAssertEqual(remoteVideoView.alpha, 1)

        view.remoteTrack = nil

        XCTAssertTrue(remoteVideoView.isHidden)
        XCTAssertEqual(remoteVideoView.alpha, 0)
        XCTAssertNil(remoteVideoView.track)
    }

    func testRemoteVideoRemainsHiddenBeforeFirstFrame() {
        let remoteTrack = RealtimeVideoTrack(id: "remote")
        VideoRenderRegistry.register(
            remoteTrack,
            binding: VideoRenderBinding(
                libraryName: "Test",
                attachHandler: { _, _ in },
                detachHandler: { _ in }
            )
        )
        defer { VideoRenderRegistry.unregister(remoteTrack) }
        let view = XmaxRealtimeVideoView(remoteTrack: remoteTrack)
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )

        window.addSubview(view)

        let remoteVideoView = view.subviews
            .compactMap { $0 as? XmaxVideoView }
            .last
        XCTAssertTrue(remoteVideoView?.isHidden == true)
    }
}

private extension XmaxRealtimeVideoViewTests {
    func makeImageFrame() throws -> VideoFrame {
        try VideoFrame(
            format: VideoFormat(
                width: 1,
                height: 1,
                pixelFormat: .bgra
            ),
            timestampUs: 0,
            planes: [
                VideoFramePlane(
                    data: Data([0, 0, 0, 255]),
                    stride: 4
                )
            ]
        )
    }
}
