import CoreVideo
import Foundation

/// 将系统 NV12 像素缓冲区复制为无行尾填充的连续帧数据。
enum NV12VideoFrameConverter {
    static func convert(
        pixelBuffer: CVPixelBuffer,
        timestampUs: Int64
    ) throws -> VideoFrame {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isNV12 = pixelFormat
            == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || pixelFormat
            == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        guard isNV12,
              CVPixelBufferGetPlaneCount(pixelBuffer) == 2 else {
            throw mediaError("Video decoder returned a non-NV12 frame")
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0,
              height > 0,
              width.isMultiple(of: 2),
              height.isMultiple(of: 2),
              CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) >= width,
              CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) >= height,
              CVPixelBufferGetWidthOfPlane(pixelBuffer, 1) >= width / 2,
              CVPixelBufferGetHeightOfPlane(pixelBuffer, 1) >= height / 2 else {
            throw mediaError("Decoded NV12 video dimensions are invalid")
        }

        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard lockStatus == kCVReturnSuccess else {
            throw mediaError("Failed to lock decoded NV12 video data")
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        guard lumaStride >= width,
              chromaStride >= width,
              let lumaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(
                  pixelBuffer,
                  0
              ),
              let chromaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(
                  pixelBuffer,
                  1
              ) else {
            throw mediaError("Decoded NV12 video plane layout is invalid")
        }

        let lumaLength = width * height
        var data = Data(count: lumaLength + lumaLength / 2)
        try data.withUnsafeMutableBytes { bytes in
            guard let destination = bytes.baseAddress else {
                throw mediaError("Failed to allocate decoded NV12 video data")
            }

            copyRows(
                source: lumaBaseAddress,
                sourceStride: lumaStride,
                destination: destination,
                destinationOffset: 0,
                rowLength: width,
                rowCount: height
            )
            copyRows(
                source: chromaBaseAddress,
                sourceStride: chromaStride,
                destination: destination,
                destinationOffset: lumaLength,
                rowLength: width,
                rowCount: height / 2
            )
        }

        return try VideoFrame(
            format: VideoFormat(
                width: width,
                height: height,
                pixelFormat: .nv12
            ),
            timestampUs: timestampUs,
            planes: [
                VideoFramePlane(
                    data: data,
                    stride: width,
                    byteLength: lumaLength
                ),
                VideoFramePlane(
                    data: data,
                    stride: width,
                    byteOffset: lumaLength,
                    byteLength: lumaLength / 2
                )
            ]
        )
    }

    private static func copyRows(
        source: UnsafeMutableRawPointer,
        sourceStride: Int,
        destination: UnsafeMutableRawPointer,
        destinationOffset: Int,
        rowLength: Int,
        rowCount: Int
    ) {
        for row in 0..<rowCount {
            memcpy(
                destination.advanced(
                    by: destinationOffset + row * rowLength
                ),
                source.advanced(by: row * sourceStride),
                rowLength
            )
        }
    }

    private static func mediaError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
