import CoreGraphics
import XCTest
@testable import XmaxSDK

final class XmaxRealtimeMediaManagerTests: XCTestCase {
    func testCreateInitializesRTCAndTakesLocalMediaOwnership() async throws {
        let rtcProvider = RtcProvidingStub()
        let manager = makeManager(rtcProvider: rtcProvider)

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
            rtcProvider.calls,
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
        let rtcProvider = RtcProvidingStub(
            initializationError: expectedError
        )
        let manager = makeManager(rtcProvider: rtcProvider)

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
            XCTAssertEqual(rtcProvider.calls, [.initialize, .destroy])
        }
    }

    func testReplaceReusesRTCAndCurrentTrack() async throws {
        let rtcProvider = RtcProvidingStub()
        let mediaService = MediaServicingStub(
            resolvedSize: CGSize(width: 1_024, height: 768)
        )
        let manager = makeManager(
            rtcProvider: rtcProvider,
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
            rtcProvider.calls.filter { $0 == .initialize }.count,
            1
        )
        XCTAssertFalse(rtcProvider.calls.contains(.destroy))
    }

    func testStopReleasesCameraPreviewOwnershipAndRTC() async throws {
        let rtcProvider = RtcProvidingStub()
        let manager = makeManager(rtcProvider: rtcProvider)
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
            Array(rtcProvider.calls.suffix(3)),
            [.unbindLocalVideo, .stopVideoCapture, .destroy]
        )
    }

    func testRepeatedStopDestroysRTCOnlyOnce() async throws {
        let rtcProvider = RtcProvidingStub()
        let manager = makeManager(rtcProvider: rtcProvider)
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
            rtcProvider.calls.filter { $0 == .destroy }.count,
            1
        )
        XCTAssertEqual(
            rtcProvider.calls.filter { $0 == .stopVideoCapture }.count,
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
}

private extension XmaxRealtimeMediaManagerTests {
    func makeManager(
        rtcProvider: RtcProvidingStub = RtcProvidingStub(),
        permissionProvider: PermissionProvidingStub = PermissionProvidingStub(),
        mediaService: MediaServicingStub = MediaServicingStub(
            resolvedSize: CGSize(width: 1_024, height: 768)
        )
    ) -> XmaxRealtimeMediaManager {
        let cameraManager = XmaxRealtimeCameraManager(
            rtcProvider: rtcProvider,
            permissionProvider: permissionProvider,
            mediaService: mediaService,
            encodingController: EncodingController(rtcProvider: rtcProvider)
        )
        return XmaxRealtimeMediaManager(
            rtcProvider: rtcProvider,
            cameraManager: cameraManager
        )
    }
}
