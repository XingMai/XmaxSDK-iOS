//
//  ExternalVideoController.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 将外部视频源绑定到 SDK 的本地预览及 RTC 帧链路。
final class ExternalVideoController: ExternalVideoControlling, @unchecked Sendable {

    /// 配置 RTC 外部视频输入。
    private let rtcManager: any RtcManaging

    /// 解析模型面积上限及媒体尺寸。
    private let mediaService: any MediaServicing

    /// 将视频帧交付给传输层。
    private let videoFrameListener: MediaVideoFrameListener

    /// 将媒体错误交付给生命周期协调器。
    private let errorListener: XmaxErrorListener

    /// 保护跨线程读取的当前轨道。
    private let lock = NSLock()

    /// 当前外部源对应的视频轨道。
    private var track: RealtimeVideoTrack?

    /// 本次绑定的外部源，生命周期由主线程管理。
    @MainActor private var source: (any RealtimeExternalVideoSource)?

    /// 本次绑定的同步供帧入口。
    @MainActor private var sink: ExternalVideoFrameSink?

    /// 当前预览呈现组件。
    @MainActor private var presenter: DecodedVideoPreviewPresenter?

    /// 合并主线程未处理的预览帧。
    @MainActor private var dispatcher: DecodedVideoPreviewDispatcher?

    /// 创建外部视频生命周期及预览控制器。
    init(
        rtcManager: any RtcManaging,
        mediaService: any MediaServicing,
        videoFrameListener: @escaping MediaVideoFrameListener,
        errorListener: @escaping XmaxErrorListener
    ) {
        self.rtcManager = rtcManager
        self.mediaService = mediaService
        self.videoFrameListener = videoFrameListener
        self.errorListener = errorListener
    }

    /// 当前有效的外部视频轨道。
    var currentTrack: RealtimeVideoTrack? {
        lock.withLock { track }
    }

    /// 解析源规格，注册预览并绑定供帧；失败时撤销部分创建的资源。
    ///
    /// - Parameter source: 接入方拥有的视频源。
    /// - Returns: 可绑定 SDK 视频视图的本地媒体流。
    /// - Throws: 规格、RTC 配置或源绑定失败，以及取消时抛出错误。
    @MainActor
    func createExternalVideoStream(
        source: any RealtimeExternalVideoSource
    ) async throws -> RealtimeMediaStream {
        guard self.source == nil else {
            throw XmaxError(code: .invalidConfiguration, message: "Stop the current external video stream before creating another one")
        }
        let requested = source.videoFormat
        try requested.validate()
        let size = try mediaService.resolveMediaSize(
            CGSize(width: requested.width, height: requested.height),
            source: .external
        )
        let format = requested.resized(width: Int(size.width), height: Int(size.height))
        try format.validate()
        try Task.checkCancellation()

        let track = RealtimeVideoTrack(id: "external0", videoFormat: format)
        let presenter = DecodedVideoPreviewPresenter()
        let dispatcher = DecodedVideoPreviewDispatcher(presenter: presenter)
        let sink = ExternalVideoFrameSink(
            videoFormat: format,
            frameListener: { [videoFrameListener] frame in
                dispatcher.enqueue(frame)
                try videoFrameListener(frame)
            },
            errorListener: errorListener
        )
        self.source = source
        self.sink = sink
        self.presenter = presenter
        self.dispatcher = dispatcher
        lock.withLock { self.track = track }

        do {
            try rtcManager.useExternalVideoSource()
            VideoRenderRegistry.register(track, binding: VideoRenderBinding(
                attachHandler: { view, contentMode in
                    guard let view = view as? XmaxVideoView else {
                        throw XmaxError(code: .invalidConfiguration, message: "External video tracks require an XmaxVideoView")
                    }
                    presenter.attach(to: view, contentMode: contentMode)
                },
                detachHandler: { view in
                    if let view = view as? XmaxVideoView { presenter.detach(from: view) }
                }
            ))
            try await source.start(sink: sink)
            try Task.checkCancellation()
            guard sink.isRequestingFrames else {
                throw XmaxError(code: .mediaError, message: "External video source failed during setup")
            }
            return RealtimeMediaStream(id: StreamID.local.rawValue, videoTrack: track)
        } catch {
            await stopExternalVideoStream()
            throw XmaxError.from(error)
        }
    }

    /// 先使供帧入口失效，再清除预览并通知接入方解绑。
    @MainActor
    func stopExternalVideoStream() async {
        sink?.invalidate()
        sink = nil
        dispatcher?.reset()
        dispatcher = nil
        presenter?.clear()
        presenter = nil
        let previousSource = source
        source = nil
        let previousTrack = lock.withLock {
            let previous = track
            track = nil
            return previous
        }
        if let previousTrack {
            do {
                try VideoRenderRegistry.binding(for: previousTrack)?.detach()
            } catch {
                XmaxLogger.media.error(message: "解除外部视频预览失败 (Failed to Detach External Video Preview)\n└─ \(error.localizedDescription)")
            }
            VideoRenderRegistry.unregister(previousTrack)
        }
        await previousSource?.stop()
    }
}
