//
//  FrameInterpolationManager.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#if !targetEnvironment(simulator)
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// 使用 VideoToolbox 在相邻视频帧之间生成一个低延迟中间帧。
@available(iOS 26.0, *)
actor FrameInterpolationManager: FrameInterpolationManaging {

    // 输入规格
    private let sourceWidth: Int
    private let sourceHeight: Int
    private let sourcePixelFormat: OSType


    // 平台资源
    private let processor = VTFrameProcessor()
    private let imageContext = CIContext(options: nil)
    private let sourcePool: CVPixelBufferPool
    private let destinationPool: CVPixelBufferPool


    // 运行状态
    private var previousSourceFrame: VTFrameProcessorFrame?
    private var lastNormalizedTimeStamp: CMTime?
    private var isClosed = false

    /// 根据首帧规格建立低延迟插帧会话及像素缓冲池。
    ///
    /// - Parameter frame: 确定输入尺寸和像素格式的首帧。
    /// - Throws: 设备或尺寸不支持插帧、缓冲池创建失败或处理会话启动失败时抛出错误。
    init(frame: RealtimeVideoFrame) throws {
        sourceWidth = CVPixelBufferGetWidth(frame.pixelBuffer)
        sourceHeight = CVPixelBufferGetHeight(frame.pixelBuffer)
        sourcePixelFormat = CVPixelBufferGetPixelFormatType(frame.pixelBuffer)

        guard VTLowLatencyFrameInterpolationConfiguration.isSupported,
              let configuration =
                VTLowLatencyFrameInterpolationConfiguration(
                    frameWidth: sourceWidth,
                    frameHeight: sourceHeight,
                    numberOfInterpolatedFrames: 1
                ) else {
            throw XmaxError(
                code: .frameInterpolationUnsupported,
                message: "Frame interpolation is unavailable for the " +
                    "remote video dimensions"
            )
        }

        let processingPixelFormat = Self.preferredSourcePixelFormat(
            inputPixelFormat: sourcePixelFormat,
            supportedPixelFormats: configuration.supportedPixelFormats
        )
        sourcePool = try Self.makeSourcePixelBufferPool(
            width: sourceWidth,
            height: sourceHeight,
            pixelFormat: processingPixelFormat,
            requiredAttributes: configuration.sourcePixelBufferAttributes
        )
        destinationPool = try Self.makePixelBufferPool(
            attributes: configuration.destinationPixelBufferAttributes
        )
        do {
            try processor.startSession(configuration: configuration)
        } catch {
            throw XmaxError(
                code: .mediaError,
                message: "Failed to start frame interpolation: " +
                    (error as NSError).localizedDescription
            )
        }
    }

    /// 结束尚未关闭的插帧会话。
    isolated deinit {
        if !isClosed {
            processor.endSession()
        }
    }

    /// 判断处理器是否仍匹配输入帧的视频规格。
    ///
    /// - Parameter frame: 待比较的视频帧。
    /// - Returns: 分辨率与像素格式均匹配时返回 `true`。
    nonisolated func matches(_ frame: RealtimeVideoFrame) -> Bool {
        CVPixelBufferGetWidth(frame.pixelBuffer) == sourceWidth &&
            CVPixelBufferGetHeight(frame.pixelBuffer) == sourceHeight &&
            CVPixelBufferGetPixelFormatType(frame.pixelBuffer) ==
                sourcePixelFormat
    }

    /// 在前一帧和当前帧之间生成一个中间帧。
    ///
    /// - Parameters:
    ///   - frame: 当前解码视频帧。
    ///   - sourceDuration: 当前源帧使用的显示时长。
    /// - Returns: 首帧返回原帧，后续返回中间帧与当前原帧。
    /// - Throws: 像素缓冲区准备或 VideoToolbox 处理失败时抛出错误。
    func process(
        _ frame: RealtimeVideoFrame,
        sourceDuration: CMTime
    ) async throws -> [RealtimeVideoFrame] {
        guard !isClosed else { throw CancellationError() }

        let timeStamp = normalizedTimeStamp(
            frame.presentationTimeStamp,
            duration: sourceDuration
        )
        let sourcePixelBuffer = try makeSourcePixelBuffer(
            copying: frame.pixelBuffer
        )
        guard let sourceFrame = VTFrameProcessorFrame(
            buffer: sourcePixelBuffer,
            presentationTimeStamp: timeStamp
        ) else {
            throw Self.mediaError(
                "Remote video pixel buffer is not IOSurface-backed"
            )
        }

        guard let previousSourceFrame else {
            self.previousSourceFrame = sourceFrame
            return [
                RealtimeVideoFrame(
                    pixelBuffer: sourcePixelBuffer,
                    presentationTimeStamp: timeStamp,
                    duration: sourceDuration
                )
            ]
        }

        let interpolationDuration = resolvedInterpolationDuration(
            previous: previousSourceFrame.presentationTimeStamp,
            current: sourceFrame.presentationTimeStamp,
            fallback: sourceDuration
        )
        let interpolationTimeStamp =
            previousSourceFrame.presentationTimeStamp +
            interpolationDuration.multiplied(by: 0.5)
        let destinationFrame = try makeDestinationFrame(
            timeStamp: interpolationTimeStamp
        )
        CVBufferPropagateAttachments(
            sourcePixelBuffer,
            destinationFrame.buffer
        )
        guard let parameters = VTLowLatencyFrameInterpolationParameters(
            sourceFrame: sourceFrame,
            previousFrame: previousSourceFrame,
            interpolationPhase: [0.5],
            destinationFrames: [destinationFrame]
        ) else {
            throw Self.mediaError(
                "Failed to create frame interpolation parameters"
            )
        }

        try await process(parameters)
        guard !isClosed else { throw CancellationError() }
        self.previousSourceFrame = sourceFrame

        let outputDuration = sourceDuration.divided(by: 2)
        return [
            RealtimeVideoFrame(
                pixelBuffer: destinationFrame.buffer,
                presentationTimeStamp: interpolationTimeStamp,
                duration: outputDuration
            ),
            RealtimeVideoFrame(
                pixelBuffer: sourcePixelBuffer,
                presentationTimeStamp: timeStamp,
                duration: outputDuration
            )
        ]
    }

    /// 结束插帧会话并释放历史帧，不再接受新的处理请求。
    func close() {
        guard !isClosed else { return }
        isClosed = true
        processor.endSession()
        previousSourceFrame = nil
        lastNormalizedTimeStamp = nil
    }
}

