import Foundation
import UIKit
import XCTest
@testable import XmaxSDK

final class XmaxRealtimeImageManagerTests: XCTestCase {
    func testCreateAcceptsEncodedImageData() async throws {
        let sourceController = ImageSourceControllingStub(
            resolvedFormat: imageFormat
        )
        let manager = makeManager(sourceController: sourceController)
        let imageData = Data("encoded-image".utf8)

        let stream = try await manager.createLocalImageStream(
            imageData: imageData,
            videoFormat: nil
        )

        XCTAssertEqual(stream.videoTrack?.videoFormat, imageFormat)
        XCTAssertEqual(
            sourceController.calls,
            [.prepareData(imageData, nil), .start]
        )
    }

    func testCreateConfiguresExternalSourceAndRegistersTrack() async throws {
        let rtcProvider = RtcProvidingStub()
        let sourceController = ImageSourceControllingStub(
            resolvedFormat: imageFormat
        )
        let manager = makeManager(
            rtcProvider: rtcProvider,
            sourceController: sourceController
        )
        let fileURL = URL(fileURLWithPath: "/tmp/reference.png")

        let stream = try await manager.createLocalImageStream(
            fileURL: fileURL,
            videoFormat: nil
        )

        XCTAssertEqual(stream.id, StreamID.local.rawValue)
        XCTAssertEqual(stream.videoTrack?.id, "video0")
        XCTAssertEqual(stream.videoTrack?.videoFormat, imageFormat)
        XCTAssertNil(stream.videoTrack?.position)
        XCTAssertTrue(stream.videoTrack === manager.currentTrack)
        XCTAssertEqual(
            sourceController.calls,
            [.prepare(fileURL, nil), .start]
        )
        XCTAssertEqual(
            rtcProvider.calls,
            [
                .configureVideoEncoding(VideoEncodingConfiguration(
                    width: imageFormat.width,
                    height: imageFormat.height,
                    frameRate: imageFormat.fps
                )),
                .useExternalVideoSource
            ]
        )

        let track = try XCTUnwrap(stream.videoTrack)
        let libraryName = await MainActor.run {
            VideoRenderRegistry.binding(for: track)?.libraryName
        }
        XCTAssertEqual(libraryName, "test")
    }

    func testStopClearsSourceTrackAndPreviewBinding() async throws {
        let rtcProvider = RtcProvidingStub()
        let sourceController = ImageSourceControllingStub(
            resolvedFormat: imageFormat
        )
        let manager = makeManager(
            rtcProvider: rtcProvider,
            sourceController: sourceController
        )
        let stream = try await manager.createLocalImageStream(
            fileURL: URL(fileURLWithPath: "/tmp/reference.png"),
            videoFormat: imageFormat
        )
        let track = try XCTUnwrap(stream.videoTrack)
        try await MainActor.run {
            let binding = try XCTUnwrap(
                VideoRenderRegistry.binding(for: track)
            )
            try binding.attach(to: UIView(), contentMode: .fill)
        }

        await manager.stopLocalImageStream()

        XCTAssertNil(manager.currentTrack)
        XCTAssertEqual(sourceController.calls.last, .stop)
        let hasBinding = await MainActor.run {
            VideoRenderRegistry.binding(for: track) != nil
        }
        XCTAssertFalse(hasBinding)
        XCTAssertEqual(
            Array(rtcProvider.calls.suffix(2)),
            [.bindLocalVideo(.fill), .unbindLocalVideo]
        )
    }

    func testCreateRollsBackPreparedSourceWhenStartFails() async {
        let expectedError = XmaxError(
            code: .mediaError,
            message: "Failed to push image frame"
        )
        let sourceController = ImageSourceControllingStub(
            resolvedFormat: imageFormat,
            startError: expectedError
        )
        let manager = makeManager(sourceController: sourceController)

        do {
            _ = try await manager.createLocalImageStream(
                fileURL: URL(fileURLWithPath: "/tmp/reference.png"),
                videoFormat: nil
            )
            XCTFail("Expected image source start to fail")
        } catch {
            XCTAssertEqual(error as? XmaxError, expectedError)
            XCTAssertNil(manager.currentTrack)
            XCTAssertEqual(
                sourceController.calls,
                [
                    .prepare(
                        URL(fileURLWithPath: "/tmp/reference.png"),
                        nil
                    ),
                    .start,
                    .stop
                ]
            )
        }
    }
}

private extension XmaxRealtimeImageManagerTests {
    var imageFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 832, height: 1_472, fps: 24)
    }

    func makeManager(
        rtcProvider: RtcProvidingStub = RtcProvidingStub(),
        sourceController: ImageSourceControllingStub
    ) -> XmaxRealtimeImageManager {
        XmaxRealtimeImageManager(
            rtcProvider: rtcProvider,
            imageSourceController: sourceController,
            encodingController: EncodingController(rtcProvider: rtcProvider)
        )
    }
}
