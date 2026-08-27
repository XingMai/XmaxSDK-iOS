import CoreGraphics
import Foundation
import UIKit

/// 协调本地视频文件元数据、输出格式和解耦的音视频播放器。
final class MediaSourceController: MediaSourceControlling, @unchecked Sendable {

    // 默认格式
    private static let defaultFrameRate = 24

    // 基础层组件
    private let metadataManager: any MediaFileMetadataManaging

    // 服务层组件
    private let mediaService: any MediaServicing

    // 媒体源组件
    private let playerController: any VideoPlayerControlling

    // 并发控制
    private let stateLock = NSLock()

    // 媒体配置
    private var preparedMedia: PreparedMedia?

    // 运行状态
    private var isRunning = false

    init(
        metadataManager: any MediaFileMetadataManaging,
        mediaService: any MediaServicing,
        playerController: any VideoPlayerControlling
    ) {
        self.metadataManager = metadataManager
        self.mediaService = mediaService
        self.playerController = playerController
    }

    var hasAudio: Bool {
        stateLock.withLock { preparedMedia?.configuration.hasAudio ?? false }
    }

    func prepare(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> MediaSourceConfiguration {
        guard stateLock.withLock({ preparedMedia == nil }) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current media source before preparing " +
                    "another file"
            )
        }

        do {
            let metadata = try await metadataManager.readMetadata(
                fileURL: fileURL
            )
            let resolvedFormat = try resolveVideoFormat(
                metadata: metadata,
                requestedFormat: videoFormat
            )
            try await playerController.configure(
                fileURL: fileURL,
                outputWidth: resolvedFormat.width,
                outputHeight: resolvedFormat.height,
                rotation: metadata.rotation,
                frameRate: resolvedFormat.fps,
                hasAudio: metadata.hasAudio
            )

            let configuration = MediaSourceConfiguration(
                videoFormat: resolvedFormat,
                hasAudio: metadata.hasAudio
            )
            stateLock.withLock {
                preparedMedia = PreparedMedia(
                    metadata: metadata,
                    configuration: configuration
                )
            }
            return configuration
        } catch {
            throw XmaxError.from(error)
        }
    }

    func start() async throws {
        _ = try beginRunning()
        do {
            try await playerController.start()
        } catch {
            await rollbackRunning()
            throw XmaxError.from(error)
        }
    }

    func setLocalAudioPreviewEnabled(_ enabled: Bool) async throws {
        guard hasAudio else {
            return
        }
        await playerController.setLocalAudioPreviewEnabled(enabled)
    }

    @MainActor
    func attachPreview(
        to view: UIView,
        contentMode: VideoContentMode
    ) throws {
        try playerController.attachPreview(
            to: view,
            contentMode: contentMode
        )
    }

    @MainActor
    func detachPreview(from view: UIView) {
        playerController.detachPreview(from: view)
    }

    func stop() async {
        stateLock.withLock {
            isRunning = false
            preparedMedia = nil
        }
        await playerController.stop()
    }
}

private extension MediaSourceController {
    struct PreparedMedia: Sendable {
        let metadata: MediaFileMetadata
        let configuration: MediaSourceConfiguration
    }

    func beginRunning() throws -> PreparedMedia {
        try stateLock.withLock {
            guard let preparedMedia else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Prepare the media file before starting it"
                )
            }
            guard !isRunning else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Local media source is already active"
                )
            }
            isRunning = true
            return preparedMedia
        }
    }

    func rollbackRunning() async {
        stateLock.withLock {
            isRunning = false
        }
        await playerController.stop()
    }

    func resolveVideoFormat(
        metadata: MediaFileMetadata,
        requestedFormat: RealtimeVideoFormat?
    ) throws -> RealtimeVideoFormat {
        let swapsDimensions = metadata.rotation == .rotation90 ||
            metadata.rotation == .rotation270
        let displayWidth = swapsDimensions ? metadata.height : metadata.width
        let displayHeight = swapsDimensions ? metadata.width : metadata.height
        let requestedFormat = requestedFormat ?? RealtimeVideoFormat(
            width: displayWidth,
            height: displayHeight,
            fps: Self.defaultFrameRate
        )
        guard requestedFormat.fps > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video stream frame rate must be greater than zero"
            )
        }

        let targetSize = try mediaService.resolveModelInputSize(
            CGSize(
                width: requestedFormat.width,
                height: requestedFormat.height
            )
        )
        let resolvedFormat = RealtimeVideoFormat(
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            fps: requestedFormat.fps
        )
        try resolvedFormat.validate()
        return resolvedFormat
    }
}
