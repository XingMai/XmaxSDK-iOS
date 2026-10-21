//
//  RemoteVideoFramePipeline.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

/// 串行处理远端解码帧，并在可用时插入一个中间帧。
actor RemoteVideoFramePipeline {

    /// 判断指定视频像素尺寸是否可进行插帧。
    typealias FrameInterpolationSupportChecker = @Sendable (
        _ size: CGSize
    ) -> Bool

    /// 异步接收最终视频帧及其输出流有效期标识。
    typealias OutputListener = @Sendable (
        _ frame: RealtimeVideoFrame,
        _ outputToken: UInt64
    ) async -> Void

    /// 根据源帧规格创建插帧处理器，不可用时返回空值。
    typealias InterpolationManagerFactory = @Sendable (
        _ frame: RealtimeVideoFrame
    ) throws -> (any FrameInterpolationManaging)?

    /// 判断帧尺寸是否支持插帧的操作。
    private let frameInterpolationSupportChecker:
        FrameInterpolationSupportChecker

    /// 根据输入帧规格创建插帧处理器。
    private let interpolationManagerFactory: InterpolationManagerFactory

    /// 接收最终帧及其流标识的异步回调。
    private let outputListener: OutputListener

    /// 接收插帧失败并降级时的错误。
    private let errorListener: XmaxErrorListener

    /// 当前远端流使用的插帧处理器。
    private var interpolationManager:
        (any FrameInterpolationManaging)?

    /// 尚未处理的最新远端帧。
    private var pendingFrame: RealtimeVideoFrame?

    /// 串行消费远端帧的任务。
    private var drainTask: Task<Void, Never>?

    /// 等待旧插帧会话完成资源释放的任务。
    private var cleanupTask: Task<Void, Never>?

    /// 当前请求的插帧开关。
    private var interpolationEnabled: Bool

    /// 当前插帧处理器对应的视频尺寸。
    private var interpolationVideoSize: CGSize?

    /// 上一输出帧的展示时间，用于确定中间帧时间戳。
    private var previousPresentationTimeStamp: CMTime?

    /// 帧处理任务的有效期，用于丢弃过期输出。
    private var generation = 0

    /// 输出流标识，用于区分前后两次远端流。
    private var outputToken: UInt64

    /// 创建带流有效期检查的远端帧处理管线。
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

    /// 当前是否请求启用插帧。
    var isFrameInterpolationEnabled: Bool {
        interpolationEnabled
    }

    /// 将帧加入当前输出流的处理队列。
    ///
    /// - Parameter frame: 最新远端解码帧。
    func enqueue(
        _ frame: RealtimeVideoFrame
    ) {
        enqueue(frame, outputToken: outputToken)
    }

    /// 接收有效流的最新帧，并在清理完成后开始处理。
    ///
    /// - Parameters:
    ///   - frame: 最新远端解码帧。
    ///   - outputToken: 该帧所属的输出流标识。
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

    /// 校验并切换插帧模式，等待旧处理资源结束。
    ///
    /// - Parameters:
    ///   - enabled: 是否启用插帧。
    ///   - videoSize: 期望回传尺寸；未知时只校验设备能力。
    ///   - outputToken: 调用时对应的输出流标识。
    /// - Throws: 启用插帧但设备或指定尺寸不受支持时抛出错误。
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

    /// 更新输出流有效期并等待旧处理资源清理。
    ///
    /// - Parameter outputToken: 目标输出流标识；旧标识不会覆盖当前流。
    func reset(
        outputToken: UInt64
    ) async {
        if outputToken > self.outputToken {
            resetProcessing(outputToken: outputToken)
        }
        await cleanupTask?.value
    }
}

private extension RemoteVideoFramePipeline {

    /// 记录决定插帧器是否可复用的视频帧规格。
    struct FrameSignature: Equatable {

        /// 当前插帧输入宽度，单位为像素。
        let width: Int

        /// 当前插帧输入高度，单位为像素。
        let height: Int

        /// 当前插帧输入的像素格式。
        let pixelFormat: OSType

        /// 提取视频帧的尺寸和像素格式。
        ///
        /// - Parameter frame: 用于检查插帧器兼容性的视频帧。
        init(
            _ frame: RealtimeVideoFrame
        ) {
            width = CVPixelBufferGetWidth(frame.pixelBuffer)
            height = CVPixelBufferGetHeight(frame.pixelBuffer)
            pixelFormat = CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
        }

        /// 插帧输入对应的像素宽高。
        var size: CGSize {
            CGSize(width: width, height: height)
        }
    }

    /// 使在途处理失效并串行回收旧插帧器及任务。
    ///
    /// - Parameter outputToken: 新的输出流有效期标识。
    func resetProcessing(
        outputToken: UInt64
    ) {
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

    /// 处理待输出的最新帧，并过滤取消或过期结果。
    ///
    /// - Parameters:
    ///   - activeGeneration: 当前帧处理版本。
    ///   - activeOutputToken: 当前输出流标识。
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

    /// 为有效帧生成插值结果，或在未启用及降级时透传。
    ///
    /// - Parameters:
    ///   - frame: 当前远端解码帧。
    ///   - sourceDuration: 源帧显示时长。
    ///   - activeGeneration: 当前帧处理版本。
    /// - Returns: 可输出的视频帧数组；处理已失效时返回空数组。
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

    /// 关闭插帧并通知降级原因，随后释放处理器。
    ///
    /// - Parameter error: 导致插帧降级的错误。
    func disableAfterFailure(
        _ error: XmaxError
    ) async {
        interpolationEnabled = false
        let previousManager = interpolationManager
        interpolationManager = nil
        errorListener(error)
        await previousManager?.close()
    }

    /// 保留源像素和时间戳并补充帧时长。
    ///
    /// - Parameters:
    ///   - frame: 需要透传的视频帧。
    ///   - duration: 输出帧的显示时长。
    /// - Returns: 带有效显示时长的源视频帧。
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

    /// 根据相邻有效时间戳估算源帧时长。
    ///
    /// - Parameter presentationTimeStamp: 当前帧的显示时间戳。
    /// - Returns: 有效帧间隔；无法估算时返回 1/24 秒。
    func frameDuration(
        for presentationTimeStamp: CMTime
    ) -> CMTime {
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

    /// 构造设备或尺寸不支持插帧的错误。
    ///
    /// - Parameter videoSize: 不受支持的视频尺寸；`nil` 表示设备能力不支持。
    /// - Returns: 包含不支持原因的插帧错误。
    static func unsupportedError(
        videoSize: CGSize?
    ) -> XmaxError {
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
