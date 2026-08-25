import CoreGraphics
import XCTest
@testable import XmaxSDK

final class XmaxRealtimeManagerTests: XCTestCase {
    func testPublicInterfaceForwardsDefaultCameraLifecycle() async throws {
        let rtcProvider = RtcProvidingStub()
        let realtimeManager = makeManager(rtcProvider: rtcProvider)
        let manager: any XmaxRealtimeManaging = realtimeManager
        let format = RealtimeVideoFormat(
            width: 1_024,
            height: 768,
            fps: 30
        )

        let stream = try await manager.createLocalCameraStream(
            videoFormat: format
        )
        let switchedStream = try await manager.switchCamera()
        try await manager.stopLocalCameraStream()

        XCTAssertEqual(manager.options.model, .x2_0)
        XCTAssertTrue(stream.videoTrack === switchedStream.videoTrack)
        XCTAssertEqual(switchedStream.videoTrack?.position, .back)
        XCTAssertEqual(rtcProvider.calls.first, .initialize)
        XCTAssertEqual(rtcProvider.calls.last, .destroy)
    }

    func testPublicInterfaceForwardsCameraReplacement() async throws {
        let rtcProvider = RtcProvidingStub()
        let manager: any XmaxRealtimeManaging = makeManager(
            rtcProvider: rtcProvider
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
    }
}

private extension XmaxRealtimeManagerTests {
    func makeManager(
        rtcProvider: RtcProvidingStub
    ) -> XmaxRealtimeManager {
        let cameraManager = XmaxRealtimeCameraManager(
            rtcProvider: rtcProvider,
            permissionProvider: PermissionProvidingStub(),
            mediaService: MediaServicingStub(
                resolvedSize: CGSize(width: 1_024, height: 768)
            ),
            encodingController: EncodingController(rtcProvider: rtcProvider)
        )
        let mediaManager = XmaxRealtimeMediaManager(
            rtcProvider: rtcProvider,
            cameraManager: cameraManager
        )
        return XmaxRealtimeManager(
            options: RealtimeConfiguration(model: .x2_0),
            mediaManager: mediaManager
        )
    }
}
