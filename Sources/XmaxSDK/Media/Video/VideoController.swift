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

/// Coordinates video file playback, external RTC media, and preview.
final class VideoController: VideoControlling, @unchecked Sendable {

    /// The local video file track identifier.
    private static let localVideoTrackID = "video0"

    /// The external RTC media adapter.
    private let rtcManager: any RtcManaging

    /// The video metadata reader.
    private let metadataManager: any MediaFileMetadataManaging

    /// The media sizing and default frame rate service.
    private let mediaService: any MediaServicing

    /// The file decoder, playback timeline, and preview controller.
    private let playerController: any VideoPlayerControlling

    /// The lock protecting video track creation and stopping.
    private let stateLock = NSLock()

    /// The current video file track.
    private var activeTrack: RealtimeVideoTrack?

    /// Whether the current file uses external audio input.
    private var storedHasAudio = false

    /// Creates a video playback and preview controller.
    ///
    /// - Parameters:
    ///   - rtcManager: The external RTC media adapter.
    ///   - mediaService: The model default frame rate provider.
    ///   - videoFrameListener: The video frame handler.
    ///   - audioFrameListener: The audio frame handler.
    ///   - errorListener: The playback failure handler.
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

    /// Creates a video controller with metadata, sizing, and playback dependencies.
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

    /// The active video file track, if created.
    var currentTrack: RealtimeVideoTrack? {
        stateLock.withLock {
            activeTrack
        }
    }

    /// Whether the video file contains SDK-managed audio.
    var hasAudio: Bool {
        stateLock.withLock {
            storedHasAudio
        }
    }

    /// The local video file preview volume.
    var localAudioVolume: Float {
        get async {
            await playerController.localAudioVolume
        }
    }

    /// Creates a looping local video stream.
    ///
    /// - Parameter fileURL: The URL of a readable local video file.
    ///
    /// - Returns: The local video file media stream.
    ///
    /// - Throws: An error if a stream exists, the file or format is invalid, or playback cannot
    ///   start.
    func createLocalVideoStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        guard currentTrack == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local video stream before " + "creating another one"
            )
        }

        return try await createStream(
            fileURL: fileURL
        )
    }

    /// Mutes or restores file audio preview without affecting uplink audio.
    ///
    /// - Parameter muted: `true` to mute; `false` to restore the configured preview volume.
    func setLocalAudioPreviewMuted(
        _ muted: Bool
    ) async {
        guard hasAudio else {
            return
        }
        await playerController.setLocalAudioPreviewMuted(muted)
    }

    /// Sets the local video file preview volume.
    ///
    /// - Parameter volume: The validated volume, from 0 to 1.
    func setLocalAudioVolume(
        _ volume: Float
    ) async {
        await playerController.setLocalAudioVolume(volume)
    }

    /// Stops file playback and releases external audio and preview resources.
    func stopLocalVideoStream() async {
        let state = stateLock.withLock {
            () -> (
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

    /// Starts file playback and external audio and video input.
    ///
    /// - Parameter fileURL: The local video file URL.
    ///
    /// - Returns: The local video file media stream.
    ///
    /// - Throws: An error if file preparation, external source configuration, or playback startup
    ///   fails.
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

    /// Registers playback preview for a video track.
    ///
    /// - Parameter track: The local video track to preview.
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

    /// Resolves the video media format from display orientation and model limits.
    ///
    /// - Parameter metadata: The file's encoded dimensions, orientation, and audio information.
    ///
    /// - Returns: A media format retaining display aspect ratio with the model's default frame
    ///   rate.
    ///
    /// - Throws: An error if source dimensions or the resolved format are invalid.
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
