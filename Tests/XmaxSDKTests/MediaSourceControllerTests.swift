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

    func testStartAndStopUseSinglePlayerTimeline() async throws {
        let components = makeComponents(hasAudio: true)
        _ = try await components.controller.prepare(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            videoFormat: videoFormat
        )

        try await components.controller.start()
        await components.controller.stop()

        XCTAssertEqual(Array(components.player.calls.suffix(2)), [
            .start,
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

        await components.controller.setLocalAudioPreviewMuted(true)
        await components.controller.setLocalAudioPreviewMuted(false)

        XCTAssertEqual(Array(components.player.calls.suffix(2)), [
            .setLocalAudioPreviewMuted(true),
            .setLocalAudioPreviewMuted(false)
        ])
    }

    func testSilentVideoIgnoresLocalAudioPreviewControl() async throws {
        let components = makeComponents(hasAudio: false)
        _ = try await components.controller.prepare(
            fileURL: URL(fileURLWithPath: "/tmp/silent.mp4"),
            videoFormat: nil
        )

        await components.controller.setLocalAudioPreviewMuted(true)

        XCTAssertFalse(components.player.calls.contains(
            .setLocalAudioPreviewMuted(true)
        ))
    }

    func testLocalAudioVolumeIsRetainedBeforeMediaPreparation() async {
        let components = makeComponents(hasAudio: true)

        await components.controller.setLocalAudioVolume(0.7)

        XCTAssertEqual(
            components.player.calls,
            [.setLocalAudioVolume(0.7)]
        )
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
    case setLocalAudioPreviewMuted(Bool)
    case setLocalAudioVolume(Float)
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

    func start() async throws {
        calls.append(.start)
    }

    func setLocalAudioPreviewMuted(_ muted: Bool) {
        calls.append(.setLocalAudioPreviewMuted(muted))
    }

    func setLocalAudioVolume(_ volume: Float) {
        calls.append(.setLocalAudioVolume(volume))
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

    func stop() async {
        calls.append(.stop)
    }
}
