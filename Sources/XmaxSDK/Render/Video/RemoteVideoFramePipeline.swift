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
        _ frame: RealtimeVideoFrame,
        _ outputToken: UInt64
    ) async -> Void

    typealias InterpolationManagerFactory = @Sendable (
        _ frame: RealtimeVideoFrame
    ) throws -> (any FrameInterpolationManaging)?

    // 组件依赖
    private let frameInterpolationSupportChecker:
        FrameInterpolationSupportChecker
    private let interpolationManagerFactory: InterpolationManagerFactory

    // 事件监听
    private let outputListener: OutputListener
    private let errorListener: XmaxErrorListener

    // 帧处理资源
    private var interpolationManager:
        (any FrameInterpolationManaging)?
    private var pendingFrame: RealtimeVideoFrame?
    private var drainTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?

    // 运行状态
    private var interpolationEnabled: Bool
    private var interpolationVideoSize: CGSize?
    private var previousPresentationTimeStamp: CMTime?
    private var generation = 0
    private var outputToken: UInt64

    init(
        interpolationEnabled: Bool,
        outputToken: UInt64,
        frameInterpolationSupportChecker:
            @escaping FrameInterpolationSupportChecker = {
                FrameInterpolationSupport.supports(size: $0)
            },
        interpolationManagerFactory: @escaping InterpolationManagerFactory = {
#if targetEnvironment(simulator)
            nil
#else
            if #available(iOS 26.0, *) {
                try FrameInterpolationManager(frame: $0)
            } else {
                nil
            }
#endif
        },
        outputListener: @escaping OutputListener,
        errorListener: @escaping XmaxErrorListener
    ) {
        self.interpolationEnabled = interpolationEnabled
        self.outputToken = outputToken
        self.frameInterpolationSupportChecker =
            frameInterpolationSupportChecker
        self.interpolationManagerFactory = interpolationManagerFactory
        self.outputListener = outputListener
        self.errorListener = errorListener
    }

    var isFrameInterpolationEnabled: Bool {
        interpolationEnabled
    }

    func enqueue(_ frame: RealtimeVideoFrame) {
        enqueue(frame, outputToken: outputToken)
    }

    func enqueue(
        _ frame: RealtimeVideoFrame,
        outputToken: UInt64
    ) {
        guard outputToken >= self.outputToken else { return }
        if outputToken > self.outputToken {
            resetProcessing(outputToken: outputToken)
        }
        pendingFrame = frame
        guard drainTask == nil else { return }
        let activeGeneration = generation
        let activeOutputToken = outputToken
        drainTask = Task { [weak self, cleanupTask] in
            await cleanupTask?.value
            await self?.drainFrames(
                generation: activeGeneration,
                outputToken: activeOutputToken
            )
        }
    }

    func setFrameInterpolationEnabled(
        _ enabled: Bool,
        videoSize: CGSize?,
        outputToken: UInt64
    ) async throws {
        if enabled {
            let supported = videoSize.map(frameInterpolationSupportChecker)
                ?? FrameInterpolationSupport.isSupported
            guard supported else {
                throw Self.unsupportedError(videoSize: videoSize)
            }
        }
        interpolationEnabled = enabled
        interpolationVideoSize = enabled ? videoSize : nil
        // 模式切换不更换流标识，也不能覆盖异步等待期间已经切换的新流标识。
        resetProcessing(outputToken: max(outputToken, self.outputToken))
        await cleanupTask?.value
    }

    func reset(outputToken: UInt64) async {
        if outputToken > self.outputToken {
            resetProcessing(outputToken: outputToken)
        }
        await cleanupTask?.value
    }
}

private extension RemoteVideoFramePipeline {
    struct FrameSignature: Equatable {
        let width: Int
        let height: Int
        let pixelFormat: OSType

        init(_ frame: RealtimeVideoFrame) {
            width = CVPixelBufferGetWidth(frame.pixelBuffer)
            height = CVPixelBufferGetHeight(frame.pixelBuffer)
            pixelFormat = CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
        }

        var size: CGSize {
            CGSize(width: width, height: height)
        }
    }

    func resetProcessing(outputToken: UInt64) {
        generation += 1
        self.outputToken = outputToken
        drainTask?.cancel()
        let previousDrainTask = drainTask
        let previousCleanupTask = cleanupTask
        let previousManager = interpolationManager
        drainTask = nil
        pendingFrame = nil
        previousPresentationTimeStamp = nil
        interpolationManager = nil
        cleanupTask = Task {
            await previousCleanupTask?.value
            await previousManager?.close()
            await previousDrainTask?.value
        }
    }

    func drainFrames(
        generation activeGeneration: Int,
        outputToken activeOutputToken: UInt64
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
                sourceDuration: sourceDuration,
                generation: activeGeneration
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
        _ frame: RealtimeVideoFrame,
        sourceDuration: CMTime,
        generation activeGeneration: Int
    ) async -> [RealtimeVideoFrame] {
        guard interpolationEnabled else {
            return [passthrough(frame, duration: sourceDuration)]
        }

        let signature = FrameSignature(frame)
        // 调整回传尺寸期间，旧尺寸帧继续显示，不进入插帧器，也不关闭用户开关。
        if let interpolationVideoSize, signature.size != interpolationVideoSize {
            let previousManager = interpolationManager
            interpolationManager = nil
            await previousManager?.close()
            return [passthrough(frame, duration: sourceDuration)]
        }
        guard frameInterpolationSupportChecker(signature.size) else {
            await disableAfterFailure(Self.unsupportedError(videoSize: signature.size))
            return [passthrough(frame, duration: sourceDuration)]
        }

        do {
            if interpolationManager?.matches(frame) != true {
                let previousManager = interpolationManager
                interpolationManager = nil
                await previousManager?.close()

                guard !Task.isCancelled,
                      generation == activeGeneration else {
                    return []
                }
                interpolationManager = try interpolationManagerFactory(frame)
            }
            guard let interpolationManager else {
                throw Self.unsupportedError(videoSize: signature.size)
            }
            return try await interpolationManager.process(
                frame,
                sourceDuration: sourceDuration
            )
        } catch {
            guard !Task.isCancelled,
                  generation == activeGeneration else {
                return []
            }
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
            await disableAfterFailure(resolvedError)
            return [passthrough(frame, duration: sourceDuration)]
        }
    }

    func disableAfterFailure(_ error: XmaxError) async {
        interpolationEnabled = false
        let previousManager = interpolationManager
        interpolationManager = nil
        errorListener(error)
        await previousManager?.close()
    }

    func passthrough(
        _ frame: RealtimeVideoFrame,
        duration: CMTime
    ) -> RealtimeVideoFrame {
        RealtimeVideoFrame(
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
