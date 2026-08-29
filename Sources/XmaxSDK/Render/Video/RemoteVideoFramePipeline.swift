import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

/// 串行处理远端解码帧，并在可用时插入一个中间帧。
actor RemoteVideoFramePipeline {
    typealias FrameInterpolationSupportChecker = @Sendable (
        _ size: CGSize
    ) -> Bool

    typealias OutputListener = @Sendable (
        _ frame: DecodedVideoFrame,
        _ outputToken: UUID
    ) async -> Void

    // 事件监听
    private let outputListener: OutputListener
    private let errorListener: XmaxErrorListener
    private let frameInterpolationSupportChecker:
        FrameInterpolationSupportChecker

    // 帧处理资源
    private var interpolationManager:
        (any FrameInterpolationManaging)?
    private var pendingFrame: DecodedVideoFrame?
    private var drainTask: Task<Void, Never>?

    // 运行状态
    private var interpolationEnabled: Bool
    private var previousPresentationTimeStamp: CMTime?
    private var generation = 0
    private var outputToken: UUID

    init(
        interpolationEnabled: Bool,
        outputToken: UUID,
        frameInterpolationSupportChecker:
            @escaping FrameInterpolationSupportChecker = {
                FrameInterpolationSupport.supports(size: $0)
            },
        outputListener: @escaping OutputListener,
        errorListener: @escaping XmaxErrorListener
    ) {
        self.interpolationEnabled = interpolationEnabled
        self.outputToken = outputToken
        self.frameInterpolationSupportChecker =
            frameInterpolationSupportChecker
        self.outputListener = outputListener
        self.errorListener = errorListener
    }

    var isFrameInterpolationEnabled: Bool {
        interpolationEnabled
    }

    func enqueue(_ frame: DecodedVideoFrame) {
        pendingFrame = frame
        guard drainTask == nil else { return }
        let activeGeneration = generation
        let activeOutputToken = outputToken
        drainTask = Task { [weak self] in
            await self?.drainFrames(
                generation: activeGeneration,
                outputToken: activeOutputToken
            )
        }
    }

    func setFrameInterpolationEnabled(
        _ enabled: Bool,
        videoSize: CGSize?,
        outputToken: UUID
    ) throws {
        if enabled {
            guard FrameInterpolationSupport.isSupported else {
                throw Self.unsupportedError(videoSize: videoSize)
            }
            if let videoSize,
               !frameInterpolationSupportChecker(videoSize) {
                throw Self.unsupportedError(videoSize: videoSize)
            }
        }
        interpolationEnabled = enabled
        resetProcessing(outputToken: outputToken)
    }

    func reset(outputToken: UUID) {
        resetProcessing(outputToken: outputToken)
    }
}

private extension RemoteVideoFramePipeline {
    struct FrameSignature: Equatable {
        let width: Int
        let height: Int
        let pixelFormat: OSType

        init(_ frame: DecodedVideoFrame) {
            width = CVPixelBufferGetWidth(frame.pixelBuffer)
            height = CVPixelBufferGetHeight(frame.pixelBuffer)
            pixelFormat = CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
        }

        var size: CGSize {
            CGSize(width: width, height: height)
        }
    }

    func resetProcessing(outputToken: UUID) {
        generation += 1
        self.outputToken = outputToken
        drainTask?.cancel()
        drainTask = nil
        pendingFrame = nil
        previousPresentationTimeStamp = nil
        interpolationManager?.reset()
        interpolationManager = nil
    }

    func drainFrames(
        generation activeGeneration: Int,
        outputToken activeOutputToken: UUID
    ) async {
        while !Task.isCancelled,
              generation == activeGeneration,
              let frame = pendingFrame {
            pendingFrame = nil
            let sourceDuration = frameDuration(
                for: frame.presentationTimeStamp
            )
            let outputFrames = await process(
                frame,
                sourceDuration: sourceDuration
            )
            guard !Task.isCancelled,
                  generation == activeGeneration else {
                break
            }
            for outputFrame in outputFrames {
                guard !Task.isCancelled,
                      generation == activeGeneration else {
                    break
                }
                await outputListener(outputFrame, activeOutputToken)
            }
        }
        if generation == activeGeneration {
            drainTask = nil
        }
    }

    func process(
        _ frame: DecodedVideoFrame,
        sourceDuration: CMTime
    ) async -> [DecodedVideoFrame] {
        guard interpolationEnabled else {
            return [passthrough(frame, duration: sourceDuration)]
        }

        let signature = FrameSignature(frame)
        guard frameInterpolationSupportChecker(signature.size) else {
            disableAfterFailure(Self.unsupportedError(videoSize: signature.size))
            return [passthrough(frame, duration: sourceDuration)]
        }

        do {
            if interpolationManager?.matches(frame) != true {
                interpolationManager?.reset()
                interpolationManager = try makeInterpolationManager(frame)
            }
            guard let interpolationManager else {
                throw Self.unsupportedError(videoSize: signature.size)
            }
            return try await interpolationManager.process(
                frame,
                sourceDuration: sourceDuration
            )
        } catch {
            let resolvedError: XmaxError
            if let xmaxError = error as? XmaxError {
                resolvedError = xmaxError
            } else {
                resolvedError = XmaxError(
                    code: .mediaError,
                    message: "Frame interpolation failed: " +
                        (error as NSError).localizedDescription
                )
            }
            disableAfterFailure(resolvedError)
            return [passthrough(frame, duration: sourceDuration)]
        }
    }

    func makeInterpolationManager(
        _ frame: DecodedVideoFrame
    ) throws -> (any FrameInterpolationManaging)? {
#if targetEnvironment(simulator)
        nil
#else
        if #available(iOS 26.0, *) {
            try FrameInterpolationManager(frame: frame)
        } else {
            nil
        }
#endif
    }

    func disableAfterFailure(_ error: XmaxError) {
        interpolationEnabled = false
        interpolationManager?.reset()
        interpolationManager = nil
        errorListener(error)
    }

    func passthrough(
        _ frame: DecodedVideoFrame,
        duration: CMTime
    ) -> DecodedVideoFrame {
        DecodedVideoFrame(
            pixelBuffer: frame.pixelBuffer,
            presentationTimeStamp: frame.presentationTimeStamp,
            duration: duration
        )
    }

    func frameDuration(for presentationTimeStamp: CMTime) -> CMTime {
        defer {
            if presentationTimeStamp.isValid {
                previousPresentationTimeStamp = presentationTimeStamp
            }
        }
        guard presentationTimeStamp.isValid,
              let previousPresentationTimeStamp,
              previousPresentationTimeStamp.isValid else {
            return CMTime(value: 1, timescale: 24)
        }

        let duration = presentationTimeStamp - previousPresentationTimeStamp
        guard duration.isValid,
              duration > .zero,
              duration < CMTime(seconds: 1, preferredTimescale: 600) else {
            return CMTime(value: 1, timescale: 24)
        }
        return duration
    }

    static func unsupportedError(videoSize: CGSize?) -> XmaxError {
        let sizeDescription: String
        if let videoSize {
            sizeDescription = " for \(Int(videoSize.width)) × " +
                "\(Int(videoSize.height)) video"
        } else {
            sizeDescription = " on this device"
        }
        return XmaxError(
            code: .frameInterpolationUnsupported,
            message: "Frame interpolation is unavailable" + sizeDescription
        )
    }
}
