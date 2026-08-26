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

    func testNV12FrameCanBeDisplayedAsStaticPreview() throws {
        let image = try XmaxVideoView.makeImage(makeNV12Frame(timestampUs: 0))

        XCTAssertEqual(image.size, CGSize(width: 2, height: 2))
    }

    func testLatestPauseOwnsPreviewUntilItsResumeRuns() async throws {
        let rtcManager = RtcManagingStub()
        let track = RealtimeVideoTrack(id: "video-track")
        register(track: track, rtcManager: rtcManager)
        defer { VideoRenderRegistry.unregister(track) }
        let view = XmaxVideoView(track: track)
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        window.addSubview(view)
        let imageView = try XCTUnwrap(
            view.subviews.compactMap { $0 as? UIImageView }.first
        )
        let controller = LocalVideoPreviewController()
        try controller.output(
            frame: try makeNV12Frame(timestampUs: 1),
            mediaTimeUs: 123_000,
            frameListener: { _ in }
        )

        let firstPause = await controller.pause(track: track)
        try controller.output(
            frame: try makeNV12Frame(timestampUs: 2),
            mediaTimeUs: 456_000,
            frameListener: { _ in }
        )
        controller.resumeVideoOutput()
        try controller.output(
            frame: try makeNV12Frame(timestampUs: 2),
            mediaTimeUs: 456_000,
            frameListener: { _ in }
        )
        let secondPause = await controller.pause(track: track)

        XCTAssertEqual(firstPause.mediaTimeUs, 123_000)
        XCTAssertEqual(secondPause.mediaTimeUs, 456_000)
        XCTAssertFalse(imageView.isHidden)
        await firstPause.resume()
        XCTAssertFalse(imageView.isHidden)
        await secondPause.resume()
        XCTAssertTrue(imageView.isHidden)
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

    func makeNV12Frame(timestampUs: Int64) throws -> VideoFrame {
        let data = Data([
            64, 96,
            128, 160,
            128, 128,
        ])
        return try VideoFrame(
            format: VideoFormat(
                width: 2,
                height: 2,
                pixelFormat: .nv12
            ),
            timestampUs: timestampUs,
            planes: [
                VideoFramePlane(
                    data: data,
                    stride: 2,
                    byteLength: 4
                ),
                VideoFramePlane(
                    data: data,
                    stride: 2,
                    byteOffset: 4,
                    byteLength: 2
                ),
            ]
        )
    }
}