@available(iOS 26.0, *)
private extension FrameInterpolationManager {
    /// 提交一次 VideoToolbox 帧处理并等待完成。
    ///
    /// - Parameter parameters: 当前帧处理所需的输入和输出参数。
    /// - Throws: VideoToolbox 处理失败时抛出原始错误。
    func process(
        _ parameters: any VTFrameProcessorParameters
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            processor.process(parameters: parameters) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// 从输出缓冲池创建带时间戳的目标帧。
    ///
    /// - Parameter timeStamp: 插值帧的显示时间戳。
    /// - Returns: 供 VideoToolbox 写入插值结果的帧。
    /// - Throws: 缓冲区分配或处理帧创建失败时抛出错误。
    func makeDestinationFrame(
        timeStamp: CMTime
    ) throws -> VTFrameProcessorFrame {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            destinationPool,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess,
              let pixelBuffer,
              let frame = VTFrameProcessorFrame(
                buffer: pixelBuffer,
                presentationTimeStamp: timeStamp
              ) else {
            throw Self.mediaError(
                "Failed to allocate an interpolation output buffer: " +
                    "\(status)"
            )
        }
        return frame
    }

    /// 复制输入像素到符合插帧要求的缓冲区。
    ///
    /// - Parameter pixelBuffer: 待复制的源像素缓冲区。
    /// - Returns: 保留源附件并转换为处理像素格式的缓冲区。
    /// - Throws: 源缓冲池分配失败时抛出错误。
    func makeSourcePixelBuffer(
        copying pixelBuffer: CVPixelBuffer
    ) throws -> CVPixelBuffer {
        var sourcePixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            sourcePool,
            &sourcePixelBuffer
        )
        guard status == kCVReturnSuccess, let sourcePixelBuffer else {
            throw Self.mediaError(
                "Failed to allocate an interpolation source buffer: " +
                    "\(status)"
            )
        }

        CVBufferPropagateAttachments(pixelBuffer, sourcePixelBuffer)
        imageContext.render(
            CIImage(cvPixelBuffer: pixelBuffer),
            to: sourcePixelBuffer
        )
        return sourcePixelBuffer
    }

    /// 保留有效时间戳，或根据上一帧时间和帧时长补全时间戳。
    ///
    /// - Parameters:
    ///   - timeStamp: 输入帧的显示时间戳。
    ///   - duration: 缺失时间戳时使用的帧间隔。
    /// - Returns: 当前帧用于插值的时间戳。
    func normalizedTimeStamp(
        _ timeStamp: CMTime,
        duration: CMTime
    ) -> CMTime {
        let resolvedTimeStamp: CMTime
        if timeStamp.isValid {
            resolvedTimeStamp = timeStamp
        } else if let lastNormalizedTimeStamp {
            resolvedTimeStamp = lastNormalizedTimeStamp + duration
        } else {
            resolvedTimeStamp = .zero
        }
        lastNormalizedTimeStamp = resolvedTimeStamp
        return resolvedTimeStamp
    }

