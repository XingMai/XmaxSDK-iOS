import UIKit
import XCTest
@testable import XmaxSDK

@MainActor
final class XmaxVideoViewTests: XCTestCase {
    func testInitializationUsesPublicRenderingDefaults() {
        let track = RealtimeVideoTrack(id: "track")

        let view = XmaxVideoView(track: track)

        XCTAssertTrue(view.track === track)
        XCTAssertEqual(view.videoContentMode, .fill)
        XCTAssertEqual(view.backgroundColor, .black)
        XCTAssertTrue(view.clipsToBounds)
    }

    func testMovingIntoWindowBindsTrackWithContentMode() {
        let rtcManager = RtcManagingStub()
        let track = RealtimeVideoTrack(id: "track")
        register(track: track, rtcManager: rtcManager)
        defer { VideoRenderRegistry.unregister(track) }
        let view = XmaxVideoView(
            track: track,
            videoContentMode: .fit
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        window.addSubview(view)

        XCTAssertEqual(rtcManager.calls, [.bindLocalVideo(.fit)])
    }

    func testChangingContentModeRefreshesRTCBinding() {
        let rtcManager = RtcManagingStub()
        let track = RealtimeVideoTrack(id: "track")
        register(track: track, rtcManager: rtcManager)
        defer { VideoRenderRegistry.unregister(track) }
        let view = XmaxVideoView(track: track)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)

        view.videoContentMode = .fit

        XCTAssertEqual(
            rtcManager.calls,
            [.bindLocalVideo(.fill), .bindLocalVideo(.fit)]
        )
    }

    func testChangingTrackDetachesPreviousBindingAndAttachesNextTrack() {
        let rtcManager = RtcManagingStub()
        let firstTrack = RealtimeVideoTrack(id: "first")
        let secondTrack = RealtimeVideoTrack(id: "second")
        register(track: firstTrack, rtcManager: rtcManager)
        register(track: secondTrack, rtcManager: rtcManager)
        defer {
            VideoRenderRegistry.unregister(firstTrack)
            VideoRenderRegistry.unregister(secondTrack)
        }
        let view = XmaxVideoView(track: firstTrack)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)

        view.track = secondTrack

        XCTAssertEqual(
            rtcManager.calls,
            [
                .bindLocalVideo(.fill),
                .unbindLocalVideo,
                .bindLocalVideo(.fill)
            ]
        )
    }

    func testMovingOutOfWindowDetachesCurrentTrack() {
        let rtcManager = RtcManagingStub()
        let track = RealtimeVideoTrack(id: "track")
        register(track: track, rtcManager: rtcManager)
        defer { VideoRenderRegistry.unregister(track) }
        let view = XmaxVideoView(track: track)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)

        view.removeFromSuperview()

        XCTAssertEqual(
            rtcManager.calls,
            [.bindLocalVideo(.fill), .unbindLocalVideo]
        )
    }

    func testImageTrackUsesUIImageViewRendering() throws {
        let track = RealtimeVideoTrack(id: "image-track")
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(
                imageFrame: try VideoFrame(
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
            )
        )
        defer { VideoRenderRegistry.unregister(track) }
        let view = XmaxVideoView(track: track)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        window.addSubview(view)

        let imageView = try XCTUnwrap(
            view.subviews.compactMap { $0 as? UIImageView }.first
        )
        XCTAssertFalse(imageView.isHidden)
        XCTAssertNotNil(imageView.image)

        view.track = nil

        XCTAssertTrue(imageView.isHidden)
        XCTAssertNil(imageView.image)
    }
}

private extension XmaxVideoViewTests {
    func register(
        track: RealtimeVideoTrack,
        rtcManager: RtcManagingStub
    ) {
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(
                libraryName: rtcManager.renderLibraryName,
                attachHandler: { view, contentMode in
                    try rtcManager.bindLocalVideo(
                        to: view,
                        contentMode: contentMode
                    )
                },
                detachHandler: { _ in
                    try rtcManager.unbindLocalVideo()
                }
            )
        )
    }
}
