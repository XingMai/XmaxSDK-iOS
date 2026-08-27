import CoreGraphics
import Foundation
import UIKit
import XCTest
@testable import XmaxSDK

@MainActor
final class MediaSourceControllerTests: XCTestCase {
    func testPrepareResolvesRotatedSizeAndConfiguresPlayer() async throws {
        let components = makeComponents(hasAudio: true)
        let fileURL = URL(fileURLWithPath: "/tmp/source.mp4")

        let configuration = try await components.controller.prepare(
            fileURL: fileURL,
            videoFormat: nil
        )

        XCTAssertEqual(
            configuration,
            MediaSourceConfiguration(
                videoFormat: videoFormat,
                hasAudio: true
            )
        )
        XCTAssertEqual(
            components.mediaService.requestedSizes,
            [CGSize(width: 1_080, height: 1_920)]
        )
        XCTAssertEqual(components.player.calls, [
            .configure(
                fileURL: fileURL,
                outputWidth: 832,
                outputHeight: 1_472,
                rotation: .rotation90,
                frameRate: 24,
                hasAudio: true
            )
        ])
        XCTAssertTrue(components.controller.hasAudio)
    }

    func testStartPauseRestartAndStopUseSinglePlayerTimeline()
        async throws {
        let components = makeComponents(hasAudio: true)
        _ = try await components.controller.prepare(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: videoFormat
        )

        try await components.controller.start()
        let checkpoint = await components.controller.pause()
        try await components.controller.restart(from: 750_000)
        await components.controller.stop()

        XCTAssertEqual(checkpoint, 625_000)
        XCTAssertEqual(Array(components.player.calls.suffix(4)), [
            .start,
            .pause,
            .restart(750_000),
            .stop
        ])
        XCTAssertFalse(components.controller.hasAudio)
    }

    func testLocalAudioPreviewControlMutesOnlyPlayerOutput() async throws {
        let components = makeComponents(hasAudio: true)
        _ = try await components.controller.prepare(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: nil
        )

        try await components.controller.setLocalAudioPreviewEnabled(false)
        try await components.controller.setLocalAudioPreviewEnabled(true)

        XCTAssertEqual(Array(components.player.calls.suffix(2)), [
            .setLocalAudioPreviewEnabled(false),
            .setLocalAudioPreviewEnabled(true)
        ])
    }

    func testSilentVideoIgnoresLocalAudioPreviewControl() async throws {
        let components = makeComponents(hasAudio: false)
        _ = try await components.controller.prepare(
            fileURL: URL(fileURLWithPath: "/tmp/silent.mp4"),
            videoFormat: nil
        )

        try await components.controller.setLocalAudioPreviewEnabled(false)

        XCTAssertFalse(components.player.calls.contains(
            .setLocalAudioPreviewEnabled(false)
        ))
    }
}

private extension MediaSourceControllerTests {
    struct Components {
        let controller: MediaSourceController
        let mediaService: MediaServicingStub
        let player: VideoPlayerControllingStub
    }

    var videoFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 832, height: 1_472, fps: 24)
    }

    func makeComponents(hasAudio: Bool) -> Components {
        let metadataManager = MediaFileMetadataManagingStub(
            metadata: MediaFileMetadata(
                width: 1_920,
                height: 1_080,
                rotation: .rotation90,
                durationUs: 2_000_000,
                hasAudio: hasAudio
            )
        )
        let mediaService = MediaServicingStub(
            resolvedSize: CGSize(width: 832, height: 1_472)
        )
        let player = VideoPlayerControllingStub()
        let controller = MediaSourceController(
            metadataManager: metadataManager,
            mediaService: mediaService,
            playerController: player
        )
        return Components(
            controller: controller,
            mediaService: mediaService,
            player: player
        )
    }
}

private final class MediaFileMetadataManagingStub:
    MediaFileMetadataManaging,
    Sendable {

    // 测试配置
    private let metadata: MediaFileMetadata

    init(metadata: MediaFileMetadata) {
        self.metadata = metadata
    }

    func readMetadata(fileURL: URL) async throws -> MediaFileMetadata {
        metadata
    }
}

private enum VideoPlayerControllingCall: Equatable {
    case configure(
        fileURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        frameRate: Int,
        hasAudio: Bool
    )
    case start
    case pause
    case restart(Int64)
    case resumePreviewIfNeeded
    case setLocalAudioPreviewEnabled(Bool)
    case attachPreview
    case detachPreview
    case stop
}

@MainActor
private final class VideoPlayerControllingStub: VideoPlayerControlling {

    // 调用记录
    private(set) var calls: [VideoPlayerControllingCall] = []

    func configure(
        fileURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        frameRate: Int,
        hasAudio: Bool
    ) async throws {
        calls.append(.configure(
            fileURL: fileURL,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            rotation: rotation,
            frameRate: frameRate,
            hasAudio: hasAudio
        ))
    }

    func start() throws {
        calls.append(.start)
    }

    func pause() -> Int64? {
        calls.append(.pause)
        return 625_000
    }

    func restart(from mediaTimeUs: Int64) async throws {
        calls.append(.restart(mediaTimeUs))
    }

    func resumePreviewIfNeeded() {
        calls.append(.resumePreviewIfNeeded)
    }

    func setLocalAudioPreviewEnabled(_ enabled: Bool) {
        calls.append(.setLocalAudioPreviewEnabled(enabled))
    }

    func attachPreview(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        calls.append(.attachPreview)
    }

    func detachPreview(from view: UIView) {
        calls.append(.detachPreview)
    }

    func stop() {
        calls.append(.stop)
    }
}
