//
//  RemoteVideoFramePipelineTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import CoreVideo
import XCTest
@testable import XmaxSDK

final class RemoteVideoFramePipelineTests: XCTestCase {
    func testResetWaitsForSessionCloseAndInFlightProcessing() async throws {
        try await verifyResetDuringProcessing(failsProcessing: false)
    }

    func testLateInterpolationFailureDoesNotDisableNewGeneration() async throws {
        try await verifyResetDuringProcessing(failsProcessing: true)
    }

    func testEnablingInterpolationPassesThroughOldSizeUntilTargetArrives() async throws {
        let recorder = RealtimeVideoFrameRecorder()
        let target = CGSize(width: 702, height: 1242)
        let pipeline = RemoteVideoFramePipeline(
            interpolationEnabled: false,
            outputToken: 0,
            frameInterpolationSupportChecker: { $0 == target },
            outputListener: { frame, token in
                await recorder.record(frame, token: token)
            },
            errorListener: { _ in XCTFail("Old size is not an interpolation failure") }
        )
        try await pipeline.setFrameInterpolationEnabled(true, videoSize: target, outputToken: 0)
        let oldBuffer = try makePixelBuffer(width: 832, height: 1472)
        await pipeline.enqueue(RealtimeVideoFrame(pixelBuffer: oldBuffer, presentationTimeStamp: .zero))
        let output = try await waitForOutput(recorder)
        XCTAssertTrue(output.frame.pixelBuffer === oldBuffer)
        let enabled = await pipeline.isFrameInterpolationEnabled
        XCTAssertTrue(enabled)
        try await pipeline.setFrameInterpolationEnabled(false, videoSize: nil, outputToken: 0)
    }

    func testOversizedReceivedFrameDisablesInterpolationAndStillDisplays() async throws {
        let recorder = RealtimeVideoFrameRecorder()
        let reportedError = expectation(description: "Unsupported received size")
        let pipeline = RemoteVideoFramePipeline(
            interpolationEnabled: true,
            outputToken: 0,
            frameInterpolationSupportChecker: { MediaService.supportsFrameInterpolationSize($0) },
            outputListener: { frame, token in
                await recorder.record(frame, token: token)
            },
            errorListener: { error in
                XCTAssertEqual(error.code, .frameInterpolationUnsupported)
                reportedError.fulfill()
            }
        )
        let pixelBuffer = try makePixelBuffer(width: 832, height: 1472)
        await pipeline.enqueue(RealtimeVideoFrame(
            pixelBuffer: pixelBuffer,
            presentationTimeStamp: .zero
        ))
        await fulfillment(of: [reportedError], timeout: 2)
        let output = try await waitForOutput(recorder)
        XCTAssertTrue(output.frame.pixelBuffer === pixelBuffer)
        let enabled = await pipeline.isFrameInterpolationEnabled
        XCTAssertFalse(enabled)
    }

    func testDisabledPipelinePassesThroughRemoteFrame() async throws {
        let recorder = RealtimeVideoFrameRecorder()
        let token: UInt64 = 0
        let pipeline = RemoteVideoFramePipeline(
            interpolationEnabled: false,
            outputToken: token,
            outputListener: { frame, outputToken in
                await recorder.record(frame, token: outputToken)
            },
            errorListener: { _ in }
        )
        let pixelBuffer = try makePixelBuffer(width: 16, height: 16)

        await pipeline.enqueue(
            RealtimeVideoFrame(
                pixelBuffer: pixelBuffer,
                presentationTimeStamp: .zero
            )
        )

        let output = try await waitForOutput(recorder)
        XCTAssertTrue(output.frame.pixelBuffer === pixelBuffer)
        XCTAssertEqual(output.frame.duration, CMTime(value: 1, timescale: 24))
        XCTAssertEqual(output.token, token)
    }

    func testStaleOutputTokenCannotReplaceCurrentGeneration() async throws {
        let recorder = RealtimeVideoFrameRecorder()
        let pipeline = RemoteVideoFramePipeline(
            interpolationEnabled: false,
            outputToken: 1,
            outputListener: { frame, outputToken in
                await recorder.record(frame, token: outputToken)
            },
            errorListener: { _ in }
        )
        let pixelBuffer = try makePixelBuffer(width: 16, height: 16)
        let frame = RealtimeVideoFrame(
            pixelBuffer: pixelBuffer,
            presentationTimeStamp: .zero
        )

        await pipeline.reset(outputToken: 2)
        await pipeline.reset(outputToken: 1)
        try await pipeline.setFrameInterpolationEnabled(
            false,
            videoSize: nil,
            outputToken: 1
        )
        await pipeline.enqueue(frame, outputToken: 1)
        let staleOutput = await recorder.firstOutput
        XCTAssertNil(staleOutput)

        await pipeline.enqueue(frame, outputToken: 2)
        let output = try await waitForOutput(recorder)
        XCTAssertEqual(output.token, 2)
    }

#if targetEnvironment(simulator)
    func testEnablingInterpolationFailsInSimulator() async throws {
        let pipeline = RemoteVideoFramePipeline(
            interpolationEnabled: false,
            outputToken: 0,
            outputListener: { _, _ in },
            errorListener: { _ in }
        )

        do {
            try await pipeline.setFrameInterpolationEnabled(
                true,
                videoSize: CGSize(width: 704, height: 1_280),
                outputToken: 1
            )
            XCTFail("Expected frame interpolation to be unavailable")
        } catch {
            XCTAssertEqual(
                (error as? XmaxError)?.code,
                .frameInterpolationUnsupported
            )
        }
    }
#endif
}

