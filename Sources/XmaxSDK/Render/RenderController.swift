//
//  RenderController.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import UIKit

/// 统一协调视频轨道、远端帧处理和轨迹交互的渲染资源。
@MainActor
final class RenderController: RenderControlling {

    /// 保存一次远端可显示首帧的等待与超时任务。
    private final class RemoteFrameReadyWaiter {

        /// 等待资源
        let continuation:
            AsyncThrowingStream<Void, any Error>.Continuation
        var timeoutTask: Task<Void, Never>?

        /// 创建等待远端首帧的通知上下文。
        ///
        /// - Parameter continuation: 用于结束首帧等待的异步流 continuation。
        init(
            continuation:
                AsyncThrowingStream<Void, any Error>.Continuation
        ) {
            self.continuation = continuation
        }
    }

    /// 基础层组件
    private let rtcManager: any RtcManaging

    /// 事件监听
    private let errorListener: XmaxErrorListener

    /// 远端帧处理
    private let initialFrameInterpolationEnabled: Bool
    private let frameInterpolationSupportChecker:
        RemoteVideoFramePipeline.FrameInterpolationSupportChecker
    private let remoteFrameReadyTimeoutNanoseconds: UInt64
    private let remoteVideoFrameDispatcher = RealtimeVideoFrameDispatcher()
    private var renderingToken: UInt64 = 0
    private lazy var remoteFramePipeline = RemoteVideoFramePipeline(
        interpolationEnabled: initialFrameInterpolationEnabled,
        outputToken: renderingToken,
        frameInterpolationSupportChecker:
            frameInterpolationSupportChecker,
        outputListener: { [weak self] frame, outputToken in
            await self?.displayRemoteFrame(
                frame,
                outputToken: outputToken
            )
        },
        errorListener: { error in
            XmaxLogger.realtime.error(message: "插帧已降级 (Frame Interpolation Disabled)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))\(error.message)")
        }
    )

    /// 远端渲染资源
    private var remoteStream: RemoteStream?
    private var activeRemoteFrameStream: RemoteStream?
    private weak var remoteView: XmaxVideoView?
    private var remoteContentMode = VideoContentMode.fill
    private var latestRemoteFrame: RealtimeVideoFrame?
    private var remoteFrameReadyWaiters:
        [UUID: RemoteFrameReadyWaiter] = [:]

    /// 创建远端渲染、插帧和帧回调协调组件。
    ///
    /// - Parameters:
    ///   - rtcManager: 提供远端解码帧的 RTC 管理器。
    ///   - frameInterpolationEnabled: 初始是否启用插帧。
    ///   - frameInterpolationSupportChecker: 判断目标尺寸能否插帧的能力检查器。
    ///   - remoteFrameReadyTimeoutNanoseconds: 远端首帧等待超时，单位为纳秒。
    ///   - errorListener: 接收渲染绑定运行错误的回调。
    init(
        rtcManager: any RtcManaging,
        frameInterpolationEnabled: Bool = false,
        frameInterpolationSupportChecker:
            @escaping RemoteVideoFramePipeline
                .FrameInterpolationSupportChecker = {
                    FrameInterpolationSupport.supports(size: $0)
                },
        remoteFrameReadyTimeoutNanoseconds: UInt64 = 10_000_000_000,
        errorListener: @escaping XmaxErrorListener = { _ in }
    ) {
        self.rtcManager = rtcManager
        initialFrameInterpolationEnabled = frameInterpolationEnabled
        self.frameInterpolationSupportChecker =
            frameInterpolationSupportChecker
        self.remoteFrameReadyTimeoutNanoseconds =
            remoteFrameReadyTimeoutNanoseconds
        self.errorListener = errorListener
    }

    /// 插帧状态
    var isFrameInterpolationEnabled: Bool {
        get async {
            await remoteFramePipeline.isFrameInterpolationEnabled
        }
    }

    /// 更新远端解码帧来源并使旧流的缓存和等待失效。
    ///
    /// - Parameter stream: 新的远端流；传入 `nil` 清除当前来源。
    /// - Throws: 旧流监听解除或新流监听绑定失败时抛出错误。
    func setRemoteStream(_ stream: RemoteStream?) throws {
        let previousStream = remoteStream
        if let previousStream, previousStream != stream {
            try deactivateRemoteFrames(for: previousStream)
        }

        remoteStream = stream
        refreshRenderingToken()
        guard stream != nil else {
            remoteView?.clearDecodedVideoPreview()
            return
        }
        try activateRemoteFramesIfReady(reportsError: false)
    }

    /// 设置远端最终视频帧监听器。
    ///
    /// - Parameter listener: 在独立串行队列接收最终帧的回调；`nil` 表示清除。
    func setRemoteVideoFrameListener(
        _ listener: RealtimeVideoFrameListener?
    ) {
        remoteVideoFrameDispatcher.setListener(listener)
    }

