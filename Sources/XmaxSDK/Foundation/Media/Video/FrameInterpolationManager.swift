//
//  FrameInterpolationManager.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#if !targetEnvironment(simulator)
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// A VideoToolbox processor generating one low-latency frame between source frames.
@available(iOS 26.0, *)
actor FrameInterpolationManager: FrameInterpolationManaging {

    /// The interpolation input width, in pixels.
    private let sourceWidth: Int

    /// The interpolation input height, in pixels.
    private let sourceHeight: Int

    /// The interpolation input pixel format.
    private let sourcePixelFormat: OSType

    /// The system frame interpolation processor.
    private let processor = VTFrameProcessor()

    /// The Core Image context for input conversion.
    private let imageContext = CIContext(options: nil)

    /// The reusable interpolation input buffers.
    private let sourcePool: CVPixelBufferPool

    /// The reusable interpolation output buffers.
    private let destinationPool: CVPixelBufferPool

    /// The preceding frame used for interpolation.
    private var previousSourceFrame: VTFrameProcessorFrame?

    /// The last normalized timestamp.
    private var lastNormalizedTimeStamp: CMTime?

    /// Whether the interpolation session is closed.
    private var isClosed = false

    /// Creates an interpolation session for the first frame's format.
    ///
    /// - Parameter frame: The first frame, defining input dimensions and pixel format.
    ///
    /// - Throws: An error if interpolation is unsupported or buffer or session creation fails.
    init(
        frame: RealtimeVideoFrame
    ) throws {
        sourceWidth = CVPixelBufferGetWidth(frame.pixelBuffer)
        sourceHeight = CVPixelBufferGetHeight(frame.pixelBuffer)
        sourcePixelFormat = CVPixelBufferGetPixelFormatType(frame.pixelBuffer)

        guard VTLowLatencyFrameInterpolationConfiguration.isSupported,
            let configuration =
                VTLowLatencyFrameInterpolationConfiguration(
                    frameWidth: sourceWidth,
                    frameHeight: sourceHeight,
                    numberOfInterpolatedFrames: 1
                )
        else {
            throw XmaxError(
                code: .frameInterpolationUnsupported,
                message: "Frame interpolation is unavailable for the remote video dimensions"
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
                message: "Failed to start frame interpolation: "
                    + (error as NSError).localizedDescription
            )
        }
    }

    /// Closes an active interpolation session.
    isolated deinit {
        if !isClosed {
            processor.endSession()
        }
    }

    /// Checks whether the processor matches an input frame.
    ///
    /// - Parameter frame: The frame to compare.
    ///
    /// - Returns: `true` if dimensions and pixel format match.
    nonisolated func matches(
        _ frame: RealtimeVideoFrame
    ) -> Bool {
        CVPixelBufferGetWidth(frame.pixelBuffer) == sourceWidth
            && CVPixelBufferGetHeight(frame.pixelBuffer) == sourceHeight
            && CVPixelBufferGetPixelFormatType(frame.pixelBuffer) == sourcePixelFormat
    }

    /// Generates an intermediate frame between the previous and current frames.
    ///
    /// - Parameters:
    ///   - frame: The current decoded video frame.
    ///   - sourceDuration: The current source frame's display duration.
    ///
    /// - Returns: The original first frame, or an interpolated frame followed by the current frame.
    ///
    /// - Throws: An error if buffer preparation or VideoToolbox processing fails.
    func process(
        _ frame: RealtimeVideoFrame,
        sourceDuration: CMTime
    ) async throws -> [RealtimeVideoFrame] {
        guard !isClosed else {
            throw CancellationError()
        }

        let timeStamp = normalizedTimeStamp(
            frame.presentationTimeStamp,
            duration: sourceDuration
        )
        let sourcePixelBuffer = try makeSourcePixelBuffer(
            copying: frame.pixelBuffer
        )
        guard
            let sourceFrame = VTFrameProcessorFrame(
                buffer: sourcePixelBuffer,
                presentationTimeStamp: timeStamp
            )
        else {
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
            previousSourceFrame.presentationTimeStamp + interpolationDuration.multiplied(by: 0.5)
        let destinationFrame = try makeDestinationFrame(
            timeStamp: interpolationTimeStamp
        )
        CVBufferPropagateAttachments(
            sourcePixelBuffer,
            destinationFrame.buffer
        )
        guard
            let parameters = VTLowLatencyFrameInterpolationParameters(
                sourceFrame: sourceFrame,
                previousFrame: previousSourceFrame,
                interpolationPhase: [0.5],
                destinationFrames: [destinationFrame]
            )
        else {
            throw Self.mediaError(
                "Failed to create frame interpolation parameters"
            )
        }

        try await process(parameters)
        guard !isClosed else {
            throw CancellationError()
        }
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

    /// Closes interpolation and releases retained frames.
    func close() {
        guard !isClosed else {
            return
        }
        isClosed = true
        processor.endSession()
        previousSourceFrame = nil
        lastNormalizedTimeStamp = nil
    }
}

@available(iOS 26.0, *)
private extension FrameInterpolationManager {

    /// Submits a VideoToolbox processing request and awaits completion.
    ///
    /// - Parameter parameters: The input and output processing parameters.
    ///
    /// - Throws: The underlying VideoToolbox processing error.
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

    /// Creates a timestamped frame from the output pool.
    ///
    /// - Parameter timeStamp: The interpolated frame's presentation timestamp.
    ///
    /// - Returns: The frame receiving the interpolation output.
    ///
    /// - Throws: An error if buffer or processing frame allocation fails.
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
            )
        else {
            throw Self.mediaError(
                "Failed to allocate an interpolation output buffer: \(status)"
            )
        }

        return frame
    }

    /// Copies input pixels into an interpolation-compatible buffer.
    ///
    /// - Parameter pixelBuffer: The source pixel buffer.
    ///
    /// - Returns: A converted buffer retaining the source attachments.
    ///
    /// - Throws: An error if input buffer allocation fails.
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
                "Failed to allocate an interpolation source buffer: \(status)"
            )
        }

        CVBufferPropagateAttachments(
            pixelBuffer,
            sourcePixelBuffer
        )
        imageContext.render(
            CIImage(cvPixelBuffer: pixelBuffer),
            to: sourcePixelBuffer
        )
        return sourcePixelBuffer
    }

    /// Resolves a valid timestamp using the previous frame when necessary.
    ///
    /// - Parameters:
    ///   - timeStamp: The input presentation timestamp.
    ///   - duration: The frame interval used when the timestamp is missing.
    ///
    /// - Returns: The timestamp used for interpolation.
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

    /// Resolves a valid interpolation interval between source frames.
    ///
    /// - Parameters:
    ///   - previous: The previous presentation timestamp.
    ///   - current: The current presentation timestamp.
    ///   - fallback: The fallback interval for invalid differences or differences of at least one
    ///     second.
    ///
    /// - Returns: The resolved frame interval.
    func resolvedInterpolationDuration(
        previous: CMTime,
        current: CMTime,
        fallback: CMTime
    ) -> CMTime {
        let duration = current - previous
        guard duration.isValid,
            duration > .zero,
            duration
                < CMTime(
                    seconds: 1,
                    preferredTimescale: 600
                )
        else {
            return fallback
        }

        return duration
    }

    /// Creates a reusable pixel buffer pool.
    ///
    /// - Parameter attributes: The pixel buffer attributes.
    ///
    /// - Returns: The pixel buffer pool.
    ///
    /// - Throws: An error if pool creation fails.
    static func makePixelBufferPool(
        attributes: [String: Any]
    ) throws -> CVPixelBufferPool {
        try makePixelBufferPool(attributes: attributes as CFDictionary)
    }

    /// Creates a reusable pixel buffer pool.
    ///
    /// - Parameter attributes: The pixel buffer attributes.
    ///
    /// - Returns: The pixel buffer pool.
    ///
    /// - Throws: An error if pool creation fails.
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
                "Failed to create an interpolation pixel buffer pool: \(status)"
            )
        }

        return pool
    }

    /// Creates an IOSurface-backed input pool satisfying processor requirements.
    ///
    /// - Parameters:
    ///   - width: The input width, in pixels.
    ///   - height: The input height, in pixels.
    ///   - pixelFormat: The processing pixel format.
    ///   - requiredAttributes: The processor's required source attributes.
    ///
    /// - Returns: A compatible source pixel buffer pool.
    ///
    /// - Throws: An error if attributes cannot be merged or the pool cannot be created.
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
                "Failed to resolve interpolation buffer attributes: \(status)"
            )
        }

        return try makePixelBufferPool(attributes: resolvedAttributes)
    }

    /// Selects a supported input pixel format.
    ///
    /// - Parameters:
    ///   - inputPixelFormat: The source pixel format.
    ///   - supportedPixelFormats: The processor's supported pixel formats.
    ///
    /// - Returns: The source format if supported, otherwise NV12, BGRA, or the first supported
    ///   format.
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

    /// Creates a frame interpolation error.
    ///
    /// - Parameter message: The error description.
    ///
    /// - Returns: A media error with the specified description.
    static func mediaError(
        _ message: String
    ) -> XmaxError {
        XmaxError(
            code: .mediaError,
            message: message
        )
    }
}

private extension CMTime {

    /// Scales a time value by a floating-point multiplier.
    ///
    /// - Parameter multiplier: The time multiplier.
    ///
    /// - Returns: The scaled time.
    func multiplied(
        by multiplier: Float64
    ) -> CMTime {
        CMTimeMultiplyByFloat64(
            self,
            multiplier: multiplier
        )
    }

    /// Divides a time value by an integer.
    ///
    /// - Parameter divisor: The time divisor.
    ///
    /// - Returns: The divided time.
    func divided(
        by divisor: Int32
    ) -> CMTime {
        CMTimeMultiplyByRatio(
            self,
            multiplier: 1,
            divisor: divisor
        )
    }
}
#endif
