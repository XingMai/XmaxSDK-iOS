import Foundation
import XCTest
@testable import XmaxSDK

@MainActor
final class XmaxRealtimeVideoManagerTests: XCTestCase {
    func testCreateWithAudioStartsExternalAudioAndPreview() async throws {
        let rtcProvider = RtcProvidingStub()
        let permissionProvider = PermissionProvidingStub()
        let source = MediaSourceControllingStub(
            configuration: MediaSourceConfiguration(
                videoFormat: videoFormat,
                hasAudio: true
            )
        )
        let manager = makeManager(
            rtcProvider: rtcProvider,
            permissionProvider: permissionProvider,
            mediaSourceController: source
        )
        let fileURL = URL(fileURLWithPath: "/tmp/source.mp4")

        let stream = try await manager.createLocalVideoStream(
            fileURL: fileURL,
            videoFormat: nil
        )

        XCTAssertEqual(stream.videoTrack?.videoFormat, videoFormat)
        XCTAssertTrue(manager.hasAudio)
        XCTAssertEqual(permissionProvider.microphoneRequestCount, 1)
        XCTAssertEqual(
            source.calls,
            [.prepare(fileURL, nil), .start]
        )
        XCTAssertTrue(rtcProvider.calls.contains(.useExternalVideoSource))
        XCTAssertTrue(rtcProvider.calls.contains(.startExternalAudioSource))
    }

    func testCreateWithoutAudioDoesNotStartExternalAudio() async throws {
        let rtcProvider = RtcProvidingStub()
        let permissionProvider = PermissionProvidingStub()
        let source = MediaSourceControllingStub(
            configuration: MediaSourceConfiguration(
                videoFormat: videoFormat,
                hasAudio: false
            )
        )
        let manager = makeManager(
            rtcProvider: rtcProvider,
            permissionProvider: permissionProvider,
            mediaSourceController: source
        )

        _ = try await manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/silent.mp4"),
            videoFormat: videoFormat
        )

        XCTAssertFalse(manager.hasAudio)
        XCTAssertEqual(permissionProvider.microphoneRequestCount, 0)
        XCTAssertFalse(rtcProvider.calls.contains(.startExternalAudioSource))
    }

    func testRestartAndStopForwardLifecycleAndReleaseAudio() async throws {
        let rtcProvider = RtcProvidingStub()
        let source = MediaSourceControllingStub(
            configuration: MediaSourceConfiguration(
                videoFormat: videoFormat,
                hasAudio: true
            )
        )
        let manager = makeManager(
            rtcProvider: rtcProvider,
            mediaSourceController: source
        )
        _ = try await manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: nil
        )

        try await manager.restartForGeneration()
        await manager.stopLocalVideoStream()

        XCTAssertEqual(Array(source.calls.suffix(2)), [.restart, .stop])
        XCTAssertTrue(rtcProvider.calls.contains(.stopExternalAudioSource))
        XCTAssertTrue(rtcProvider.calls.contains(.unbindLocalVideo))
        XCTAssertNil(manager.currentTrack)
    }
}

private extension XmaxRealtimeVideoManagerTests {
    var videoFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 832, height: 1_472, fps: 24)
    }

    func makeManager(
        rtcProvider: RtcProvidingStub,
        permissionProvider: PermissionProvidingStub =
            PermissionProvidingStub(),
        mediaSourceController: MediaSourceControllingStub
    ) -> XmaxRealtimeVideoManager {
        XmaxRealtimeVideoManager(
            rtcProvider: rtcProvider,
            permissionProvider: permissionProvider,
            mediaSourceController: mediaSourceController,
            encodingController: EncodingController(rtcProvider: rtcProvider)
        )
    }
}
