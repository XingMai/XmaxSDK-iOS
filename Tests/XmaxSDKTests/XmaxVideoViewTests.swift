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
        let rtcProvider = RtcProvidingStub()
        let track = RealtimeVideoTrack(id: "track")
        register(track: track, rtcProvider: rtcProvider)
        defer { VideoRenderRegistry.unregister(track) }
        let view = XmaxVideoView(
            track: track,
            videoContentMode: .fit
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        window.addSubview(view)

        XCTAssertEqual(rtcProvider.calls, [.bindLocalVideo(.fit)])
    }

    func testChangingContentModeRefreshesRTCBinding() {
        let rtcProvider = RtcProvidingStub()
        let track = RealtimeVideoTrack(id: "track")
        register(track: track, rtcProvider: rtcProvider)
        defer { VideoRenderRegistry.unregister(track) }
        let view = XmaxVideoView(track: track)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)

        view.videoContentMode = .fit

        XCTAssertEqual(
            rtcProvider.calls,
            [.bindLocalVideo(.fill), .bindLocalVideo(.fit)]
        )
    }

    func testChangingTrackDetachesPreviousBindingAndAttachesNextTrack() {
        let rtcProvider = RtcProvidingStub()
        let firstTrack = RealtimeVideoTrack(id: "first")
        let secondTrack = RealtimeVideoTrack(id: "second")
        register(track: firstTrack, rtcProvider: rtcProvider)
        register(track: secondTrack, rtcProvider: rtcProvider)
        defer {
            VideoRenderRegistry.unregister(firstTrack)
            VideoRenderRegistry.unregister(secondTrack)
        }
        let view = XmaxVideoView(track: firstTrack)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)

        view.track = secondTrack

        XCTAssertEqual(
            rtcProvider.calls,
            [
                .bindLocalVideo(.fill),
                .unbindLocalVideo,
                .bindLocalVideo(.fill)
            ]
        )
    }

    func testMovingOutOfWindowDetachesCurrentTrack() {
        let rtcProvider = RtcProvidingStub()
        let track = RealtimeVideoTrack(id: "track")
        register(track: track, rtcProvider: rtcProvider)
        defer { VideoRenderRegistry.unregister(track) }
        let view = XmaxVideoView(track: track)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)

        view.removeFromSuperview()

        XCTAssertEqual(
            rtcProvider.calls,
            [.bindLocalVideo(.fill), .unbindLocalVideo]
        )
    }
}

private extension XmaxVideoViewTests {
    func register(
        track: RealtimeVideoTrack,
        rtcProvider: RtcProvidingStub
    ) {
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(
                libraryName: rtcProvider.renderLibraryName,
                attachHandler: { view, contentMode in
                    try rtcProvider.bindLocalVideo(
                        to: view,
                        contentMode: contentMode
                    )
                },
                detachHandler: {
                    try rtcProvider.unbindLocalVideo()
                }
            )
        )
    }
}
