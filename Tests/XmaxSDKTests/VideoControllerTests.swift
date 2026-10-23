//
//  VideoControllerTests.swift
//  XmaxSDK
//  Repo: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import XCTest
@testable import XmaxSDK

@MainActor
final class VideoControllerTests: XCTestCase {
    func testCreateWithAudioStartsExternalAudioAndPreview() async throws {
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
        let fileURL = URL(fileURLWithPath: "/tmp/source.mp4")

        let stream = try await manager.createLocalVideoStream(
            fileURL: fileURL
        )

        XCTAssertEqual(stream.videoTrack?.videoFormat, videoFormat)
        XCTAssertTrue(manager.hasAudio)
        XCTAssertEqual(
            source.calls,
            [.prepare(fileURL), .start]
        )
        XCTAssertTrue(rtcManager.calls.contains(.useExternalVideoSource))
        XCTAssertTrue(rtcManager.calls.contains(.startExternalAudioSource))
        XCTAssertFalse(rtcManager.calls.contains(.startAudioCapture))
        await manager.stopLocalVideoStream()
    }

    func testCreateWithoutAudioDoesNotStartExternalAudio() async throws {
        let rtcManager = RtcManagingStub()
        let source = MediaSourceControllingStub(
            configuration: MediaSourceConfiguration(
                videoFormat: videoFormat,
                hasAudio: false
            )
        )
        let manager = makeManager(
            rtcManager: rtcManager,
            mediaSourceController: source
        )

        _ = try await manager.createLocalVideoStream(
            fileURL: URL(fileURLWithPath: "/tmp/silent.mp4")
        )

        XCTAssertFalse(manager.hasAudio)
        XCTAssertFalse(rtcManager.calls.contains(.startExternalAudioSource))
        XCTAssertFalse(rtcManager.calls.contains(.startAudioCapture))
        await manager.stopLocalVideoStream()
    }

    func testStopForwardsLifecycleAndReleasesAudio() async throws {
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
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4")
        )

        await manager.stopLocalVideoStream()

        XCTAssertEqual(source.calls.last, .stop)
        XCTAssertTrue(rtcManager.calls.contains(.stopExternalAudioSource))
        XCTAssertNil(manager.currentTrack)
    }

}

private extension VideoControllerTests {
    var videoFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 832, height: 1_472, fps: 24)
    }

    func makeManager(
        rtcManager: RtcManagingStub,
        mediaSourceController: MediaSourceControllingStub
    ) -> VideoController {
        VideoController(
            rtcManager: rtcManager,
            mediaSourceController: mediaSourceController
        )
    }
}
