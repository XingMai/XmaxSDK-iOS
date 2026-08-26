import CoreGraphics
import XCTest
@testable import XmaxSDK

final class MediaControllerTests: XCTestCase {
    func testCreateInitializesRTCAndTakesLocalMediaOwnership() async throws {
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

        let ownsStream = await manager.owns(stream)
        let currentTrack = await manager.currentTrack
        let currentVideoFormat = await manager.currentVideoFormat
        XCTAssertTrue(ownsStream)
        XCTAssertTrue(stream.videoTrack === currentTrack)
        XCTAssertEqual(
            currentVideoFormat,
            RealtimeVideoFormat(width: 1_024, height: 768, fps: 30)
        )
        XCTAssertEqual(
            rtcManager.calls,
            [
                .initialize,
                .configureVideoEncoding(VideoEncodingConfiguration(
                    width: 1_024,
                    height: 768,
                    frameRate: 30
                )),
                .switchCamera(.front),
                .startVideoCapture(width: 1_024, height: 768, frameRate: 30)
            ]
        )
    }

    func testCreateFailureDestroysRTCAndReleasesOwnership() async {
        let expectedError = XmaxError(
            code: .rtcError,
            message: "Failed to initialize RTC"
        )
        let rtcManager = RtcManagingStub(
            initializationError: expectedError
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
            XCTFail("Expected RTC initialization to fail")
        } catch {
            let currentTrack = await manager.currentTrack
            XCTAssertEqual(error as? XmaxError, expectedError)
            XCTAssertNil(currentTrack)
            XCTAssertEqual(rtcManager.calls, [.initialize, .destroy])
        }
    }

    func testReplaceReusesRTCAndCurrentTrack() async throws {
        let rtcManager = RtcManagingStub()
        let mediaService = MediaServicingStub(
            resolvedSize: CGSize(width: 1_024, height: 768)
        )
        let manager = makeManager(
            rtcManager: rtcManager,
            mediaService: mediaService
        )
        let originalStream = try await manager.createLocalCameraStream(
            videoFormat: RealtimeVideoFormat(
                width: 1_024,
                height: 768,
                fps: 24
            ),
            position: .front
        )

        let replacedStream = try await manager.replaceLocalCameraStream(
            videoFormat: RealtimeVideoFormat(
                width: 1_280,
                height: 720,
                fps: 30
            ),
            position: .back
        )

        XCTAssertTrue(originalStream.videoTrack === replacedStream.videoTrack)
        XCTAssertEqual(replacedStream.videoTrack?.position, .back)
        XCTAssertEqual(
            rtcManager.calls.filter { $0 == .initialize }.count,
            1
        )
        XCTAssertFalse(rtcManager.calls.contains(.destroy))
    }

    func testStopReleasesCameraPreviewOwnershipAndRTC() async throws {
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

        await manager.stopLocalCameraStream()

        let currentTrack = await manager.currentTrack
        let ownsStream = await manager.owns(stream)
        XCTAssertNil(currentTrack)
        XCTAssertFalse(ownsStream)
        XCTAssertEqual(
            Array(rtcManager.calls.suffix(3)),
            [.unbindLocalVideo, .stopVideoCapture, .destroy]
        )
    }

    func testRepeatedStopDestroysRTCOnlyOnce() async throws {
        let rtcManager = RtcManagingStub()
        let manager = makeManager(rtcManager: rtcManager)
        _ = try await manager.createLocalCameraStream(
            videoFormat: RealtimeVideoFormat(
                width: 1_024,
                height: 768,
                fps: 30
            ),
            position: .front
        )

        async let firstStop: Void = manager.stopLocalCameraStream()
        async let secondStop: Void = manager.stopLocalCameraStream()
        _ = await (firstStop, secondStop)

        XCTAssertEqual(
            rtcManager.calls.filter { $0 == .destroy }.count,
            1
        )
        XCTAssertEqual(
            rtcManager.calls.filter { $0 == .stopVideoCapture }.count,
            1
        )
    }

