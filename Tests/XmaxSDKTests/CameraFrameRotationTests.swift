import CoreVideo
import Foundation
import XCTest
@testable import XmaxSDK

final class CameraFrameRotationTests: XCTestCase {
    func testFixedPortraitFrameRotatesIntoEachWindowOrientation() throws {
        let buffer = try makePortraitBuffer()
        let cases: [(CameraOrientation, [UInt8], [UInt8])] = [
            (.portrait, [1, 2, 3, 4, 5, 6, 7, 8], [101, 201, 102, 202]),
            (.landscapeLeft, [2, 4, 6, 8, 1, 3, 5, 7], [101, 201, 102, 202]),
            (.portraitUpsideDown, [8, 7, 6, 5, 4, 3, 2, 1], [102, 202, 101, 201]),
            (.landscapeRight, [7, 5, 3, 1, 8, 6, 4, 2], [102, 202, 101, 201])
        ]

        // 重复切换使用同一个采集基准，不对上一帧的方向累加旋转。
        for _ in 0..<3 {
            for (orientation, luma, chroma) in cases {
                let frame = try NV12VideoFrameConverter.convert(
                    pixelBuffer: buffer,
                    outputWidth: orientation.isLandscape ? 4 : 2,
                    outputHeight: orientation.isLandscape ? 2 : 4,
                    rotation: orientation.frameRotation,
                    timestampUs: 123
                )

                XCTAssertEqual(frame.format.width, orientation.isLandscape ? 4 : 2)
                XCTAssertEqual(frame.format.height, orientation.isLandscape ? 2 : 4)
                XCTAssertEqual(frame.planes[0].data, Data(luma + chroma), "\(orientation)")
                XCTAssertEqual(frame.planes[1].byteOffset, 8)
                XCTAssertEqual(frame.planes[1].byteLength, 4)
                XCTAssertEqual(frame.rotation, .rotation0)
                XCTAssertEqual(frame.timestampUs, 123)
            }
        }
    }

    func testRotationPreservesModelBucketDimensions() throws {
        let buffer = try makePortraitBuffer()

        for orientation in [CameraOrientation.portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown] {
            let frame = try NV12VideoFrameConverter.convert(
                pixelBuffer: buffer,
                outputWidth: orientation.isLandscape ? 1920 : 1024,
                outputHeight: orientation.isLandscape ? 1024 : 1920,
                rotation: orientation.frameRotation,
                timestampUs: 456
            )

            XCTAssertEqual(frame.format.width, orientation.isLandscape ? 1920 : 1024)
            XCTAssertEqual(frame.format.height, orientation.isLandscape ? 1024 : 1920)
            XCTAssertEqual(frame.planes[0].byteLength, 1024 * 1920)
            XCTAssertEqual(frame.planes[1].byteLength, 1024 * 1920 / 2)
            XCTAssertEqual(frame.rotation, .rotation0)
        }
    }
}

private extension CameraFrameRotationTests {
    func makePortraitBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, 2, 4,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            nil, &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)
        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        XCTAssertEqual(lockStatus, kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let luma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0))
            .assumingMemoryBound(to: UInt8.self)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        for row in 0..<4 {
            luma[row * lumaStride] = UInt8(row * 2 + 1)
            luma[row * lumaStride + 1] = UInt8(row * 2 + 2)
        }

        let chroma = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1))
            .assumingMemoryBound(to: UInt8.self)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        for row in 0..<2 {
            chroma[row * chromaStride] = UInt8(101 + row)
            chroma[row * chromaStride + 1] = UInt8(201 + row)
        }

        return pixelBuffer
    }
}
