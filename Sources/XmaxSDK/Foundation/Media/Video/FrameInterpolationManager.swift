#if !targetEnvironment(simulator)
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// 使用 VideoToolbox 在相邻视频帧之间生成一个低延迟中间帧。
@available(iOS 26.0, *)
final class FrameInterpolationManager:
    FrameInterpolationManaging,
    @unchecked Sendable {

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

    init(frame: DecodedVideoFrame) throws {
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

    deinit {
        processor.endSession()
    }

    func matches(_ frame: DecodedVideoFrame) -> Bool {
        CVPixelBufferGetWidth(frame.pixelBuffer) == sourceWidth &&
            CVPixelBufferGetHeight(frame.pixelBuffer) == sourceHeight &&
            CVPixelBufferGetPixelFormatType(frame.pixelBuffer) ==
                sourcePixelFormat
    }

    func process(
        _ frame: DecodedVideoFrame,
        sourceDuration: CMTime
    ) async throws -> [DecodedVideoFrame] {
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
                DecodedVideoFrame(
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
        self.previousSourceFrame = sourceFrame

        let outputDuration = sourceDuration.divided(by: 2)
        return [
            DecodedVideoFrame(
                pixelBuffer: destinationFrame.buffer,
                presentationTimeStamp: interpolationTimeStamp,
                duration: outputDuration
            ),
            DecodedVideoFrame(
                pixelBuffer: sourcePixelBuffer,
                presentationTimeStamp: timeStamp,
                duration: outputDuration
            )
        ]
    }

    func reset() {
        previousSourceFrame = nil
        lastNormalizedTimeStamp = nil
    }
}

@available(iOS 26.0, *)
private extension FrameInterpolationManager {
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

    static func makePixelBufferPool(
        attributes: [String: Any]
    ) throws -> CVPixelBufferPool {
        try makePixelBufferPool(attributes: attributes as CFDictionary)
    }

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

    static func mediaError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}

private extension CMTime {
    func multiplied(by multiplier: Float64) -> CMTime {
        CMTimeMultiplyByFloat64(self, multiplier: multiplier)
    }

    func divided(by divisor: Int32) -> CMTime {
        CMTimeMultiplyByRatio(self, multiplier: 1, divisor: divisor)
    }
}
#endif
