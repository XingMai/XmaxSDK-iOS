import Foundation
import XCTest
@testable import XmaxSDK

@MainActor
final class VideoControllerTests: XCTestCase {
    func testCreateWithAudioStartsExternalAudioAndPreview() async throws {
        let rtcManager = RtcManagingStub()
        let permissionManager = PermissionManagingStub()
        let source = MediaSourceControllingStub(
            configuration: MediaSourceConfiguration(
                videoFormat: videoFormat,
                hasAudio: true
            )
        )
        let manager = makeManager(
            rtcManager: rtcManager,
            permissionManager: permissionManager,
            mediaSourceController: source
        )
        let fileURL = URL(fileURLWithPath: "/tmp/source.mp4")

        let stream = try await manager.createLocalVideoStream(
            fileURL: fileURL,
            videoFormat: nil
        )

        XCTAssertEqual(stream.videoTrack?.videoFormat, videoFormat)
        XCTAssertTrue(manager.hasAudio)
        XCTAssertEqual(permissionManager.microphoneRequestCount, 1)
        XCTAssertEqual(
            source.calls,
            [.prepare(fileURL, nil), .start]
        )
        XCTAssertTrue(rtcManager.calls.contains(.useExternalVideoSource))
        XCTAssertTrue(rtcManager.calls.contains(.startExternalAudioSource))
    }

    func testCreateWithoutAudioDoesNotStartExternalAudio() async throws {
        let rtcManager = RtcManagingStub()
        let permissionManager = PermissionManagingStub()
        let source = MediaSourceControllingStub(
            configuration: MediaSourceConfiguration(
                videoFormat: videoFormat,
                hasAudio: false
            )
        )
        let manager = makeManager(
            rtcManager: rtcManager,
            permissionManager: permissionManager,
            mediaSourceController: source
        )

        _ = try await manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/silent.mp4"),
            videoFormat: videoFormat
        )

        XCTAssertFalse(manager.hasAudio)
        XCTAssertEqual(permissionManager.microphoneRequestCount, 0)
        XCTAssertFalse(rtcManager.calls.contains(.startExternalAudioSource))
    }

    func testRestartAndStopForwardLifecycleAndReleaseAudio() async throws {
        let rtcManager = RtcManagingStub()
        let source = MediaSourceControllingStub(
            configuration: MediaSourceConfiguration(
                videoFormat: videoFormat,
                hasAudio: true
            )
        )
        let manager = makeManager(
            rtcManager: rtcManager,
            mediaSourceController: source
        )
        _ = try await manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: nil
        )

        try await manager.restartForGeneration()
        await manager.stopLocalVideoStream()

        XCTAssertEqual(Array(source.calls.suffix(2)), [.restart(0), .stop])
        XCTAssertTrue(rtcManager.calls.contains(.stopExternalAudioSource))
        XCTAssertFalse(rtcManager.calls.contains(.unbindLocalVideo))
        XCTAssertNil(manager.currentTrack)
    }

    func testRestartUsesPausedPreviewMediaCheckpoint() async throws {
        let rtcManager = RtcManagingStub()
        let source = MediaSourceControllingStub(
            configuration: MediaSourceConfiguration(
                videoFormat: videoFormat,
                hasAudio: false
            ),
            pauseMediaTimeUs: 875_000
        )
        let manager = makeManager(
            rtcManager: rtcManager,
            mediaSourceController: source
        )
        _ = try await manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: nil
        )
        _ = await manager.pauseVideoPreview()
        try await manager.restartForGeneration()

        XCTAssertTrue(source.calls.contains(.restart(875_000)))
    }
}

private extension VideoControllerTests {
    var videoFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 832, height: 1_472, fps: 24)
    }

    func makeManager(
        rtcManager: RtcManagingStub,
        permissionManager: PermissionManagingStub =
            PermissionManagingStub(),
        mediaSourceController: MediaSourceControllingStub
    ) -> VideoController {
        VideoController(
            rtcManager: rtcManager,
            permissionManager: permissionManager,
            mediaSourceController: mediaSourceController
        )
    }
}
