import Foundation

/// 协调本地视频播放器、RTC 外部音视频源和预览资源。
final class VideoController: @unchecked Sendable {

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

    @MainActor
    convenience init(
        rtcManager: any RtcManaging,
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
            mediaService: MediaService(),
            playerController: playerController
        )
        self.init(
            rtcManager: rtcManager,
            permissionManager: PermissionManager(),
            mediaSourceController: mediaSourceController
        )
    }

    init(
        rtcManager: any RtcManaging,
        permissionManager: any PermissionManaging,
        mediaSourceController: any MediaSourceControlling
    ) {
        self.rtcManager = rtcManager
        self.permissionManager = permissionManager
        self.mediaSourceController = mediaSourceController
    }

    /// 当前活动的本地文件视频轨道；尚未创建时返回空值。
    var currentTrack: RealtimeVideoTrack? {
        stateLock.withLock { activeTrack }
    }

    /// 当前文件视频是否包含由 SDK 管理的音频轨道。
    var hasAudio: Bool {
        currentTrack != nil && mediaSourceController.hasAudio
    }

    /// 从本地视频文件创建循环播放的媒体流。
    func createLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard currentTrack == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local video stream before " +
                    "creating another one"
            )
        }

        return try await createStream(
            fileURL: fileURL,
            videoFormat: videoFormat
        )
    }

    /// 静音或恢复本地文件视频的音频预览。
    func setLocalAudioPreviewMuted(_ muted: Bool) async throws {
        guard currentTrack != nil else {
            return
        }
        try await mediaSourceController.setLocalAudioPreviewMuted(muted)
    }

    /// 停止文件音视频输出并释放 RTC 外部音频和预览资源。
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
                Self.logCleanupFailure(
                    title: "停止 RTC 外部音频源失败 (Failed to Stop RTC External Audio Source)",
                    error: error
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
    func createStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        var track: RealtimeVideoTrack?
        var externalAudioStarted = false

        do {
            let configuration = try await mediaSourceController.prepare(
                fileURL: fileURL,
                videoFormat: videoFormat
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
                    Self.logCleanupFailure(
                        title: "回滚 RTC 外部音频源失败 (Failed to Roll Back RTC External Audio Source)",
                        error: error
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

    @MainActor
    func registerPreview(for track: RealtimeVideoTrack) {
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(
                libraryName: "AVFoundation",
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

    static func logCleanupFailure(
        title: String,
        error: any Error
    ) {
        XmaxLogger.error(
            "\(title)\n└─ 原因：" +
                (error as NSError).localizedDescription,
            category: "Realtime"
        )
    }
}