    /// 确定相邻源帧之间有效的插值间隔。
    ///
    /// - Parameters:
    ///   - previous: 上一帧显示时间戳。
    ///   - current: 当前帧显示时间戳。
    ///   - fallback: 时间差无效或不在一秒以内时使用的间隔。
    /// - Returns: 有效帧间隔或指定的备用间隔。
    func resolvedInterpolationDuration(
        previous: CMTime,
        current: CMTime,
        fallback: CMTime
    ) -> CMTime {
        let duration = current - previous
        guard duration.isValid,
              duration > .zero,
              duration < CMTime(seconds: 1, preferredTimescale: 600) else {
            return fallback
        }
        return duration
    }

    /// 按指定像素属性创建可复用的缓冲池。
    ///
    /// - Parameter attributes: 像素缓冲区属性。
    /// - Returns: 新建的像素缓冲池。
    /// - Throws: 缓冲池创建失败时抛出错误。
    static func makePixelBufferPool(
        attributes: [String: Any]
    ) throws -> CVPixelBufferPool {
        try makePixelBufferPool(attributes: attributes as CFDictionary)
    }

    /// 按指定像素属性创建可复用的缓冲池。
    ///
    /// - Parameter attributes: 像素缓冲区属性。
    /// - Returns: 新建的像素缓冲池。
    /// - Throws: 缓冲池创建失败时抛出错误。
    static func makePixelBufferPool(
        attributes: CFDictionary
    ) throws -> CVPixelBufferPool {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 8
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            attributes,
            &pool
        )
        guard status == kCVReturnSuccess, let pool else {
            throw mediaError(
                "Failed to create an interpolation pixel buffer pool: " +
                    "\(status)"
            )
        }
        return pool
    }

    /// 合并处理器要求和输入规格，创建支持 IOSurface 的源缓冲池。
    ///
    /// - Parameters:
    ///   - width: 输入宽度，单位为像素。
    ///   - height: 输入高度，单位为像素。
    ///   - pixelFormat: 处理使用的像素格式。
    ///   - requiredAttributes: 处理器要求的源缓冲区属性。
    /// - Returns: 满足处理要求的源像素缓冲池。
    /// - Throws: 属性无法合并或缓冲池创建失败时抛出错误。
    static func makeSourcePixelBufferPool(
        width: Int,
        height: Int,
        pixelFormat: OSType,
        requiredAttributes: [String: Any]
    ) throws -> CVPixelBufferPool {
        let requestedAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var resolvedAttributes: CFDictionary?
        let status = CVPixelBufferCreateResolvedAttributesDictionary(
            kCFAllocatorDefault,
            [
                requiredAttributes as CFDictionary,
                requestedAttributes as CFDictionary
            ] as CFArray,
            &resolvedAttributes
        )
        guard status == kCVReturnSuccess, let resolvedAttributes else {
            throw mediaError(
                "Failed to resolve interpolation buffer attributes: " +
                    "\(status)"
            )
        }
        return try makePixelBufferPool(attributes: resolvedAttributes)
    }

    /// 选取处理器支持的输入像素格式。
    ///
    /// - Parameters:
    ///   - inputPixelFormat: 原始输入像素格式。
    ///   - supportedPixelFormats: 处理器支持的像素格式列表。
    /// - Returns: 优先保留原格式，其次选择 NV12、BGRA 或首个支持的格式。
    static func preferredSourcePixelFormat(
        inputPixelFormat: OSType,
        supportedPixelFormats: [OSType]
    ) -> OSType {
        if supportedPixelFormats.contains(inputPixelFormat) {
            return inputPixelFormat
        }
        if supportedPixelFormats.contains(
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ) {
            return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
        if supportedPixelFormats.contains(kCVPixelFormatType_32BGRA) {
            return kCVPixelFormatType_32BGRA
        }
        return supportedPixelFormats.first ?? inputPixelFormat
    }

    /// 构造插帧处理错误。
    ///
    /// - Parameter message: 错误描述。
    /// - Returns: 包含指定描述的媒体错误。
    static func mediaError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}

private extension CMTime {
    /// 将时间按浮点倍数缩放。
    ///
    /// - Parameter multiplier: 时间缩放倍数。
    /// - Returns: 缩放后的时间。
    func multiplied(by multiplier: Float64) -> CMTime {
        CMTimeMultiplyByFloat64(self, multiplier: multiplier)
    }

    /// 将时间按整数除数分割。
    ///
    /// - Parameter divisor: 时间除数。
    /// - Returns: 分割后的时间。
    func divided(by divisor: Int32) -> CMTime {
        CMTimeMultiplyByRatio(self, multiplier: 1, divisor: divisor)
    }
}
#endif