    /// 为远端轨道注册视频渲染和轨迹交互绑定。
    ///
    /// - Parameters:
    ///   - track: 需要注册的远端视频轨道。
    ///   - resolvedMediaSize: 处理后的本地媒体尺寸，用于轨迹交互映射。
    ///   - interactionListener: 接收视图交互采样的异步回调。
    func registerRemoteTrack(
        _ track: RealtimeVideoTrack,
        resolvedMediaSize: CGSize,
        interactionListener: @escaping RenderInteractionListener
    ) {
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(
                attachHandler: { [weak self] view, contentMode in
                    try self?.attachRemoteVideo(
                        to: view,
                        contentMode: contentMode
                    )
                },
                detachHandler: { [weak self] _ in
                    try self?.detachRemoteVideo()
                }
            )
        )

        TrajectoryRegistry.register(
            track,
            binding: TrajectoryBinding(
                interactionListener: interactionListener,
                resolvedMediaSize: resolvedMediaSize
            )
        )
    }

    /// 开启或关闭远端视频插帧。
    ///
    /// - Parameters:
    ///   - enabled: 是否开启插帧。
    ///   - videoFormat: 期望的回传视频格式；尚未创建本地流时为空。
    /// - Throws: 显式开启时，当前设备或视频规格不支持插帧则抛出错误。
    func setFrameInterpolationEnabled(
        _ enabled: Bool,
        videoFormat: RealtimeVideoFormat?
    ) async throws {
        try await remoteFramePipeline.setFrameInterpolationEnabled(
            enabled,
            videoSize: videoFormat.map {
                CGSize(width: $0.width, height: $0.height)
            },
            outputToken: renderingToken
        )
    }

    /// 等待当前远端流产生第一张已经完成处理、可立即提交显示的视频帧。
    ///
    /// - Throws: 等待被取消、远端流被重置或首帧等待超时时抛出错误。
    func waitUntilRemoteFrameReady() async throws {
        guard !Task.isCancelled else {
            throw Self.remoteFrameWaitCancelledError()
        }
        guard remoteStream != nil else {
            throw XmaxError(
                code: .rtcError,
                message: "Remote video stream is unavailable"
            )
        }
        if latestRemoteFrame != nil {
            return
        }

        let waiterID = UUID()
        let activeToken = renderingToken
        var continuation:
            AsyncThrowingStream<Void, any Error>.Continuation?
        let stream = AsyncThrowingStream<Void, any Error> {
            continuation = $0
        }
        guard let continuation else {
            throw XmaxError(
                code: .internalError,
                message: "Failed to create remote first frame waiter"
            )
        }
        let waiter = RemoteFrameReadyWaiter(continuation: continuation)
        remoteFrameReadyWaiters[waiterID] = waiter
        waiter.timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(
                    nanoseconds: remoteFrameReadyTimeoutNanoseconds
                )
            } catch {
                return
            }
            finishRemoteFrameReadyWaiter(
                waiterID,
                error: XmaxError(
                    code: .timeout,
                    message: "Remote video first frame timed out"
                )
            )
        }

        try await withTaskCancellationHandler {
            guard activeToken == renderingToken,
                  remoteStream != nil else {
                finishRemoteFrameReadyWaiter(
                    waiterID,
                    error: Self.remoteFrameWaitCancelledError()
                )
                throw Self.remoteFrameWaitCancelledError()
            }
            if latestRemoteFrame != nil {
                finishRemoteFrameReadyWaiter(waiterID)
            }
            for try await _ in stream {
                return
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishRemoteFrameReadyWaiter(
                    waiterID,
                    error: Self.remoteFrameWaitCancelledError()
                )
            }
        }
    }

    /// 注销远端轨道的所有渲染绑定，重置画面并等待在途帧处理结束。
    ///
    /// - Parameter track: 需要注销的远端轨道；没有轨道时仍会清理帧处理资源。
    /// - Throws: 解除 RTC 视频帧监听失败时抛出错误。
    func resetRemoteTrack(_ track: RealtimeVideoTrack?) async throws {
        if let track {
            VideoRenderRegistry.unregister(track)
            TrajectoryRegistry.unregister(track)
        }
        let result = Result { try resetRemoteVideo() }
        await remoteFramePipeline.reset(outputToken: renderingToken)
        try result.get()
    }
}

