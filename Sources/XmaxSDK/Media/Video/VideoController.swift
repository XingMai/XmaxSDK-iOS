//
//  VideoController.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics
import Foundation

/// 协调本地视频播放器、RTC 外部音视频源和预览资源。
final class VideoController: VideoControlling, @unchecked Sendable {

    /// 文件视频的本地轨道标识。
    private static let localVideoTrackID = "video0"

    /// RTC 外部媒体源适配组件。
    private let rtcManager: any RtcManaging

    /// 读取视频尺寸、方向、时长和音频轨道信息。
    private let metadataManager: any MediaFileMetadataManaging

    /// 解析媒体尺寸和模型默认帧率。
    private let mediaService: any MediaServicing

    /// 负责文件解码、播放时间轴和本地预览。
    private let playerController: any VideoPlayerControlling

    /// 保护文件视频轨道的创建与停止。
    private let stateLock = NSLock()

    /// 当前文件视频对应的本地轨道。
    private var activeTrack: RealtimeVideoTrack?

    /// 当前文件流是否已启用外部音频输入。
    private var storedHasAudio = false

    /// 创建文件解码、音视频输出和本地预览控制器。
    ///
    /// - Parameters:
    ///   - rtcManager: RTC 外部媒体源适配组件。
    ///   - mediaService: 提供模型默认帧率的服务。
    ///   - videoFrameListener: 接收视频帧的回调。
    ///   - audioFrameListener: 接收音频帧的回调。
    ///   - errorListener: 接收播放运行错误的回调。
    @MainActor
    convenience init(
        rtcManager: any RtcManaging,
        mediaService: any MediaServicing = MediaService(),
        videoFrameListener: @escaping MediaVideoFrameListener,
        audioFrameListener: @escaping MediaAudioFrameListener,
        errorListener: @escaping XmaxErrorListener
    ) {
        let playerController = VideoPlayerController(
            videoFrameListener: videoFrameListener,
            audioFrameListener: audioFrameListener,
            errorListener: errorListener
        )
        self.init(
            rtcManager: rtcManager,
            mediaService: mediaService,
            playerController: playerController
        )
    }

    /// 使用文件元数据、模型规则及播放器组件创建视频控制器。
    init(
        rtcManager: any RtcManaging,
        metadataManager: any MediaFileMetadataManaging = MediaFileMetadataManager(),
        mediaService: any MediaServicing = MediaService(),
        playerController: any VideoPlayerControlling
    ) {
        self.rtcManager = rtcManager
        self.metadataManager = metadataManager
        self.mediaService = mediaService
        self.playerController = playerController
    }

    /// 当前活动的本地文件视频轨道；尚未创建时返回空值。
    var currentTrack: RealtimeVideoTrack? {
        stateLock.withLock { activeTrack }
    }

    /// 当前文件视频是否包含由 SDK 管理的音频轨道。
    var hasAudio: Bool {
        stateLock.withLock { storedHasAudio }
    }

    /// 当前本地文件视频的音频预览音量。
    var localAudioVolume: Float {
        get async {
            await playerController.localAudioVolume
        }
    }

    /// 从本地视频文件创建循环播放的媒体流。
    ///
    /// - Parameter fileURL: 可读取的本地视频文件地址。
    /// - Returns: 包含本地文件视频轨道的媒体流。
    /// - Throws: 已有活动视频流、文件或格式无效、播放启动失败时抛出错误。
    func createLocalVideoStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        guard currentTrack == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local video stream before " +
                    "creating another one"
            )
        }

        return try await createStream(
            fileURL: fileURL
        )
    }

    /// 静音或恢复本地文件视频的音频预览，不影响上传的音频帧。
    ///
    /// - Parameter muted: 为 true 时静音，为 false 时恢复配置的预览音量。
    func setLocalAudioPreviewMuted(
        _ muted: Bool
    ) async {
        guard hasAudio else {
            return
        }
        await playerController.setLocalAudioPreviewMuted(muted)
    }

    /// 设置本地文件视频的音频预览音量。
    ///
    /// - Parameter volume: 已校验且取值范围为 0...1 的音量。
    func setLocalAudioVolume(
        _ volume: Float
    ) async {
        await playerController.setLocalAudioVolume(volume)
    }

    /// 停止文件音视频输出，并释放当前轨道、RTC 外部音频和预览资源。
    func stopLocalVideoStream() async {
        let state = stateLock.withLock { () -> (
            RealtimeVideoTrack?,
            Bool
        ) in
            let track = activeTrack
            let hasAudio = storedHasAudio
            activeTrack = nil
            storedHasAudio = false
            return (track, hasAudio)
        }
        await playerController.stop()

        if state.1 {
            do {
                try rtcManager.stopExternalAudioSource()
            } catch {
                XmaxLogger.realtime.error(
                    message: """
                    停止 RTC 外部音频源失败 (Failed to Stop RTC External Audio Source)
                    └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                    """
                )
            }
        }
        if let track = state.0 {
            await MainActor.run {
                VideoRenderRegistry.unregister(track)
            }
        }
    }
}

