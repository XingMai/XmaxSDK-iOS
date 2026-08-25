import Foundation

/// 协调本地视频文件解码、音视频循环、编码和 RTC 预览资源。
final class XmaxRealtimeVideoManager: @unchecked Sendable {

    // 轨道标识
    private static let localVideoTrackID = "video0"

    // 基础层组件
    private let rtcProvider: any RtcProviding
    private let permissionProvider: any PermissionProviding

    // 业务层组件
    private let mediaSourceController: any MediaSourceControlling
    private let encodingController: any EncodingControlling

    // 并发控制
    private let stateLock = NSLock()

    // 本地资源
    private var activeTrack: RealtimeVideoTrack?

    @MainActor
    convenience init(
        rtcProvider: any RtcProviding,
        streamController: any StreamControlling,
        errorListener: @escaping MediaSourceErrorListener
    ) {
        let audioProvider = AudioProvider()
        let mediaSourceController = MediaSourceController(
            metadataProvider: MediaFileMetadataProvider(),
            audioProvider: audioProvider,
            mediaService: MediaService(),
            videoSourceController: VideoSourceController(
                frameListener: { frame in
                    try streamController.pushLocalVideoFrame(frame)
                },
                errorListener: errorListener
            ),
            audioSourceController: AudioSourceController(
                frameListener: { frame in
                    audioProvider.write(frame: frame)
                    try streamController.pushLocalAudioFrame(frame)
                },
                errorListener: errorListener
            )
        )
        self.init(
            rtcProvider: rtcProvider,
            permissionProvider: PermissionProvider(),
            mediaSourceController: mediaSourceController,
            encodingController: EncodingController(rtcProvider: rtcProvider)
        )
    }

    init(
        rtcProvider: any RtcProviding,
        permissionProvider: any PermissionProviding,
        mediaSourceController: any MediaSourceControlling,
        encodingController: any EncodingControlling
    ) {
        self.rtcProvider = rtcProvider
        self.permissionProvider = permissionProvider
        self.mediaSourceController = mediaSourceController
        self.encodingController = encodingController
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

    /// 从文件起点重新开始音视频循环，用于新一轮生成。
    func restartForGeneration() async throws {
        guard currentTrack != nil else {
            return
        }
        try await mediaSourceController.restart()
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
                try rtcProvider.stopExternalAudioSource()
            } catch {
                Self.logCleanupFailure(
                    operation: "停止 RTC 外部音频源",
                    error: error
                )
            }
        }
        if let track = state.0 {
            await MainActor.run {
                VideoRenderRegistry.unregister(track)
                do {
                    try rtcProvider.unbindLocalVideo()
                } catch {
                    Self.logCleanupFailure(
                        operation: "解除 RTC 本地预览绑定",
                        error: error
                    )
                }
            }
        }
    }
}

private extension XmaxRealtimeVideoManager {
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
                try await permissionProvider.ensureMicrophonePermission()
            }
            try encodingController.configure(configuration.videoFormat)
            try rtcProvider.useExternalVideoSource()
            if configuration.hasAudio {
                try rtcProvider.startExternalAudioSource()
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
                    try rtcProvider.stopExternalAudioSource()
                } catch {
                    Self.logCleanupFailure(
                        operation: "回滚 RTC 外部音频源",
                        error: error
                    )
                }
            }
            if let track {
                await MainActor.run {
                    VideoRenderRegistry.unregister(track)
                    do {
                        try rtcProvider.unbindLocalVideo()
                    } catch {
                        Self.logCleanupFailure(
                            operation: "回滚 RTC 本地预览绑定",
                            error: error
                        )
                    }
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
                libraryName: rtcProvider.renderLibraryName,
                attachHandler: { view, contentMode in
                    try self.rtcProvider.bindLocalVideo(
                        to: view,
                        contentMode: contentMode
                    )
                },
                detachHandler: {
                    try self.rtcProvider.unbindLocalVideo()
                }
            )
        )
    }

    static func logCleanupFailure(
        operation: String,
        error: any Error
    ) {
        XmaxLogger.error(
            "\(operation)失败\n└─ 原因：" +
                (error as NSError).localizedDescription,
            category: "Realtime"
        )
    }
}
