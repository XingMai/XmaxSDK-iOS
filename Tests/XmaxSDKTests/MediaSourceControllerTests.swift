//
//  MediaSourceControllerTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics
import Foundation
import UIKit
import XCTest
@testable import XmaxSDK

@MainActor
final class MediaSourceControllerTests: XCTestCase {
    func testSourceSizeAndModelDefaultFrameRateAreIndependentOfBuckets() async throws {
        let components = makeComponents(hasAudio: false, model: .x2_1_1_preview_cn)
        let fileURL = URL(fileURLWithPath: "/tmp/source.mp4")
        let defaultConfiguration = try await components.controller.prepare(
            fileURL: fileURL
        )
        XCTAssertEqual(defaultConfiguration.videoFormat.fps, RealtimeModel.x2_1_1_preview_cn.defaultFrameRate)
        await components.controller.stop()
        XCTAssertEqual(defaultConfiguration.videoFormat, RealtimeVideoFormat(width: 1080, height: 1920, fps: 30))
        XCTAssertTrue(components.mediaService.requestedSizes.isEmpty)
    }

    func testPrepareResolvesRotatedSizeAndPreservesMetadataDuration() async throws {
        let components = makeComponents(hasAudio: true)
        let fileURL = URL(fileURLWithPath: "/tmp/source.mp4")

        let configuration = try await components.controller.prepare(
            fileURL: fileURL
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
            []
        )
        XCTAssertEqual(components.player.calls, [
            .configure(
                fileURL: fileURL,
                outputWidth: 1080,
                outputHeight: 1920,
                rotation: .rotation90,
                frameRate: 30,
                hasAudio: true,
                durationSeconds: 2.0000001
            )
        ])
        XCTAssertTrue(components.controller.hasAudio)
    }

    func testStartBeforePrepareIsRejected() async {
        let components = makeComponents(hasAudio: false)

        do {
            try await components.controller.start()
            XCTFail("Starting an unprepared source should fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
        }

        XCTAssertTrue(components.player.calls.isEmpty)
    }

    func testRepeatedPrepareAndStartAreRejectedUntilStopped() async throws {
        let components = makeComponents(hasAudio: true)
        let fileURL = URL(fileURLWithPath: "/tmp/source.mp4")
        _ = try await components.controller.prepare(fileURL: fileURL)
        try await components.controller.start()
        let calls = components.player.calls

        do {
            _ = try await components.controller.prepare(fileURL: fileURL)
            XCTFail("Preparing an active source should fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
        }

        do {
            try await components.controller.start()
            XCTFail("Starting an active source should fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
        }
        XCTAssertEqual(components.player.calls, calls)

        await components.controller.stop()
        XCTAssertFalse(components.controller.hasAudio)
        _ = try await components.controller.prepare(fileURL: fileURL)
        try await components.controller.start()

        XCTAssertTrue(components.controller.hasAudio)
        XCTAssertEqual(components.player.calls.filter { $0 == .start }.count, 2)
        await components.controller.stop()
    }

    func testStartAndStopUseSinglePlayerTimeline() async throws {
        let components = makeComponents(hasAudio: true)
        _ = try await components.controller.prepare(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4")
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
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4")
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
            fileURL: URL(fileURLWithPath: "/tmp/silent.mp4")
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
        RealtimeVideoFormat(width: 1080, height: 1920, fps: 30)
    }

    func makeComponents(hasAudio: Bool, model: RealtimeModel = .x2_1_1_preview_cn) -> Components {
        let metadataManager = MediaFileMetadataManagingStub(
            metadata: MediaFileMetadata(
                width: 1_920,
                height: 1_080,
                rotation: .rotation90,
                durationSeconds: 2.0000001,
                hasAudio: hasAudio
            )
        )
        let mediaService = MediaServicingStub(
            resolvedSize: CGSize(width: 832, height: 1_472),
            model: model
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
        hasAudio: Bool,
        durationSeconds: Double
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
    private(set) var localAudioVolume: Float = 0.45

    func configure(
        fileURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        frameRate: Int,
        hasAudio: Bool,
        durationSeconds: Double
    ) throws {
        calls.append(.configure(
            fileURL: fileURL,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            rotation: rotation,
            frameRate: frameRate,
            hasAudio: hasAudio,
            durationSeconds: durationSeconds
        ))
    }

    func start() async throws {
        calls.append(.start)
    }

    func setLocalAudioPreviewMuted(_ muted: Bool) {
        calls.append(.setLocalAudioPreviewMuted(muted))
    }

    func setLocalAudioVolume(_ volume: Float) {
        localAudioVolume = volume
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