private extension VideoController {

    /// 准备文件视频并启动外部音视频源及循环播放。
    ///
    /// - Parameter fileURL: 待播放的本地视频文件地址。
    /// - Returns: 持有文件视频轨道的本地媒体流。
    /// - Throws: 文件准备、外部源配置或播放启动失败时抛出错误。
    func createStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        var track: RealtimeVideoTrack?
        var externalAudioStarted = false

        do {
            let metadata = try await metadataManager.readMetadata(
                fileURL: fileURL
            )
            let videoFormat = try resolveVideoFormat(metadata: metadata)
            try Task.checkCancellation()
            try await playerController.configure(
                fileURL: fileURL,
                outputWidth: videoFormat.width,
                outputHeight: videoFormat.height,
                rotation: metadata.rotation,
                frameRate: videoFormat.fps,
                hasAudio: metadata.hasAudio,
                durationSeconds: metadata.durationSeconds
            )
            let localTrack = RealtimeVideoTrack(
                id: Self.localVideoTrackID,
                videoFormat: videoFormat
            )
            track = localTrack

            try rtcManager.useExternalVideoSource()
            if metadata.hasAudio {
                try rtcManager.startExternalAudioSource()
                externalAudioStarted = true
            }
            await registerPreview(for: localTrack)
            try await playerController.start()
            try Task.checkCancellation()
            stateLock.withLock {
                activeTrack = localTrack
                storedHasAudio = metadata.hasAudio
            }

            return RealtimeMediaStream(
                id: StreamID.local.rawValue,
                videoTrack: localTrack
            )
        } catch {
            await playerController.stop()
            if externalAudioStarted {
                do {
                    try rtcManager.stopExternalAudioSource()
                } catch {
                    XmaxLogger.realtime.error(
                        message: """
                        回滚 RTC 外部音频源失败 (Failed to Roll Back RTC External Audio Source)
                        └─ \(XmaxLogger.localized("原因：", "Reason: "))\((error as NSError).localizedDescription)
                        """
                    )
                }
            }
            if let track {
                await MainActor.run {
                    VideoRenderRegistry.unregister(track)
                }
            }
            throw XmaxError.from(error)
        }
    }

    /// 为文件视频轨道注册播放器预览绑定。
    ///
    /// - Parameter track: 需要绑定预览的本地视频轨道。
    @MainActor
    func registerPreview(
        for track: RealtimeVideoTrack
    ) {
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(
                attachHandler: { view, contentMode in
                    try self.playerController.attachPreview(
                        to: view,
                        contentMode: contentMode
                    )
                },
                detachHandler: { view in
                    self.playerController.detachPreview(from: view)
                }
            )
        )
    }

    /// 根据视频显示方向和模型面积上限计算媒体规格。
    ///
    /// - Parameter metadata: 源文件的编码尺寸、方向及音频信息。
    /// - Returns: 保留显示比例并采用模型默认帧率的媒体规格。
    /// - Throws: 原始尺寸或解析结果无效时抛出错误。
    func resolveVideoFormat(
        metadata: MediaFileMetadata
    ) throws -> RealtimeVideoFormat {
        let swapsDimensions = metadata.rotation == .rotation90 || metadata.rotation == .rotation270
        let size = try mediaService.resolveMediaSize(
            CGSize(
                width: swapsDimensions ? metadata.height : metadata.width,
                height: swapsDimensions ? metadata.width : metadata.height
            ),
            source: .video
        )
        let format = RealtimeVideoFormat(
            width: Int(size.width),
            height: Int(size.height),
            fps: mediaService.model.defaultFrameRate
        )
        try format.validate()
        return format
    }
}
