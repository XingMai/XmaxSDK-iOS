import CoreMedia
import CoreVideo
import XCTest
@testable import XmaxSDK

final class RemoteVideoFramePipelineTests: XCTestCase {
    func testDisabledPipelinePassesThroughRemoteFrame() async throws {
        let recorder = DecodedVideoFrameRecorder()
        let token = UUID()
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
            DecodedVideoFrame(
                pixelBuffer: pixelBuffer,
                presentationTimeStamp: .zero
            )
        )

        let output = try await waitForOutput(recorder)
        XCTAssertTrue(output.frame.pixelBuffer === pixelBuffer)
        XCTAssertEqual(output.frame.duration, CMTime(value: 1, timescale: 24))
        XCTAssertEqual(output.token, token)
    }

#if targetEnvironment(simulator)
    func testEnablingInterpolationFailsInSimulator() async throws {
        let pipeline = RemoteVideoFramePipeline(
            interpolationEnabled: false,
            outputToken: UUID(),
            outputListener: { _, _ in },
            errorListener: { _ in }
        )

        do {
            try await pipeline.setFrameInterpolationEnabled(
                true,
                videoSize: CGSize(width: 704, height: 1_280),
                outputToken: UUID()
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

private actor DecodedVideoFrameRecorder {
    struct Output: @unchecked Sendable {
        let frame: DecodedVideoFrame
        let token: UUID
    }

    private var outputs: [Output] = []

    func record(_ frame: DecodedVideoFrame, token: UUID) {
        outputs.append(Output(frame: frame, token: token))
    }

    var firstOutput: Output? {
        outputs.first
    }
}

private extension RemoteVideoFramePipelineTests {
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
        _ recorder: DecodedVideoFrameRecorder
    ) async throws -> DecodedVideoFrameRecorder.Output {
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
