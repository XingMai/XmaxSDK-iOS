import CoreGraphics
import UIKit
import XCTest
@testable import XmaxSDK

final class CameraControllerTests: XCTestCase {
    func testCreateStartsInternalCaptureAndRegistersLocalTrack() async throws {
        let rtcManager = RtcManagingStub()
        let permissionManager = PermissionManagingStub()
        let mediaService = MediaServicingStub(
            resolvedSize: CGSize(width: 896, height: 672)
        )
        let manager = makeManager(
            rtcManager: rtcManager,
            permissionManager: permissionManager,
            mediaService: mediaService
        )

        let stream = try await manager.createLocalCameraStream(
            videoFormat: RealtimeVideoFormat(
                width: 640,
                height: 480,
                fps: 30
            ),
            position: .front
        )

        XCTAssertEqual(permissionManager.cameraRequestCount, 1)
        XCTAssertEqual(
            mediaService.requestedSizes,
            [CGSize(width: 640, height: 480)]
        )
        XCTAssertEqual(stream.id, StreamID.local.rawValue)
        XCTAssertEqual(stream.videoTrack?.id, "video0")
        XCTAssertEqual(
            stream.videoTrack?.videoFormat,
            RealtimeVideoFormat(width: 896, height: 672, fps: 30)
        )
        XCTAssertEqual(stream.videoTrack?.position, .front)
        XCTAssertTrue(stream.videoTrack === manager.currentTrack)
        XCTAssertEqual(
            rtcManager.calls,
            [
                .switchCamera(.front),
                .startVideoCapture(width: 896, height: 672, frameRate: 30)
            ]
        )

        let track = try XCTUnwrap(stream.videoTrack)
        let libraryName = await MainActor.run {
            VideoRenderRegistry.binding(for: track)?.libraryName
        }
        XCTAssertEqual(libraryName, "test")
    }

    func testCreateRejectsSecondActiveCameraStream() async throws {
        let manager = makeManager()
        _ = try await manager.createLocalCameraStream(
            videoFormat: RealtimeVideoFormat(
                width: 1_024,
                height: 768,
                fps: 30
            ),
            position: .front
        )

        do {
            _ = try await manager.createLocalCameraStream(
                videoFormat: RealtimeVideoFormat(
                    width: 1_024,
                    height: 768,
                    fps: 30
                ),
                position: .back
            )
            XCTFail("Expected a duplicate camera stream to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Stop the current local camera stream before " +
                        "creating another one"
                )
            )
        }
    }

    func testCreateRollsBackCaptureWhenRTCStartFails() async {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "Failed to start camera capture"
        )
        let rtcManager = RtcManagingStub(
            startVideoCaptureError: expectedError
        )
        let manager = makeManager(rtcManager: rtcManager)

        do {
            _ = try await manager.createLocalCameraStream(
                videoFormat: RealtimeVideoFormat(
                    width: 1_024,
                    height: 768,
                    fps: 30
                ),
                position: .front
            )
            XCTFail("Expected camera capture to fail")
        } catch {
            XCTAssertEqual(error as? XmaxError, expectedError)
            XCTAssertNil(manager.currentTrack)
            XCTAssertEqual(
                rtcManager.calls,
                [
                    .switchCamera(.front),
                    .startVideoCapture(
                        width: 1_024,
                        height: 768,
                        frameRate: 30
                    ),
                    .stopVideoCapture
                ]
            )
        }
    }

    func testSwitchCameraUpdatesExistingTrack() async throws {
        let rtcManager = RtcManagingStub()
        let manager = makeManager(rtcManager: rtcManager)
        let originalStream = try await manager.createLocalCameraStream(
            videoFormat: RealtimeVideoFormat(
                width: 1_024,
                height: 768,
                fps: 30
            ),
            position: .front
        )

        let switchedStream = try await manager.switchCamera()

        XCTAssertTrue(originalStream.videoTrack === switchedStream.videoTrack)
        XCTAssertEqual(switchedStream.videoTrack?.position, .back)
        XCTAssertEqual(rtcManager.calls.last, .switchCamera(.back))
    }

    func testStopClearsTrackPreviewBindingAndCapture() async throws {
        let rtcManager = RtcManagingStub()
        let manager = makeManager(rtcManager: rtcManager)
        let stream = try await manager.createLocalCameraStream(
            videoFormat: RealtimeVideoFormat(
                width: 1_024,
                height: 768,
                fps: 30
            ),
            position: .front
        )
        let track = try XCTUnwrap(stream.videoTrack)
        try await MainActor.run {
            let binding = try XCTUnwrap(
                VideoRenderRegistry.binding(for: track)
            )
            try binding.attach(to: UIView(), contentMode: .fill)
        }

        await manager.stopLocalCameraStream()

        XCTAssertNil(manager.currentTrack)
        let hasBinding = await MainActor.run {
            VideoRenderRegistry.binding(for: track) != nil
        }
        XCTAssertFalse(hasBinding)
        XCTAssertEqual(
            Array(rtcManager.calls.suffix(3)),
            [
                .bindLocalVideo(.fill),
                .unbindLocalVideo,
                .stopVideoCapture
            ]
        )
    }

    @MainActor
    func testLocalCanvasBindingFailureReportsRTCError() async throws {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "Failed to bind the local RTC canvas"
        )
        let recorder = CameraErrorRecorder()
        let manager = makeManager(
            rtcManager: RtcManagingStub(
                bindLocalVideoError: expectedError
            ),
            errorListener: { recorder.record($0) }
        )
        let stream = try await manager.createLocalCameraStream(
            videoFormat: RealtimeVideoFormat(
                width: 1_024,
                height: 768,
                fps: 30
            ),
            position: .front
        )
        let track = try XCTUnwrap(stream.videoTrack)
        let binding = try XCTUnwrap(
            VideoRenderRegistry.binding(for: track)
        )

        XCTAssertThrowsError(
            try binding.attach(to: UIView(), contentMode: .fill)
        )
        XCTAssertEqual(recorder.recordedErrors, [expectedError])

        await manager.stopLocalCameraStream()
    }
}

private extension CameraControllerTests {
    func makeManager(
        rtcManager: RtcManagingStub = RtcManagingStub(),
        permissionManager: PermissionManagingStub = PermissionManagingStub(),
        mediaService: MediaServicingStub = MediaServicingStub(
            resolvedSize: CGSize(width: 1_024, height: 768)
        ),
        errorListener: @escaping XmaxErrorListener = { _ in }
    ) -> CameraController {
        CameraController(
            rtcManager: rtcManager,
            permissionManager: permissionManager,
            mediaService: mediaService,
            errorListener: errorListener
        )
    }
}

private final class CameraErrorRecorder: @unchecked Sendable {
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