private actor RealtimeVideoFrameRecorder {
    struct Output: @unchecked Sendable {
        let frame: RealtimeVideoFrame
        let token: UInt64
    }

    private var outputs: [Output] = []

    func record(_ frame: RealtimeVideoFrame, token: UInt64) {
        outputs.append(Output(frame: frame, token: token))
    }

    var firstOutput: Output? {
        outputs.first
    }
}

private extension RemoteVideoFramePipelineTests {
    func verifyResetDuringProcessing(failsProcessing: Bool) async throws {
        let recorder = RealtimeVideoFrameRecorder()
        let processingStarted = expectation(description: "Old frame processing started")
        let closeStarted = expectation(description: "Old session close started")
        let closeFinished = expectation(description: "Old session closed")
        let processingGate = InterpolationTestGate()
        let closeGate = InterpolationTestGate()
        let oldManager = ControlledInterpolationManager(
            processingGate: processingGate,
            closeGate: closeGate,
            failsProcessing: failsProcessing,
            processingStarted: processingStarted,
            closeStarted: closeStarted,
            closeFinished: closeFinished
        )
        let factory = InterpolationTestFactory(firstManager: oldManager)
        let pipeline = RemoteVideoFramePipeline(
            interpolationEnabled: true,
            outputToken: 1,
            frameInterpolationSupportChecker: { _ in true },
            interpolationManagerFactory: { _ in factory.make() },
            outputListener: { frame, token in
                await recorder.record(frame, token: token)
            },
            errorListener: { _ in XCTFail("An old generation must not report errors") }
        )
        let frame = RealtimeVideoFrame(
            pixelBuffer: try makePixelBuffer(width: 16, height: 16),
            presentationTimeStamp: .zero
        )
        await pipeline.enqueue(frame, outputToken: 1)
        await fulfillment(of: [processingStarted], timeout: 2)

        let resetFinished = InterpolationTestFlag()
        let resetting = Task {
            await pipeline.reset(outputToken: 2)
            resetFinished.set()
        }
        await fulfillment(of: [closeStarted], timeout: 2)

        // 新流可以先到达，但必须等待旧会话及其在途帧完整结束。
        await pipeline.enqueue(frame, outputToken: 3)
        let latestReset = Task { await pipeline.reset(outputToken: 3) }
        try await Task.sleep(nanoseconds: 50000000)
        XCTAssertFalse(resetFinished.value)
        XCTAssertEqual(factory.creationCount, 1)

        await closeGate.open()
        await fulfillment(of: [closeFinished], timeout: 2)
        try await Task.sleep(nanoseconds: 50000000)
        XCTAssertFalse(resetFinished.value)
        XCTAssertEqual(factory.creationCount, 1)

        await processingGate.open()
        await resetting.value
        await latestReset.value
        let output = try await waitForOutput(recorder)
        XCTAssertEqual(output.token, 3)
        XCTAssertEqual(factory.creationCount, 2)
        let enabled = await pipeline.isFrameInterpolationEnabled
        XCTAssertTrue(enabled)

        await pipeline.reset(outputToken: 4)
    }

    func makePixelBuffer(
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(pixelBuffer)
    }

    func waitForOutput(
        _ recorder: RealtimeVideoFrameRecorder
    ) async throws -> RealtimeVideoFrameRecorder.Output {
        for _ in 0..<1_000 {
            if let output = await recorder.firstOutput {
                return output
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for a processed video frame")
        throw XmaxError(code: .timeout, message: "Frame output timed out")
    }
}

private actor InterpolationTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor ControlledInterpolationManager: FrameInterpolationManaging {
    private let processingGate: InterpolationTestGate
    private let closeGate: InterpolationTestGate
    private let failsProcessing: Bool
    private let processingStarted: XCTestExpectation
    private let closeStarted: XCTestExpectation
    private let closeFinished: XCTestExpectation

    init(
        processingGate: InterpolationTestGate,
        closeGate: InterpolationTestGate,
        failsProcessing: Bool,
        processingStarted: XCTestExpectation,
        closeStarted: XCTestExpectation,
        closeFinished: XCTestExpectation
    ) {
        self.processingGate = processingGate
        self.closeGate = closeGate
        self.failsProcessing = failsProcessing
        self.processingStarted = processingStarted
        self.closeStarted = closeStarted
        self.closeFinished = closeFinished
    }

    nonisolated func matches(_ frame: RealtimeVideoFrame) -> Bool { true }

    func process(
        _ frame: RealtimeVideoFrame,
        sourceDuration: CMTime
    ) async throws -> [RealtimeVideoFrame] {
        processingStarted.fulfill()
        await processingGate.wait()
        if failsProcessing {
            throw XmaxError(code: .mediaError, message: "Late interpolation failure")
        }
        return [frame]
    }

    func close() async {
        closeStarted.fulfill()
        await closeGate.wait()
        closeFinished.fulfill()
    }
}

private final class PassthroughInterpolationManager: FrameInterpolationManaging {
    func matches(_ frame: RealtimeVideoFrame) -> Bool { true }

    func process(
        _ frame: RealtimeVideoFrame,
        sourceDuration: CMTime
    ) async throws -> [RealtimeVideoFrame] { [frame] }

    func close() async {}
}

private final class InterpolationTestFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let firstManager: any FrameInterpolationManaging
    private var count = 0

    init(firstManager: any FrameInterpolationManaging) {
        self.firstManager = firstManager
    }

    var creationCount: Int { lock.withLock { count } }

    func make() -> any FrameInterpolationManaging {
        lock.withLock {
            count += 1
            return count == 1 ? firstManager : PassthroughInterpolationManager()
        }
    }
}

private final class InterpolationTestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    var value: Bool { lock.withLock { isSet } }

    func set() { lock.withLock { isSet = true } }
}
