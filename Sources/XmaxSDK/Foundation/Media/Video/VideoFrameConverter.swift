//
//  VideoFrameConverter.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Accelerate
import CoreVideo
import Foundation

/// Processes camera, decoder, and external pixel buffers to resolved media dimensions.
enum VideoFrameConverter {

    /// Center-crops, scales, and rotates pixels to the requested display dimensions.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The source NV12 or BGRA buffer.
    ///   - outputWidth: The positive, even output width, in pixels.
    ///   - outputHeight: The positive, even output height, in pixels.
    ///   - rotation: The display rotation applied after scaling.
    ///   - timestampUs: The output timestamp, in microseconds.
    ///
    /// - Returns: An independently owned frame retaining the input pixel format, with rotation
    ///   applied to pixels.
    ///
    /// - Throws: An error if the format, planes, or dimensions are invalid or conversion fails.
    static func convert(
        pixelBuffer: CVPixelBuffer,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        timestampUs: Int64
    ) throws -> VideoFrame {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if pixelFormat == kCVPixelFormatType_32BGRA {
            return try convertBGRA(
                pixelBuffer,
                outputWidth: outputWidth,
                outputHeight: outputHeight,
                rotation: rotation,
                timestampUs: timestampUs
            )
        }
        let isNV12 =
            pixelFormat
            == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            || pixelFormat
                == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        guard isNV12,
            CVPixelBufferGetPlaneCount(pixelBuffer) == 2
        else {
            throw mediaError("Video decoder returned a non-NV12 frame")
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0,
            height > 0,
            width.isMultiple(of: 2),
            height.isMultiple(of: 2),
            outputWidth > 0,
            outputHeight > 0,
            outputWidth.isMultiple(of: 2),
            outputHeight.isMultiple(of: 2),
            CVPixelBufferGetWidthOfPlane(
                pixelBuffer,
                0
            ) >= width,
            CVPixelBufferGetHeightOfPlane(
                pixelBuffer,
                0
            ) >= height,
            CVPixelBufferGetWidthOfPlane(
                pixelBuffer,
                1
            ) >= width / 2,
            CVPixelBufferGetHeightOfPlane(
                pixelBuffer,
                1
            ) >= height / 2
        else {
            throw mediaError("Decoded NV12 video dimensions are invalid")
        }

        let lockStatus = CVPixelBufferLockBaseAddress(
            pixelBuffer,
            .readOnly
        )
        guard lockStatus == kCVReturnSuccess else {
            throw mediaError("Failed to lock decoded NV12 video data")
        }
        defer {
            CVPixelBufferUnlockBaseAddress(
                pixelBuffer,
                .readOnly
            )
        }

        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(
            pixelBuffer,
            0
        )
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(
            pixelBuffer,
            1
        )
        guard lumaStride >= width,
            chromaStride >= width,
            let lumaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(
                pixelBuffer,
                0
            ),
            let chromaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(
                pixelBuffer,
                1
            )
        else {
            throw mediaError("Decoded NV12 video plane layout is invalid")
        }

        let scaledDimensions = scaledDimensions(
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            rotation: rotation
        )
        let crop = centerCrop(
            sourceWidth: width,
            sourceHeight: height,
            targetWidth: scaledDimensions.width,
            targetHeight: scaledDimensions.height
        )
        let scaledData = try scale(
            lumaBaseAddress: lumaBaseAddress,
            lumaStride: lumaStride,
            chromaBaseAddress: chromaBaseAddress,
            chromaStride: chromaStride,
            crop: crop,
            outputWidth: scaledDimensions.width,
            outputHeight: scaledDimensions.height
        )
        let data = try rotate(
            scaledData,
            sourceWidth: scaledDimensions.width,
            sourceHeight: scaledDimensions.height,
            rotation: rotation
        )
        let lumaLength = outputWidth * outputHeight

        return try VideoFrame(
            format: VideoFormat(
                width: outputWidth,
                height: outputHeight,
                pixelFormat: .nv12
            ),
            timestampUs: timestampUs,
            planes: [
                VideoFramePlane(
                    data: data,
                    stride: outputWidth,
                    byteLength: lumaLength
                ),
                VideoFramePlane(
                    data: data,
                    stride: outputWidth,
                    byteOffset: lumaLength,
                    byteLength: lumaLength / 2
                )
            ],
            rotation: .rotation0
        )
    }

    /// Creates a cropped and scaled frame from BGRA pixels.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The BGRA pixel buffer.
    ///   - outputWidth: The final display width.
    ///   - outputHeight: The final display height.
    ///   - rotation: The rotation applied after scaling.
    ///   - timestampUs: The monotonic timestamp, in microseconds.
    ///
    /// - Returns: A frame owning the processed BGRA pixels.
    ///
    /// - Throws: An error if dimensions or buffer layout are invalid or pixel processing fails.
    private static func convertBGRA(
        _ pixelBuffer: CVPixelBuffer,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        timestampUs: Int64
    ) throws -> VideoFrame {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let (sourceRowBytes, sourceOverflow) = width.multipliedReportingOverflow(by: 4)
        let (outputPixels, pixelOverflow) = outputWidth.multipliedReportingOverflow(
            by: outputHeight
        )
        let (byteCount, byteOverflow) = outputPixels.multipliedReportingOverflow(by: 4)
        guard width > 0, height > 0, outputWidth > 0, outputHeight > 0,
            outputWidth.isMultiple(of: 2), outputHeight.isMultiple(of: 2),
            !sourceOverflow, !pixelOverflow, !byteOverflow,
            CVPixelBufferGetBytesPerRow(pixelBuffer) >= sourceRowBytes,
            CVPixelBufferLockBaseAddress(
                pixelBuffer,
                .readOnly
            ) == kCVReturnSuccess
        else {
            throw mediaError("Invalid BGRA video dimensions or buffer layout")
        }
        defer {
            CVPixelBufferUnlockBaseAddress(
                pixelBuffer,
                .readOnly
            )
        }
        guard let source = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw mediaError("BGRA video pixels are unavailable")
        }

        let dimensions = scaledDimensions(
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            rotation: rotation
        )
        let crop = centerCrop(
            sourceWidth: width,
            sourceHeight: height,
            targetWidth: dimensions.width,
            targetHeight: dimensions.height
        )
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let start = source.advanced(by: crop.y * stride + crop.x * 4)
        var data = Data(count: byteCount)
        try data.withUnsafeMutableBytes { bytes in
            guard let destination = bytes.baseAddress else {
                throw mediaError("Failed to allocate BGRA video data")
            }
            let rowBytes = dimensions.width * 4
            if crop.width == dimensions.width, crop.height == dimensions.height {
                for row in 0..<dimensions.height {
                    memcpy(
                        destination.advanced(by: row * rowBytes),
                        start.advanced(by: row * stride),
                        rowBytes
                    )
                }
                return
            }

            var input = vImage_Buffer(
                data: start,
                height: vImagePixelCount(crop.height),
                width: vImagePixelCount(crop.width),
                rowBytes: stride
            )
            var output = vImage_Buffer(
                data: destination,
                height: vImagePixelCount(dimensions.height),
                width: vImagePixelCount(dimensions.width),
                rowBytes: rowBytes
            )
            guard
                vImageScale_ARGB8888(
                    &input,
                    &output,
                    nil,
                    vImage_Flags(kvImageHighQualityResampling)
                ) == kvImageNoError
            else {
                throw mediaError("Failed to scale BGRA video pixels")
            }
        }

        if rotation != .rotation0 {
            var rotated = Data(count: byteCount)
            try data.withUnsafeBytes { sourceBytes in
                try rotated.withUnsafeMutableBytes { destinationBytes in
                    guard let source = sourceBytes.baseAddress,
                        let destination = destinationBytes.baseAddress
                    else {
                        throw mediaError("Failed to allocate rotated BGRA video data")
                    }
                    var input = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: source),
                        height: vImagePixelCount(dimensions.height),
                        width: vImagePixelCount(dimensions.width),
                        rowBytes: dimensions.width * 4
                    )
                    var output = vImage_Buffer(
                        data: destination,
                        height: vImagePixelCount(outputHeight),
                        width: vImagePixelCount(outputWidth),
                        rowBytes: outputWidth * 4
                    )
                    var background: Pixel_8888 = (0, 0, 0, 0)
                    guard
                        vImageRotate90_ARGB8888(
                            &input,
                            &output,
                            rotationConstant(for: rotation),
                            &background,
                            vImage_Flags(kvImageNoFlags)
                        ) == kvImageNoError
                    else {
                        throw mediaError("Failed to rotate BGRA video pixels")
                    }
                }
            }
            data = rotated
        }

        return try VideoFrame(
            format: VideoFormat(
                width: outputWidth,
                height: outputHeight,
                pixelFormat: .bgra
            ),
            timestampUs: timestampUs,
            planes: [
                VideoFramePlane(
                    data: data,
                    stride: outputWidth * 4
                )
            ]
        )
    }

    /// Crops and scales the NV12 luma and chroma planes.
    ///
    /// - Parameters:
    ///   - lumaBaseAddress: The source luma address.
    ///   - lumaStride: The source luma row stride.
    ///   - chromaBaseAddress: The source chroma address.
    ///   - chromaStride: The source chroma row stride.
    ///   - crop: The even-aligned crop rectangle in source coordinates.
    ///   - outputWidth: The scaled width, in pixels.
    ///   - outputHeight: The scaled height, in pixels.
    ///
    /// - Returns: Contiguous NV12 luma and chroma data.
    ///
    /// - Throws: An error if allocation or plane scaling fails.
    private static func scale(
        lumaBaseAddress: UnsafeMutableRawPointer,
        lumaStride: Int,
        chromaBaseAddress: UnsafeMutableRawPointer,
        chromaStride: Int,
        crop: (x: Int, y: Int, width: Int, height: Int),
        outputWidth: Int,
        outputHeight: Int
    ) throws -> Data {
        let lumaLength = outputWidth * outputHeight
        var data = Data(count: lumaLength + lumaLength / 2)
        try data.withUnsafeMutableBytes { bytes in
            guard let destination = bytes.baseAddress else {
                throw mediaError("Failed to allocate decoded NV12 video data")
            }

            if crop.width == outputWidth, crop.height == outputHeight {
                let luma = lumaBaseAddress.advanced(by: crop.y * lumaStride + crop.x)
                let chroma = chromaBaseAddress.advanced(by: crop.y / 2 * chromaStride + crop.x)
                for row in 0..<outputHeight {
                    memcpy(
                        destination.advanced(by: row * outputWidth),
                        luma.advanced(by: row * lumaStride),
                        outputWidth
                    )
                }
                for row in 0..<(outputHeight / 2) {
                    memcpy(
                        destination.advanced(by: lumaLength + row * outputWidth),
                        chroma.advanced(by: row * chromaStride),
                        outputWidth
                    )
                }
                return
            }

            var sourceLuma = vImage_Buffer(
                data: lumaBaseAddress.advanced(
                    by: crop.y * lumaStride + crop.x
                ),
                height: vImagePixelCount(crop.height),
                width: vImagePixelCount(crop.width),
                rowBytes: lumaStride
            )
            var targetLuma = vImage_Buffer(
                data: destination,
                height: vImagePixelCount(outputHeight),
                width: vImagePixelCount(outputWidth),
                rowBytes: outputWidth
            )
            let flags = vImage_Flags(kvImageHighQualityResampling)
            guard
                vImageScale_Planar8(
                    &sourceLuma,
                    &targetLuma,
                    nil,
                    flags
                ) == kvImageNoError
            else {
                throw mediaError("Failed to scale decoded NV12 luma data")
            }

            var sourceChroma = vImage_Buffer(
                data: chromaBaseAddress.advanced(
                    by: crop.y / 2 * chromaStride + crop.x
                ),
                height: vImagePixelCount(crop.height / 2),
                width: vImagePixelCount(crop.width / 2),
                rowBytes: chromaStride
            )
            var targetChroma = vImage_Buffer(
                data: destination.advanced(by: lumaLength),
                height: vImagePixelCount(outputHeight / 2),
                width: vImagePixelCount(outputWidth / 2),
                rowBytes: outputWidth
            )
            guard
                vImageScale_CbCr8(
                    &sourceChroma,
                    &targetChroma,
                    nil,
                    flags
                ) == kvImageNoError
            else {
                throw mediaError("Failed to scale decoded NV12 chroma data")
            }
        }
        return data
    }

    /// Rotates contiguous NV12 pixels.
    ///
    /// - Parameters:
    ///   - data: The source NV12 data.
    ///   - sourceWidth: The source width, in pixels.
    ///   - sourceHeight: The source height, in pixels.
    ///   - rotation: The rotation to apply.
    ///
    /// - Returns: The rotated NV12 data, or the source data for zero rotation.
    ///
    /// - Throws: An error if allocation or plane rotation fails.
    private static func rotate(
        _ data: Data,
        sourceWidth: Int,
        sourceHeight: Int,
        rotation: VideoRotation
    ) throws -> Data {
        guard rotation != .rotation0 else {
            return data
        }

        let swapsDimensions =
            rotation == .rotation90
            || rotation == .rotation270
        let outputWidth = swapsDimensions ? sourceHeight : sourceWidth
        let outputHeight = swapsDimensions ? sourceWidth : sourceHeight
        let sourceLumaLength = sourceWidth * sourceHeight
        let outputLumaLength = outputWidth * outputHeight
        var output = Data(count: outputLumaLength + outputLumaLength / 2)

        try data.withUnsafeBytes { sourceBytes in
            try output.withUnsafeMutableBytes { outputBytes in
                guard let source = sourceBytes.baseAddress,
                    let destination = outputBytes.baseAddress
                else {
                    throw mediaError(
                        "Failed to allocate rotated NV12 video data"
                    )
                }

                let rotationConstant = rotationConstant(for: rotation)
                var sourceLuma = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: source),
                    height: vImagePixelCount(sourceHeight),
                    width: vImagePixelCount(sourceWidth),
                    rowBytes: sourceWidth
                )
                var targetLuma = vImage_Buffer(
                    data: destination,
                    height: vImagePixelCount(outputHeight),
                    width: vImagePixelCount(outputWidth),
                    rowBytes: outputWidth
                )
                guard
                    vImageRotate90_Planar8(
                        &sourceLuma,
                        &targetLuma,
                        rotationConstant,
                        0,
                        vImage_Flags(kvImageNoFlags)
                    ) == kvImageNoError
                else {
                    throw mediaError("Failed to rotate decoded NV12 luma data")
                }

                var sourceChroma = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: source).advanced(
                        by: sourceLumaLength
                    ),
                    height: vImagePixelCount(sourceHeight / 2),
                    width: vImagePixelCount(sourceWidth / 2),
                    rowBytes: sourceWidth
                )
                var targetChroma = vImage_Buffer(
                    data: destination.advanced(by: outputLumaLength),
                    height: vImagePixelCount(outputHeight / 2),
                    width: vImagePixelCount(outputWidth / 2),
                    rowBytes: outputWidth
                )
                guard
                    vImageRotate90_Planar16U(
                        &sourceChroma,
                        &targetChroma,
                        rotationConstant,
                        0,
                        vImage_Flags(kvImageNoFlags)
                    ) == kvImageNoError
                else {
                    throw mediaError(
                        "Failed to rotate decoded NV12 chroma data"
                    )
                }
            }
        }
        return output
    }

    /// Resolves scaled dimensions before rotation.
    ///
    /// - Parameters:
    ///   - outputWidth: The final display width.
    ///   - outputHeight: The final display height.
    ///   - rotation: The rotation applied after scaling.
    ///
    /// - Returns: The width and height before rotation.
    private static func scaledDimensions(
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation
    ) -> (width: Int, height: Int) {
        switch rotation {
        case .rotation90, .rotation270:
            (outputHeight, outputWidth)
        case .rotation0, .rotation180:
            (outputWidth, outputHeight)
        }
    }

    /// Converts a display rotation to a vImage quarter-turn constant.
    ///
    /// - Parameter rotation: The video display rotation.
    ///
    /// - Returns: The vImage rotation constant.
    private static func rotationConstant(
        for rotation: VideoRotation
    ) -> UInt8 {
        switch rotation {
        case .rotation0:
            0
        case .rotation90:
            3
        case .rotation180:
            2
        case .rotation270:
            1
        }
    }

    /// Resolves a centered crop matching the target aspect ratio.
    ///
    /// - Parameters:
    ///   - sourceWidth: The source width.
    ///   - sourceHeight: The source height.
    ///   - targetWidth: The target width.
    ///   - targetHeight: The target height.
    ///
    /// - Returns: A crop rectangle with even-aligned origin and dimensions for NV12.
    private static func centerCrop(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) -> (x: Int, y: Int, width: Int, height: Int) {
        let sourceAspectRatio = Double(sourceWidth) / Double(sourceHeight)
        let targetAspectRatio = Double(targetWidth) / Double(targetHeight)
        var cropWidth = sourceWidth
        var cropHeight = sourceHeight

        if sourceAspectRatio > targetAspectRatio {
            cropWidth = evenFloor(
                Double(sourceHeight) * targetAspectRatio
            )
        } else if sourceAspectRatio < targetAspectRatio {
            cropHeight = evenFloor(
                Double(sourceWidth) / targetAspectRatio
            )
        }

        return (
            x: evenOffset(Double(sourceWidth - cropWidth) / 2),
            y: evenOffset(Double(sourceHeight - cropHeight) / 2),
            width: cropWidth,
            height: cropHeight
        )
    }

    /// Rounds down to an even dimension of at least two pixels.
    ///
    /// - Parameter value: The dimension to align.
    ///
    /// - Returns: An even dimension of at least 2.
    private static func evenFloor(
        _ value: Double
    ) -> Int {
        max(
            Int(floor(value)) / 2 * 2,
            2
        )
    }

    /// Rounds down to a nonnegative, even offset.
    ///
    /// - Parameter value: The offset to align.
    ///
    /// - Returns: A nonnegative, even offset.
    private static func evenOffset(
        _ value: Double
    ) -> Int {
        max(
            Int(floor(value)) / 2 * 2,
            0
        )
    }

    /// Creates a video conversion error.
    ///
    /// - Parameter message: The error description.
    ///
    /// - Returns: A media error with the specified description.
    private static func mediaError(
        _ message: String
    ) -> XmaxError {
        XmaxError(
            code: .mediaError,
            message: message
        )
    }
}