    func testCreateRejectsAnotherActiveLocalMediaSource() async throws {
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
            XCTFail("Expected another local media source to be rejected")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Stop the current local media stream before " +
                        "creating another one"
                )
            )
        }
    }

    func testStopCameraThenCreateImageChangesOwnership() async throws {
        let rtcManager = RtcManagingStub()
        let imageFormat = RealtimeVideoFormat(
            width: 832,
            height: 1_472,
            fps: 24
        )
        let imageSourceController = ImageSourceControllingStub(
            resolvedFormat: imageFormat
        )
        let manager = makeManager(
            rtcManager: rtcManager,
            imageSourceController: imageSourceController
        )
        let cameraStream = try await manager.createLocalCameraStream(
            videoFormat: RealtimeVideoFormat(
                width: 1_024,
                height: 768,
                fps: 30
            ),
            position: .front
        )

        await manager.stopLocalCameraStream()
        let imageStream = try await manager.createLocalImageStream(
            fileURL: URL(fileURLWithPath: "/tmp/reference.png"),
            videoFormat: nil
        )

        let ownsImageStream = await manager.owns(imageStream)
        let ownsCameraStream = await manager.owns(cameraStream)
        XCTAssertFalse(cameraStream.videoTrack === imageStream.videoTrack)
        XCTAssertEqual(imageStream.videoTrack?.videoFormat, imageFormat)
        XCTAssertTrue(ownsImageStream)
        XCTAssertFalse(ownsCameraStream)
        XCTAssertEqual(
            rtcManager.calls.filter { $0 == .initialize }.count,
            2
        )
        XCTAssertEqual(
            rtcManager.calls.filter { $0 == .destroy }.count,
            1
        )
        XCTAssertTrue(rtcManager.calls.contains(.stopVideoCapture))
        XCTAssertTrue(rtcManager.calls.contains(.useExternalVideoSource))

        await manager.stopLocalCameraStream()
        let trackAfterWrongStop = await manager.currentTrack
        XCTAssertNotNil(trackAfterWrongStop)
        await manager.stopLocalImageStream()
        let trackAfterImageStop = await manager.currentTrack
        XCTAssertNil(trackAfterImageStop)
        XCTAssertEqual(
            rtcManager.calls.filter { $0 == .destroy }.count,
            2
        )
    }

    func testVideoSourceOwnsAudioLifecycleAndRestartsForGeneration() async throws {
        let rtcManager = RtcManagingStub()
        let source = MediaSourceControllingStub(
            configuration: MediaSourceConfiguration(
                videoFormat: RealtimeVideoFormat(
                    width: 832,
                    height: 1_472,
                    fps: 24
                ),
                hasAudio: true
            )
        )
        let manager = makeManager(
            rtcManager: rtcManager,
            mediaSourceController: source
        )

        let stream = try await manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: nil
        )
        try await manager.restartForGeneration()

        let hasAudio = await manager.hasAudio
        let ownsStream = await manager.owns(stream)
        XCTAssertTrue(hasAudio)
        XCTAssertTrue(ownsStream)
        XCTAssertTrue(source.calls.contains(.restart))

        await manager.stopLocalVideoStream()
        let hasAudioAfterStop = await manager.hasAudio
        XCTAssertFalse(hasAudioAfterStop)
        XCTAssertEqual(rtcManager.calls.last, .destroy)
    }
}

private extension MediaControllerTests {
    func makeManager(
        rtcManager: RtcManagingStub = RtcManagingStub(),
        permissionManager: PermissionManagingStub = PermissionManagingStub(),
        mediaService: MediaServicingStub = MediaServicingStub(
            resolvedSize: CGSize(width: 1_024, height: 768)
        ),
        imageSourceController: ImageSourceControllingStub? = nil,
        mediaSourceController: MediaSourceControllingStub? = nil
    ) -> MediaController {
        let transportController = TransportController(
            rtcManager: rtcManager
        )
        let cameraController = CameraController(
            rtcManager: rtcManager,
            permissionManager: permissionManager,
            mediaService: mediaService,
            transportController: transportController
        )
        let imageController = imageSourceController.map {
            ImageController(
                rtcManager: rtcManager,
                imageSourceController: $0,
                transportController: transportController
            )
        }
        let videoController = mediaSourceController.map {
            VideoController(
                rtcManager: rtcManager,
                permissionManager: permissionManager,
                mediaSourceController: $0,
                transportController: transportController
            )
        }
        return MediaController(
            rtcManager: rtcManager,
            cameraController: cameraController,
            imageController: imageController,
            videoController: videoController
        )
    }
}
