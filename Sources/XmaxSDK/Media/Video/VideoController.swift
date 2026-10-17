//
//  VideoController.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 协调本地视频播放器、RTC 外部音视频源和预览资源。
final class VideoController: VideoControlling, @unchecked Sendable {

    // 轨道标识
    private static let localVideoTrackID = "video0"


    // 基础层组件
    private let rtcManager: any RtcManaging
    private let permissionManager: any PermissionManaging


    // 业务层组件
    private let mediaSourceController: any MediaSourceControlling


    // 并发控制
    private let stateLock = NSLock()


    // 本地资源
    private var activeTrack: RealtimeVideoTrack?

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
        let mediaSourceController = MediaSourceController(
            metadataManager: MediaFileMetadataManager(),
            mediaService: mediaService,
            playerController: playerController
        )
        self.init(
            rtcManager: rtcManager,
            permissionManager: PermissionManager(),
            mediaSourceController: mediaSourceController
        )
    }

    /// 使用指定媒体源和权限组件创建视频控制器。
    ///
    /// - Parameters:
    ///   - rtcManager: RTC 外部媒体源适配组件。
    ///   - permissionManager: 音频使用所需的权限组件。
    ///   - mediaSourceController: 负责文件准备与播放的媒体源组件。
    init(
        rtcManager: any RtcManaging,
        permissionManager: any PermissionManaging,
        mediaSourceController: any MediaSourceControlling
    ) {
        self.rtcManager = rtcManager
        self.permissionManager = permissionManager
        self.mediaSourceController = mediaSourceController
    }


    // 本地媒体状态
    /// 当前活动的本地文件视频轨道；尚未创建时返回空值。
    var currentTrack: RealtimeVideoTrack? {
        stateLock.withLock { activeTrack }
    }

    /// 当前文件视频是否包含由 SDK 管理的音频轨道。
    var hasAudio: Bool {
        currentTrack != nil && mediaSourceController.hasAudio
    }


    // 音频预览
    /// 当前本地文件视频的音频预览音量。
    var localAudioVolume: Float {
        get async {
            await mediaSourceController.localAudioVolume
        }
    }

    /// 从本地视频文件创建循环播放的媒体流。
    ///
    /// - Parameter fileURL: 可读取的本地视频文件地址。
    /// - Returns: 包含本地文件视频轨道的媒体流。
    /// - Throws: 已有活动视频流、文件或格式无效、权限不足或播放启动失败时抛出错误。
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
    func setLocalAudioPreviewMuted(_ muted: Bool) async {
        guard currentTrack != nil else {
            return
        }
        await mediaSourceController.setLocalAudioPreviewMuted(muted)
    }

    /// 设置本地文件视频的音频预览音量。
    ///
    /// - Parameter volume: 已校验且取值范围为 0...1 的音量。
    func setLocalAudioVolume(_ volume: Float) async {
        await mediaSourceController.setLocalAudioVolume(volume)
    }

    /// 停止文件音视频输出，并释放当前轨道、RTC 外部音频和预览资源。
    func stopLocalVideoStream() async {
        let state = stateLock.withLock { () -> (
            RealtimeVideoTrack?,
            Bool
        ) in
            let track = activeTrack
            let hasAudio = track != nil && mediaSourceController.hasAudio
            activeTrack = nil
            return (track, hasAudio)
        }
        await mediaSourceController.stop()

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
    /// - Throws: 文件准备、权限检查、外部源配置或播放启动失败时抛出错误。
    func createStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        var track: RealtimeVideoTrack?
        var externalAudioStarted = false

        do {
            let configuration = try await mediaSourceController.prepare(
                fileURL: fileURL
            )
            let localTrack = RealtimeVideoTrack(
                id: Self.localVideoTrackID,
                videoFormat: configuration.videoFormat
            )
            track = localTrack

            if configuration.hasAudio {
                try await permissionManager.ensureMicrophonePermission()
            }
            try rtcManager.useExternalVideoSource()
            if configuration.hasAudio {
                try rtcManager.startExternalAudioSource()
                externalAudioStarted = true
            }
            await registerPreview(for: localTrack)
            try await mediaSourceController.start()
            stateLock.withLock {
                activeTrack = localTrack
            }

            return RealtimeMediaStream(
                id: StreamID.local.rawValue,
                videoTrack: localTrack
            )
        } catch {
            await mediaSourceController.stop()
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
    func registerPreview(for track: RealtimeVideoTrack) {
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(
                attachHandler: { view, contentMode in
                    try self.mediaSourceController.attachPreview(
                        to: view,
                        contentMode: contentMode
                    )
                },
                detachHandler: { view in
                    self.mediaSourceController.detachPreview(from: view)
                }
            )
        )
    }
}
