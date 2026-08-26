import CoreVideo
import Foundation
import XCTest
@testable import XmaxSDK

final class VideoFileFrameDecoderTests: XCTestCase {
    func testConverterCompactsPaddedNV12Planes() throws {
        let pixelBuffer = try makeNV12PixelBuffer(width: 4, height: 4)
        try fillNV12PixelBuffer(pixelBuffer)

        let frame = try NV12VideoFrameConverter.convert(
            pixelBuffer: pixelBuffer,
            timestampUs: 42_000
        )

        XCTAssertEqual(frame.format.width, 4)
        XCTAssertEqual(frame.format.height, 4)
        XCTAssertEqual(frame.format.pixelFormat, .nv12)
        XCTAssertEqual(frame.timestampUs, 42_000)
        XCTAssertEqual(frame.planes.map(\.stride), [4, 4])
        XCTAssertEqual(frame.planes.map(\.byteLength), [16, 8])
        let data = try XCTUnwrap(frame.planes.first).data
        XCTAssertEqual(data.count, 24)
        XCTAssertEqual(
            data,
            Data([
                1, 1, 1, 1,
                2, 2, 2, 2,
                3, 3, 3, 3,
                4, 4, 4, 4,
                11, 11, 11, 11,
                12, 12, 12, 12
            ])
        )
    }

    func testDecoderRejectsMissingFile() async {
        do {
            _ = try await VideoFileFrameDecoder(
                fileURL: URL(fileURLWithPath: "/missing/video.mov"),
                onFrame: { _ in },
                onEndOfStream: {},
                onError: { _ in }
            )
            XCTFail("Expected decoder creation to fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .mediaError)
        }
    }

    private func makeNV12PixelBuffer(
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw XmaxError(
                code: .mediaError,
                message: "Failed to create test NV12 pixel buffer"
            )
        }
        return pixelBuffer
    }

    private func fillNV12PixelBuffer(
        _ pixelBuffer: CVPixelBuffer
    ) throws {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, [])
                == kCVReturnSuccess else {
            throw XmaxError(
                code: .mediaError,
                message: "Failed to lock test NV12 pixel buffer"
            )
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        guard let lumaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(
                  pixelBuffer,
                  0
              ),
              let chromaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(
                  pixelBuffer,
                  1
              ) else {
            throw XmaxError(
                code: .mediaError,
                message: "Test NV12 pixel buffer has no plane data"
            )
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        for row in 0..<height {
            memset(
                lumaBaseAddress.advanced(by: row * lumaStride),
                Int32(row + 1),
                width
            )
        }
        for row in 0..<(height / 2) {
            memset(
                chromaBaseAddress.advanced(by: row * chromaStride),
                Int32(row + 11),
                width
            )
        }
    }
}
