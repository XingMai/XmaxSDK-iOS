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

/// 将摄像头、解码器及外部源的像素缓冲区处理为统一媒体尺寸的视频帧。
enum VideoFrameConverter {

    /// 将像素缓冲区居中裁剪、缩放并旋转为指定显示尺寸，尺寸匹配时直接复制。
    ///
    /// - Parameters:
    ///   - pixelBuffer: 源 NV12 或 BGRA 像素缓冲区。
    ///   - outputWidth: 输出宽度，单位为像素且须为正偶数。
    ///   - outputHeight: 输出高度，单位为像素且须为正偶数。
    ///   - rotation: 缩放后应用的显示旋转。
    ///   - timestampUs: 输出帧时间戳，单位为微秒。
    /// - Returns: 像素格式与输入一致、旋转已应用到像素数据且独立持有像素的视频帧。
    /// - Throws: 像素格式、平面布局或尺寸无效，以及缓冲区转换失败时抛出错误。
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
              outputWidth > 0,
              outputHeight > 0,
              outputWidth.isMultiple(of: 2),
              outputHeight.isMultiple(of: 2),
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

    /// 直接读取 BGRA 源像素，在一次目标缓冲区写入中完成裁剪、缩放或复制。
    ///
    /// - Parameters:
    ///   - pixelBuffer: BGRA 像素缓冲区。
    ///   - outputWidth: 最终显示宽度。
    ///   - outputHeight: 最终显示高度。
    ///   - rotation: 缩放后应用的旋转方向。
    ///   - timestampUs: 单调时间戳，单位为微秒。
    /// - Returns: 持有处理后 BGRA 像素的视频帧。
    /// - Throws: 尺寸、缓冲区布局无效或像素处理失败时抛出错误。
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
        let (outputPixels, pixelOverflow) = outputWidth.multipliedReportingOverflow(by: outputHeight)
        let (byteCount, byteOverflow) = outputPixels.multipliedReportingOverflow(by: 4)
        guard width > 0, height > 0, outputWidth > 0, outputHeight > 0,
              outputWidth.isMultiple(of: 2), outputHeight.isMultiple(of: 2),
              !sourceOverflow, !pixelOverflow, !byteOverflow,
              CVPixelBufferGetBytesPerRow(pixelBuffer) >= sourceRowBytes,
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            throw mediaError("Invalid BGRA video dimensions or buffer layout")
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
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
                    memcpy(destination.advanced(by: row * rowBytes), start.advanced(by: row * stride), rowBytes)
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
            guard vImageScale_ARGB8888(&input, &output, nil, vImage_Flags(kvImageHighQualityResampling)) == kvImageNoError else {
                throw mediaError("Failed to scale BGRA video pixels")
            }
        }

        if rotation != .rotation0 {
            var rotated = Data(count: byteCount)
            try data.withUnsafeBytes { sourceBytes in
                try rotated.withUnsafeMutableBytes { destinationBytes in
                    guard let source = sourceBytes.baseAddress,
                          let destination = destinationBytes.baseAddress else {
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
                    guard vImageRotate90_ARGB8888(&input, &output, rotationConstant(for: rotation), &background, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
                        throw mediaError("Failed to rotate BGRA video pixels")
                    }
                }
            }
            data = rotated
        }

        return try VideoFrame(
            format: VideoFormat(width: outputWidth, height: outputHeight, pixelFormat: .bgra),
            timestampUs: timestampUs,
            planes: [VideoFramePlane(data: data, stride: outputWidth * 4)]
        )
    }

    /// 裁剪并缩放 NV12 的亮度和色度平面。
    ///
    /// - Parameters:
    ///   - lumaBaseAddress: 源亮度平面起始地址。
    ///   - lumaStride: 源亮度平面每行字节数。
    ///   - chromaBaseAddress: 源色度平面起始地址。
    ///   - chromaStride: 源色度平面每行字节数。
    ///   - crop: 源图像中的偶数对齐裁剪区域。
    ///   - outputWidth: 缩放后的宽度，单位为像素。
    ///   - outputHeight: 缩放后的高度，单位为像素。
    /// - Returns: 连续存储亮度和色度平面的 NV12 数据。
    /// - Throws: 内存分配或平面缩放失败时抛出错误。
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
                    memcpy(destination.advanced(by: row * outputWidth), luma.advanced(by: row * lumaStride), outputWidth)
                }
                for row in 0..<(outputHeight / 2) {
                    memcpy(destination.advanced(by: lumaLength + row * outputWidth), chroma.advanced(by: row * chromaStride), outputWidth)
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
            guard vImageScale_Planar8(
                &sourceLuma,
                &targetLuma,
                nil,
                flags
            ) == kvImageNoError else {
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
            guard vImageScale_CbCr8(
                &sourceChroma,
                &targetChroma,
                nil,
                flags
            ) == kvImageNoError else {
                throw mediaError("Failed to scale decoded NV12 chroma data")
            }
        }
        return data
    }

    /// 旋转连续存储的 NV12 像素数据。
    ///
    /// - Parameters:
    ///   - data: 源 NV12 数据。
    ///   - sourceWidth: 源图像宽度，单位为像素。
    ///   - sourceHeight: 源图像高度，单位为像素。
    ///   - rotation: 需要应用的旋转角度。
    /// - Returns: 按指定角度旋转后的 NV12 数据；零度旋转时返回原数据。
    /// - Throws: 输出缓冲区分配或平面旋转失败时抛出错误。
    private static func rotate(
        _ data: Data,
        sourceWidth: Int,
        sourceHeight: Int,
        rotation: VideoRotation
    ) throws -> Data {
        guard rotation != .rotation0 else {
            return data
        }

        let swapsDimensions = rotation == .rotation90
            || rotation == .rotation270
        let outputWidth = swapsDimensions ? sourceHeight : sourceWidth
        let outputHeight = swapsDimensions ? sourceWidth : sourceHeight
        let sourceLumaLength = sourceWidth * sourceHeight
        let outputLumaLength = outputWidth * outputHeight
        var output = Data(count: outputLumaLength + outputLumaLength / 2)

        try data.withUnsafeBytes { sourceBytes in
            try output.withUnsafeMutableBytes { outputBytes in
                guard let source = sourceBytes.baseAddress,
                      let destination = outputBytes.baseAddress else {
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
                guard vImageRotate90_Planar8(
                    &sourceLuma,
                    &targetLuma,
                    rotationConstant,
                    0,
                    vImage_Flags(kvImageNoFlags)
                ) == kvImageNoError else {
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
                guard vImageRotate90_Planar16U(
                    &sourceChroma,
                    &targetChroma,
                    rotationConstant,
                    0,
                    vImage_Flags(kvImageNoFlags)
                ) == kvImageNoError else {
                    throw mediaError(
                        "Failed to rotate decoded NV12 chroma data"
                    )
                }
            }
        }
        return output
    }

    /// 计算应用旋转前的缩放尺寸。
    ///
    /// - Parameters:
    ///   - outputWidth: 最终显示宽度。
    ///   - outputHeight: 最终显示高度。
    ///   - rotation: 缩放后应用的旋转角度。
    /// - Returns: 旋转前所需的宽度和高度。
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

    /// 将显示旋转转换为 vImage 的四分之一圈旋转次数。
    ///
    /// - Parameter rotation: 视频显示旋转。
    /// - Returns: vImage 使用的旋转常量。
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

    /// 计算符合目标宽高比的居中裁剪区域。
    ///
    /// - Parameters:
    ///   - sourceWidth: 源图像宽度。
    ///   - sourceHeight: 源图像高度。
    ///   - targetWidth: 目标图像宽度。
    ///   - targetHeight: 目标图像高度。
    /// - Returns: 位置及尺寸均按 NV12 要求进行偶数对齐的裁剪区域。
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

    /// 向下取偶数尺寸，并保证至少为两个像素。
    ///
    /// - Parameter value: 待对齐的尺寸。
    /// - Returns: 不小于 2 的偶数尺寸。
    private static func evenFloor(
        _ value: Double
    ) -> Int {
        max(Int(floor(value)) / 2 * 2, 2)
    }

    /// 向下取偶数偏移，并保证偏移非负。
    ///
    /// - Parameter value: 待对齐的偏移。
    /// - Returns: 非负偶数偏移。
    private static func evenOffset(
        _ value: Double
    ) -> Int {
        max(Int(floor(value)) / 2 * 2, 0)
    }

    /// 构造视频帧转换错误。
    ///
    /// - Parameter message: 错误描述。
    /// - Returns: 包含指定描述的媒体错误。
    private static func mediaError(
        _ message: String
    ) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
