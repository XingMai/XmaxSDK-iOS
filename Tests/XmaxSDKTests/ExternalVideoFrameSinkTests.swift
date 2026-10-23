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

    private func makeBuffer(width: Int = 4, pixelFormat: OSType = kCVPixelFormatType_32BGRA) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, width, 4, pixelFormat, nil, &buffer), kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    private func makeSink(_ recorder: Recorder) -> ExternalVideoFrameSink {
        ExternalVideoFrameSink(
            videoFormat: RealtimeVideoFormat(width: 4, height: 4, fps: 24),
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
