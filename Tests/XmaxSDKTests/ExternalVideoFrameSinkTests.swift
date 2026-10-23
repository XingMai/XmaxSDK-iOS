//
//  ExternalVideoFrameSinkTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import CoreVideo
import XCTest
@testable import XmaxSDK

final class ExternalVideoFrameSinkTests: XCTestCase {
    func testCopiesPixelsAndPreservesTimestamp() throws {
        let recorder = Recorder()
        let sink = makeSink(recorder)
        let buffer = try makeBuffer()
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 42, CVPixelBufferGetBytesPerRow(buffer) * 4)
        CVPixelBufferUnlockBaseAddress(buffer, [])

        sink.pushVideo(buffer, timestamp: CMTime(value: 12345, timescale: 1000))
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetBytesPerRow(buffer) * 4)
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let frame = try XCTUnwrap(recorder.frames.first)
        XCTAssertEqual(frame.timestampUs, 12345000)
        XCTAssertEqual(frame.format.pixelFormat, .bgra)
        XCTAssertEqual(frame.planes.first?.data.first, 42)
        XCTAssertTrue(recorder.errors.isEmpty)
    }

    func testRejectsInvalidAndNonIncreasingTimestamps() throws {
        let recorder = Recorder()
        let sink = makeSink(recorder)
        let buffer = try makeBuffer()
        for time in [CMTime.invalid, .indefinite, .positiveInfinity, CMTime(value: -1, timescale: 1),
                     CMTime(value: 2, timescale: 1), CMTime(value: 2, timescale: 1),
                     CMTime(value: 1, timescale: 1), CMTime(value: 3, timescale: 1)] {
            sink.pushVideo(buffer, timestamp: time)
        }
        XCTAssertEqual(recorder.frames.map(\.timestampUs), [2000000, 3000000])
        XCTAssertTrue(sink.isRequestingFrames)
    }

    func testInvalidationDiscardsFramesAndLateErrors() throws {
        let recorder = Recorder()
        let sink = makeSink(recorder)
        sink.invalidate()
        sink.pushVideo(try makeBuffer(), timestamp: .zero)
        sink.reportError(XmaxError(code: .mediaError, message: "late"))
        XCTAssertFalse(sink.isRequestingFrames)
        XCTAssertTrue(recorder.frames.isEmpty)
        XCTAssertTrue(recorder.errors.isEmpty)
    }

    func testWrongDimensionsFailBindingOnlyOnce() throws {
        let recorder = Recorder()
        let sink = makeSink(recorder)
        sink.pushVideo(try makeBuffer(width: 8), timestamp: .zero)
        sink.pushVideo(try makeBuffer(), timestamp: CMTime(value: 1, timescale: 1))
        sink.reportError(XmaxError(code: .mediaError, message: "again"))
        XCTAssertFalse(sink.isRequestingFrames)
        XCTAssertTrue(recorder.frames.isEmpty)
        XCTAssertEqual(recorder.errors.map(\.code), [.mediaError])
    }

    func testOriginalFramesAreScaledToResolvedMediaSizeForBothPixelFormats() throws {
        for pixelFormat in [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange] {
            let recorder = Recorder()
            let source = RealtimeVideoFormat(width: 8, height: 8, fps: 24)
            let resolved = RealtimeVideoFormat(width: 4, height: 4, fps: 24)
            let sink = makeSink(recorder, sourceFormat: source, resolvedFormat: resolved)
            let buffer = try makeBuffer(width: 8, height: 8, pixelFormat: pixelFormat)
            CVPixelBufferLockBaseAddress(buffer, [])
            if pixelFormat == kCVPixelFormatType_32BGRA {
                memset(CVPixelBufferGetBaseAddress(buffer), 42, CVPixelBufferGetBytesPerRow(buffer) * 8)
            } else {
                memset(CVPixelBufferGetBaseAddressOfPlane(buffer, 0), 64, CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) * 8)
                memset(CVPixelBufferGetBaseAddressOfPlane(buffer, 1), 128, CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * 4)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            sink.pushVideo(buffer, timestamp: CMTime(value: 10, timescale: 1))
            let frame = try XCTUnwrap(recorder.frames.first)
            XCTAssertEqual(frame.format.width, 4)
            XCTAssertEqual(frame.format.height, 4)
            XCTAssertEqual(frame.timestampUs, 10000000)
            XCTAssertEqual(frame.planes[0].data.first, pixelFormat == kCVPixelFormatType_32BGRA ? 42 : 64)
            XCTAssertTrue(recorder.errors.isEmpty)
            XCTAssertTrue(sink.isRequestingFrames)
        }
    }

    func testSubmittingResolvedSizeInsteadOfDeclaredSourceSizeIsRejected() throws {
        let recorder = Recorder()
        let sink = makeSink(
            recorder,
            sourceFormat: RealtimeVideoFormat(width: 8, height: 8, fps: 24)
        )
        sink.pushVideo(try makeBuffer(), timestamp: .zero)
        XCTAssertTrue(recorder.frames.isEmpty)
        XCTAssertEqual(recorder.errors.map(\.code), [.mediaError])
        XCTAssertTrue(recorder.errors[0].message.contains("source.videoFormat"))
    }

    func testUnalignedSourceIsProcessedToFourAlignedSizeWithoutChangingSourceBuffer() throws {
        let recorder = Recorder()
        let source = RealtimeVideoFormat(width: 1282, height: 722, fps: 24)
        let size = try MediaService().resolveMediaSize(source.size, source: .external)
        let resolved = source.resized(width: Int(size.width), height: Int(size.height))
        let sink = makeSink(recorder, sourceFormat: source, resolvedFormat: resolved)
        let buffer = try makeBuffer(width: 1282, height: 722)
        sink.pushVideo(buffer, timestamp: .zero)
        let frame = try XCTUnwrap(recorder.frames.first)
        XCTAssertEqual(frame.format.width, 1280)
        XCTAssertEqual(frame.format.height, 720)
        XCTAssertEqual(CVPixelBufferGetWidth(buffer), 1282)
        XCTAssertEqual(CVPixelBufferGetHeight(buffer), 722)
    }

    func testLargeOriginalNV12FrameUsesModelAreaLimit() throws {
        let recorder = Recorder()
        let source = RealtimeVideoFormat(width: 3840, height: 2160, fps: 60)
        let size = try MediaService().resolveMediaSize(source.size, source: .external)
        let resolved = source.resized(width: Int(size.width), height: Int(size.height))
        let sink = makeSink(recorder, sourceFormat: source, resolvedFormat: resolved)
        let buffer = try makeBuffer(width: 3840, height: 2160, pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        sink.pushVideo(buffer, timestamp: .zero)
        let frame = try XCTUnwrap(recorder.frames.first)
        XCTAssertEqual(frame.format.width, 1920)
        XCTAssertEqual(frame.format.height, 1080)
        XCTAssertEqual(sink.videoFormat.fps, 60)
        XCTAssertTrue(recorder.errors.isEmpty)
    }

    func testNV12PlaneCopyAndUnsupportedFullRange() throws {
        let recorder = Recorder()
        let sink = makeSink(recorder)
        let nv12 = try makeBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        sink.pushVideo(nv12, timestamp: .zero)
        XCTAssertEqual(recorder.frames.first?.format.pixelFormat, .nv12)
        XCTAssertEqual(recorder.frames.first?.planes.count, 2)
        let fullRange = try makeBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        sink.pushVideo(fullRange, timestamp: CMTime(value: 1, timescale: 1))
        XCTAssertEqual(recorder.errors.count, 1)
    }

    func testFailureReportedBySourceEndsBinding() {
        let recorder = Recorder()
        let sink = makeSink(recorder)
        sink.reportError(XmaxError(code: .mediaError, message: "Capture stopped"))
        XCTAssertFalse(sink.isRequestingFrames)
        XCTAssertEqual(recorder.errors.count, 1)
    }

    private func makeBuffer(width: Int = 4, height: Int = 4, pixelFormat: OSType = kCVPixelFormatType_32BGRA) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, width, height, pixelFormat, nil, &buffer), kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    private func makeSink(
        _ recorder: Recorder,
        sourceFormat: RealtimeVideoFormat = RealtimeVideoFormat(width: 4, height: 4, fps: 24),
        resolvedFormat: RealtimeVideoFormat = RealtimeVideoFormat(width: 4, height: 4, fps: 24)
    ) -> ExternalVideoFrameSink {
        ExternalVideoFrameSink(
            sourceVideoFormat: sourceFormat,
            videoFormat: resolvedFormat,
            frameListener: { recorder.append($0) },
            errorListener: { recorder.append($0) }
        )
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storedFrames: [VideoFrame] = []
        private var storedErrors: [XmaxError] = []
        var frames: [VideoFrame] { lock.withLock { storedFrames } }
        var errors: [XmaxError] { lock.withLock { storedErrors } }
        func append(_ frame: VideoFrame) { lock.withLock { storedFrames.append(frame) } }
        func append(_ error: XmaxError) { lock.withLock { storedErrors.append(error) } }
    }
}
