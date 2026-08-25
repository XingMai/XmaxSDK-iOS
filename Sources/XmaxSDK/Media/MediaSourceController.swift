import CoreGraphics
import Foundation

/// 协调本地视频文件的元数据、共享时间线和音视频循环输出。
final class MediaSourceController: MediaSourceControlling, @unchecked Sendable {

    // 默认格式
    private static let defaultFrameRate = 24

    // 基础层组件
    private let metadataProvider: any MediaFileMetadataProviding
    private let audioProvider: any AudioProviding

    // 服务层组件
    private let mediaService: any MediaServicing

    // 媒体源组件
    private let videoSourceController: any VideoSourceControlling
    private let audioSourceController: any AudioSourceControlling

    // 并发控制
    private let stateLock = NSLock()

    // 媒体配置
    private var preparedMedia: PreparedMedia?

    // 运行状态
    private var isRunning = false

    init(
        metadataProvider: any MediaFileMetadataProviding,
        audioProvider: any AudioProviding,
        mediaService: any MediaServicing,
        videoSourceController: any VideoSourceControlling,
        audioSourceController: any AudioSourceControlling
    ) {
        self.metadataProvider = metadataProvider
        self.audioProvider = audioProvider
        self.mediaService = mediaService
        self.videoSourceController = videoSourceController
        self.audioSourceController = audioSourceController
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
            let metadata = try await metadataProvider.readMetadata(
                fileURL: fileURL
            )
            let resolvedFormat = try resolveVideoFormat(
                metadata: metadata,
                requestedFormat: videoFormat
            )
            try videoSourceController.configure(
                fileURL: fileURL,
                rotation: metadata.rotation,
                frameRate: resolvedFormat.fps
            )
            if metadata.hasAudio {
                try audioSourceController.configure(fileURL: fileURL)
            }

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
        let preparedMedia = try beginRunning()
        do {
            try await startSources(preparedMedia: preparedMedia)
        } catch {
            await rollbackRunning()
            throw XmaxError.from(error)
        }
    }

    func restart() async throws {
        let preparedMedia = try stateLock.withLock { () -> PreparedMedia in
            guard isRunning, let preparedMedia else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Start the media source before restarting it"
                )
            }
            return preparedMedia
        }

        do {
            if preparedMedia.configuration.hasAudio {
                try await audioProvider.flush()
            }
            let timeline = try MediaTimeline(
                durationUs: preparedMedia.metadata.durationUs
            )
            async let videoRestart: Void = videoSourceController.restart(
                timeline: timeline
            )
            async let audioRestart: Void = restartAudioIfNeeded(
                timeline: timeline,
                hasAudio: preparedMedia.configuration.hasAudio
            )
            _ = try await (videoRestart, audioRestart)
        } catch {
            throw XmaxError.from(error)
        }
    }

    func stop() async {
        stateLock.withLock {
            isRunning = false
            preparedMedia = nil
        }
        videoSourceController.stop()
        audioSourceController.stop()
        await audioProvider.stop()
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

    func startSources(preparedMedia: PreparedMedia) async throws {
        if preparedMedia.configuration.hasAudio {
            try await audioProvider.start()
        }
        let timeline = try MediaTimeline(
            durationUs: preparedMedia.metadata.durationUs
        )
        async let videoStart: Void = videoSourceController.start(
            timeline: timeline
        )
        async let audioStart: Void = startAudioIfNeeded(
            timeline: timeline,
            hasAudio: preparedMedia.configuration.hasAudio
        )
        _ = try await (videoStart, audioStart)
    }

    func startAudioIfNeeded(
        timeline: MediaTimeline,
        hasAudio: Bool
    ) async throws {
        guard hasAudio else {
            return
        }
        try await audioSourceController.start(timeline: timeline)
    }

    func restartAudioIfNeeded(
        timeline: MediaTimeline,
        hasAudio: Bool
    ) async throws {
        guard hasAudio else {
            return
        }
        try await audioSourceController.restart(timeline: timeline)
    }

    func rollbackRunning() async {
        stateLock.withLock {
            isRunning = false
        }
        videoSourceController.stop()
        audioSourceController.stop()
        await audioProvider.stop()
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
