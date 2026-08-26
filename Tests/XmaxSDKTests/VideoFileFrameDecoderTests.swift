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
            outputWidth: 4,
            outputHeight: 4,
            rotation: .rotation0,
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

    func testConverterCenterCropsToTargetAspectRatio() throws {
        let pixelBuffer = try makeNV12PixelBuffer(width: 8, height: 4)
        try fillNV12PixelBufferWithColumns(pixelBuffer)

        let frame = try NV12VideoFrameConverter.convert(
            pixelBuffer: pixelBuffer,
            outputWidth: 4,
            outputHeight: 4,
            rotation: .rotation0,
            timestampUs: 84_000
        )

        XCTAssertEqual(frame.format.width, 4)
        XCTAssertEqual(frame.format.height, 4)
        XCTAssertEqual(frame.planes.map(\.stride), [4, 4])
        XCTAssertEqual(
            frame.planes[0].data,
            Data([
                3, 4, 5, 6,
                3, 4, 5, 6,
                3, 4, 5, 6,
                3, 4, 5, 6,
                21, 22, 31, 32,
                21, 22, 31, 32
            ])
        )
    }

    func testConverterPhysicallyRotatesFrameClockwise() throws {
        let pixelBuffer = try makeNV12PixelBuffer(width: 4, height: 2)
        try fillNV12PixelBufferWithSequentialLuma(pixelBuffer)

        let frame = try NV12VideoFrameConverter.convert(
            pixelBuffer: pixelBuffer,
            outputWidth: 2,
            outputHeight: 4,
            rotation: .rotation90,
            timestampUs: 126_000
        )

        XCTAssertEqual(frame.format.width, 2)
        XCTAssertEqual(frame.format.height, 4)
        XCTAssertEqual(frame.rotation, .rotation0)
        XCTAssertEqual(frame.planes.map(\.stride), [2, 2])
        XCTAssertEqual(
            frame.planes[0].data,
            Data([
                5, 1,
                6, 2,
                7, 3,
                8, 4,
                11, 12,
                21, 22
            ])
        )
    }

    func testDecoderRejectsMissingFile() async {
        do {
            _ = try await VideoFileFrameDecoder(
                fileURL: URL(fileURLWithPath: "/missing/video.mov"),
                outputWidth: 832,
                outputHeight: 1_472,
                rotation: .rotation0,
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

    private func fillNV12PixelBufferWithColumns(
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
            let destination = lumaBaseAddress.assumingMemoryBound(to: UInt8.self)
                .advanced(by: row * lumaStride)
            for column in 0..<width {
                destination[column] = UInt8(column + 1)
            }
        }
        for row in 0..<(height / 2) {
            let destination = chromaBaseAddress
                .assumingMemoryBound(to: UInt8.self)
                .advanced(by: row * chromaStride)
            for column in stride(from: 0, to: width, by: 2) {
                let pair = column / 2 + 1
                destination[column] = UInt8(pair * 10 + 1)
                destination[column + 1] = UInt8(pair * 10 + 2)
            }
        }
    }

    private func fillNV12PixelBufferWithSequentialLuma(
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
            let destination = lumaBaseAddress.assumingMemoryBound(to: UInt8.self)
                .advanced(by: row * lumaStride)
            for column in 0..<width {
                destination[column] = UInt8(row * width + column + 1)
            }
        }
        let chroma = chromaBaseAddress.assumingMemoryBound(to: UInt8.self)
        chroma[0] = 11
        chroma[1] = 12
        chroma[2] = 21
        chroma[3] = 22
        XCTAssertGreaterThanOrEqual(chromaStride, width)
    }
}
