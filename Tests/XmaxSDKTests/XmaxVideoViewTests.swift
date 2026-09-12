import AVFoundation
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
        XCTAssertTrue(view.isInteractionEnabled)
        XCTAssertEqual(view.backgroundColor, .black)
        XCTAssertTrue(view.clipsToBounds)
    }

    func testInitializationAcceptsInteractionState() {
        let view = XmaxVideoView(isInteractionEnabled: false)

        XCTAssertFalse(view.isInteractionEnabled)
    }

    func testMovingIntoWindowBindsTrackWithContentMode() {
        let recorder = VideoBindingRecorder()
        let track = RealtimeVideoTrack(id: "track")
        register(track: track, recorder: recorder)
        defer { VideoRenderRegistry.unregister(track) }
        let view = XmaxVideoView(
            track: track,
            videoContentMode: .fit
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))

        window.addSubview(view)

        XCTAssertEqual(recorder.events, [.attach("track", .fit)])
    }

    func testChangingContentModeRefreshesRenderBinding() {
        let recorder = VideoBindingRecorder()
        let track = RealtimeVideoTrack(id: "track")
        register(track: track, recorder: recorder)
        defer { VideoRenderRegistry.unregister(track) }
        let view = XmaxVideoView(track: track)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)

        view.videoContentMode = .fit

        XCTAssertEqual(
            recorder.events,
            [.attach("track", .fill), .attach("track", .fit)]
        )
    }

    func testChangingTrackDetachesPreviousBindingAndAttachesNextTrack() {
        let recorder = VideoBindingRecorder()
        let firstTrack = RealtimeVideoTrack(id: "first")
        let secondTrack = RealtimeVideoTrack(id: "second")
        register(track: firstTrack, recorder: recorder)
        register(track: secondTrack, recorder: recorder)
        defer {
            VideoRenderRegistry.unregister(firstTrack)
            VideoRenderRegistry.unregister(secondTrack)
        }
        let view = XmaxVideoView(track: firstTrack)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)

        view.track = secondTrack

        XCTAssertEqual(
            recorder.events,
            [
                .attach("first", .fill),
                .detach("first"),
                .attach("second", .fill)
            ]
        )
    }

    func testMovingOutOfWindowDetachesCurrentTrack() {
        let recorder = VideoBindingRecorder()
        let track = RealtimeVideoTrack(id: "track")
        register(track: track, recorder: recorder)
        defer { VideoRenderRegistry.unregister(track) }
        let view = XmaxVideoView(track: track)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.addSubview(view)

        view.removeFromSuperview()

        XCTAssertEqual(
            recorder.events,
            [.attach("track", .fill), .detach("track")]
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

    func testPreviewPoolKeepsInFlightPixelsAndReusesFormatDescription() throws {
        let view = XmaxVideoView()
        let frame = try makeNV12Frame(timestampUs: 0)
        let first = try view.makeLocalPreviewPixelBuffer(frame)
        let firstDescription = try view.localPreviewDescription(for: first)
        let second = try view.makeLocalPreviewPixelBuffer(frame)

        XCTAssertFalse(first === second)
        XCTAssertTrue(firstDescription === (try view.localPreviewDescription(for: second)))
        let restored = try NV12VideoFrameConverter.convert(
            pixelBuffer: first, outputWidth: 2, outputHeight: 2,
            rotation: .rotation0, timestampUs: 0
        )
        XCTAssertEqual(restored.planes[0].data, frame.planes[0].data)

        let largerFrame = try VideoFrame(
            format: VideoFormat(width: 4, height: 2, pixelFormat: .nv12),
            timestampUs: 1,
            planes: [
                VideoFramePlane(data: Data(repeating: 64, count: 8), stride: 4),
                VideoFramePlane(data: Data(repeating: 128, count: 4), stride: 4)
            ]
        )
        let larger = try view.makeLocalPreviewPixelBuffer(largerFrame)
        let description = try view.localPreviewDescription(for: larger)
        XCTAssertEqual(CMVideoFormatDescriptionGetDimensions(description).width, 4)
        XCTAssertEqual(CVPixelBufferGetWidth(first), 2)

        view.clearDecodedVideoPreview()
        let restarted = try view.makeLocalPreviewPixelBuffer(frame)
        XCTAssertEqual(CVPixelBufferGetWidth(restarted), 2)
    }

    func testNV12CropOnlyPathPreservesPlaneOffsetsAndPadding() throws {
        let frame = try VideoFrame(
            format: VideoFormat(width: 4, height: 2, pixelFormat: .nv12),
            timestampUs: 123,
            planes: [
                VideoFramePlane(data: Data([10, 20, 30, 40, 50, 60, 70, 80]), stride: 4),
                VideoFramePlane(data: Data([100, 110, 120, 130]), stride: 4)
            ]
        )
        let buffer = try XmaxVideoView.makeNV12PixelBuffer(frame)
        let cropped = try NV12VideoFrameConverter.convert(
            pixelBuffer: buffer, outputWidth: 2, outputHeight: 2,
            rotation: .rotation0, timestampUs: 123
        )

        XCTAssertEqual(cropped.planes[0].data, Data([10, 20, 50, 60, 100, 110]))
        XCTAssertEqual(cropped.timestampUs, 123)
    }

    func testDecodedPreviewMirrorChangesWithoutRecreatingLayer() throws {
        let view = XmaxVideoView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let presenter = DecodedVideoPreviewPresenter()
        presenter.setMirrored(true)
        presenter.attach(to: view, contentMode: .fit)
        let layer = try XCTUnwrap(view.layer.sublayers?.compactMap { $0 as? AVSampleBufferDisplayLayer }.first)
        XCTAssertEqual(layer.affineTransform().a, -1)
        XCTAssertEqual(layer.videoGravity, .resizeAspect)
        presenter.setMirrored(false)
        XCTAssertEqual(layer.affineTransform(), .identity)
        presenter.detach(from: view)
        XCTAssertNil(layer.superlayer)
    }

}

private extension XmaxVideoViewTests {
    func register(
        track: RealtimeVideoTrack,
        recorder: VideoBindingRecorder
    ) {
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(
                attachHandler: { _, contentMode in
                    recorder.events.append(.attach(track.id, contentMode))
                },
                detachHandler: { _ in
                    recorder.events.append(.detach(track.id))
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

@MainActor
private final class VideoBindingRecorder {
    enum Event: Equatable {
        case attach(String, VideoContentMode)
        case detach(String)
    }

    // 绑定记录
    var events: [Event] = []
}