private extension RenderController {
    /// 绑定远端视频视图，并立即提交已缓存的有效帧。
    ///
    /// - Parameters:
    ///   - view: 用于显示远端画面的 `XmaxVideoView`。
    ///   - contentMode: 远端画面的缩放与裁剪方式。
    /// - Throws: 视图类型无效或远端帧监听启动失败时抛出错误。
    func attachRemoteVideo(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        guard let videoView = view as? XmaxVideoView else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Remote tracks require an XmaxVideoView"
            )
        }
        if let remoteView, remoteView !== videoView,
           remoteStream != nil {
            remoteView.clearDecodedVideoPreview()
        }

        remoteView = videoView
        remoteContentMode = contentMode
        videoView.prepareDecodedVideoPreview(contentMode: contentMode)
        if let latestRemoteFrame {
            videoView.displayRemoteVideoFrame(
                latestRemoteFrame,
                contentMode: contentMode
            )
        }
        try activateRemoteFramesIfReady(reportsError: true)
    }

    /// 清除远端视图的画面并解除视图绑定。
    ///
    /// - Throws: 无。
    func detachRemoteVideo() throws {
        remoteView?.clearDecodedVideoPreview()
        self.remoteView = nil
    }

    /// 移除远端帧监听并清空画面、缓存和首帧等待。
    ///
    /// - Throws: RTC 帧监听解除失败时抛出错误。
    func resetRemoteVideo() throws {
        let stream = remoteStream
        remoteStream = nil
        remoteContentMode = .fill

        defer {
            remoteView?.clearDecodedVideoPreview()
            remoteView = nil
            refreshRenderingToken()
        }

        if let stream {
            try deactivateRemoteFrames(for: stream)
        }
    }

    /// 为当前远端流安装解码帧监听。
    ///
    /// - Parameter reportsError: 绑定失败时是否同时通知错误回调。
    /// - Throws: RTC 帧监听设置失败时抛出错误。
    func activateRemoteFramesIfReady(reportsError: Bool) throws {
        guard let remoteStream else { return }
        guard activeRemoteFrameStream != remoteStream else { return }
        let outputToken = renderingToken
        do {
            try rtcManager.setRemoteVideoFrameListener(
                { [weak remoteFramePipeline] frame in
                    Task {
                        await remoteFramePipeline?.enqueue(
                            frame,
                            outputToken: outputToken
                        )
                    }
                },
                for: remoteStream
            )
            activeRemoteFrameStream = remoteStream
        } catch {
            if reportsError {
                errorListener(XmaxError.from(error))
            }
            throw error
        }
    }

    /// 解除匹配远端流的解码帧监听。
    ///
    /// - Parameter stream: 需要停止监听的远端流。
    /// - Throws: RTC 帧监听解除失败时抛出错误。
    func deactivateRemoteFrames(for stream: RemoteStream) throws {
        guard activeRemoteFrameStream == stream else { return }
        try rtcManager.setRemoteVideoFrameListener(nil, for: stream)
        activeRemoteFrameStream = nil
    }

    /// 更新渲染有效期，清空旧帧并取消旧流的首帧等待。
    func refreshRenderingToken() {
        finishAllRemoteFrameReadyWaiters(
            error: Self.remoteFrameWaitCancelledError()
        )
        latestRemoteFrame = nil
        remoteVideoFrameDispatcher.invalidatePendingFrames()
        renderingToken &+= 1
        let token = renderingToken
        Task { [remoteFramePipeline] in
            await remoteFramePipeline.reset(outputToken: token)
        }
    }

    /// 缓存并分发当前有效的最终帧，同时通知首帧就绪。
    ///
    /// - Parameters:
    ///   - frame: 已经完成插帧等处理的远端视频帧。
    ///   - outputToken: 该帧所属的渲染有效期标识。
    func displayRemoteFrame(
        _ frame: RealtimeVideoFrame,
        outputToken: UInt64
    ) {
        guard outputToken == renderingToken else { return }
        latestRemoteFrame = frame
        finishAllRemoteFrameReadyWaiters()
        remoteVideoFrameDispatcher.dispatch(frame)
        if let remoteView {
            remoteView.displayRemoteVideoFrame(
                frame,
                contentMode: remoteContentMode
            )
        }
    }

    /// 结束指定首帧等待并取消其超时任务。
    ///
    /// - Parameters:
    ///   - waiterID: 需要结束的等待标识。
    ///   - error: 等待失败的原因；`nil` 表示首帧已就绪。
    func finishRemoteFrameReadyWaiter(
        _ waiterID: UUID,
        error: XmaxError? = nil
    ) {
        guard let waiter = remoteFrameReadyWaiters.removeValue(
            forKey: waiterID
        ) else {
            return
        }
        waiter.timeoutTask?.cancel()
        if let error {
            waiter.continuation.finish(throwing: error)
        } else {
            waiter.continuation.yield()
            waiter.continuation.finish()
        }
    }

    /// 结束当前全部首帧等待。
    ///
    /// - Parameter error: 等待失败的原因；`nil` 表示首帧已就绪。
    func finishAllRemoteFrameReadyWaiters(error: XmaxError? = nil) {
        let waiterIDs = Array(remoteFrameReadyWaiters.keys)
        for waiterID in waiterIDs {
            finishRemoteFrameReadyWaiter(waiterID, error: error)
        }
    }

    /// 构造远端首帧等待取消错误。
    ///
    /// - Returns: 表示首帧等待已取消的 SDK 错误。
    static func remoteFrameWaitCancelledError() -> XmaxError {
        XmaxError(
            code: .cancelled,
            message: "Remote video first frame wait was cancelled"
        )
    }
}
