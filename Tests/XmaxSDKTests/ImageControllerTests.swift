import Foundation
import UIKit
import XCTest
@testable import XmaxSDK

final class ImageControllerTests: XCTestCase {
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
        let rtcManager = RtcManagingStub()
        let sourceController = ImageSourceControllingStub(
            resolvedFormat: imageFormat
        )
        let manager = makeManager(
            rtcManager: rtcManager,
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
            rtcManager.calls,
            [.useExternalVideoSource]
        )

        let track = try XCTUnwrap(stream.videoTrack)
        let libraryName = await MainActor.run {
            VideoRenderRegistry.binding(for: track)?.libraryName
        }
        XCTAssertEqual(libraryName, "UIKit")
    }

    func testStopClearsSourceTrackAndPreviewBinding() async throws {
        let rtcManager = RtcManagingStub()
        let sourceController = ImageSourceControllingStub(
            resolvedFormat: imageFormat
        )
        let manager = makeManager(
            rtcManager: rtcManager,
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
            try binding.attach(to: XmaxVideoView(), contentMode: .fill)
        }

        await manager.stopLocalImageStream()

        XCTAssertNil(manager.currentTrack)
        XCTAssertEqual(sourceController.calls.last, .stop)
        let hasBinding = await MainActor.run {
            VideoRenderRegistry.binding(for: track) != nil
        }
        XCTAssertFalse(hasBinding)
        XCTAssertFalse(rtcManager.calls.contains(.bindLocalVideo(.fill)))
        XCTAssertFalse(rtcManager.calls.contains(.unbindLocalVideo))
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

private extension ImageControllerTests {
    var imageFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 832, height: 1_472, fps: 24)
    }

    func makeManager(
        rtcManager: RtcManagingStub = RtcManagingStub(),
        sourceController: ImageSourceControllingStub
    ) -> ImageController {
        ImageController(
            rtcManager: rtcManager,
            imageSourceController: sourceController
        )
    }
}
