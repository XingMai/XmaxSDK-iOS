//
//  ExternalVideoControllerTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import XCTest
@testable import XmaxSDK

@MainActor
final class ExternalVideoControllerTests: XCTestCase {
    func testResolvesSizePreservesSourceFPSAndEncodingWithoutMicrophone() async throws {
        let rtc = RtcManagingStub()
        let controller = makeController(rtc)
        let format = RealtimeVideoFormat(width: 3840, height: 2160, fps: 60, minimumBitrate: 600, maximumBitrate: 3000)
        let source = RealtimeExternalVideoSourceStub(videoFormat: format)
        let stream = try await controller.createExternalVideoStream(source: source)
        let resolved = try XCTUnwrap(source.sink?.videoFormat)
        XCTAssertEqual(resolved.fps, 60)
        XCTAssertEqual(resolved.minimumBitrate, 600)
        XCTAssertEqual(resolved.maximumBitrate, 3000)
        XCTAssertLessThanOrEqual(resolved.width * resolved.height, RealtimeModel.x2_1.maximumInputPixels)
        XCTAssertEqual(resolved.width % 4, 0)
        XCTAssertEqual(resolved.height % 4, 0)
        XCTAssertEqual(stream.videoTrack?.videoFormat, resolved)
        XCTAssertEqual(rtc.calls, [.useExternalVideoSource])
        XCTAssertNotNil(VideoRenderRegistry.binding(for: try XCTUnwrap(stream.videoTrack)))
        await controller.stopExternalVideoStream()
    }

    func testAcceptsNonCameraBucketAndStopInvalidatesOldSink() async throws {
        let controller = makeController()
        let source = RealtimeExternalVideoSourceStub()
        let stream = try await controller.createExternalVideoStream(source: source)
        let oldSink = try XCTUnwrap(source.sink)
        XCTAssertEqual(oldSink.videoFormat, source.videoFormat)
        await controller.stopExternalVideoStream()
        await controller.stopExternalVideoStream()
        XCTAssertFalse(oldSink.isRequestingFrames)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertNil(controller.currentTrack)
        XCTAssertNil(VideoRenderRegistry.binding(for: try XCTUnwrap(stream.videoTrack)))
        _ = try await controller.createExternalVideoStream(source: source)
        XCTAssertTrue(source.sink?.isRequestingFrames == true)
        XCTAssertFalse(oldSink.isRequestingFrames)
        await controller.stopExternalVideoStream()
    }

    func testStartFailureRollsBackAndAllowsRetry() async throws {
        let controller = makeController()
        let source = RealtimeExternalVideoSourceStub()
        source.startHandler = { throw XmaxError(code: .mediaError, message: "start failed") }
        do {
            _ = try await controller.createExternalVideoStream(source: source)
            XCTFail("Expected startup failure")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .mediaError)
        }
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertNil(controller.currentTrack)
        XCTAssertNil(source.sink)
        source.startHandler = nil
        _ = try await controller.createExternalVideoStream(source: source)
        await controller.stopExternalVideoStream()
    }

    func testCancellationDuringStartUnbindsSource() async throws {
        let controller = makeController()
        let source = RealtimeExternalVideoSourceStub()
        source.startHandler = { try await Task.sleep(nanoseconds: 60000000000) }
        let task = Task { try await controller.createExternalVideoStream(source: source) }
        while source.sink == nil { await Task.yield() }
        let sink = try XCTUnwrap(source.sink)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
        }
        XCTAssertFalse(sink.isRequestingFrames)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertNil(controller.currentTrack)
    }

    private func makeController(_ rtc: RtcManagingStub = RtcManagingStub()) -> ExternalVideoController {
        ExternalVideoController(
            rtcManager: rtc,
            mediaService: MediaService(),
            videoFrameListener: { _ in },
            errorListener: { _ in }
        )
    }
}
