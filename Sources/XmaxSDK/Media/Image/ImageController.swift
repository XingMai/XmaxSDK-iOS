import Foundation

/// 协调本地图片解码、循环帧输出和预览资源。
final class ImageController: @unchecked Sendable {

    // 轨道标识
    private static let localVideoTrackID = "video0"

    // 基础层组件
    private let rtcManager: any RtcManaging

    // 业务层组件
    private let imageSourceController: any ImageSourceControlling

    // 并发控制
    private let stateLock = NSLock()

    // 本地资源
    private var activeTrack: RealtimeVideoTrack?

    @MainActor
    convenience init(
        rtcManager: any RtcManaging,
        frameListener: @escaping MediaVideoFrameListener,
        errorListener: @escaping XmaxErrorListener
    ) {
        let imageManager = ImageManager()
        self.init(
            rtcManager: rtcManager,
            imageSourceController: ImageSourceController(
                imageManager: imageManager,
                mediaService: MediaService(),
                frameListener: frameListener,
                errorListener: errorListener
            )
        )
    }

    init(
        rtcManager: any RtcManaging,
        imageSourceController: any ImageSourceControlling
    ) {
        self.rtcManager = rtcManager
        self.imageSourceController = imageSourceController
    }

    /// 当前活动的本地图片视频轨道；尚未创建时返回空值。
    var currentTrack: RealtimeVideoTrack? {
        stateLock.withLock { activeTrack }
    }

    /// 从已经解码的图片创建持续输出帧的媒体流。
    func createLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard currentTrack == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local image stream before " +
                    "creating another one"
            )
        }

        return try await createStream(
            input: .decoded(decodedImage),
            videoFormat: videoFormat
        )
    }

    /// 从编码后的图片数据创建持续输出帧的媒体流。
    func createLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard currentTrack == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local image stream before " +
                    "creating another one"
            )
        }

        return try await createStream(
            input: .data(imageData),
            videoFormat: videoFormat
        )
    }

    /// 从本地图片文件创建持续输出帧的媒体流。
    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        guard currentTrack == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local image stream before " +
                    "creating another one"
            )
        }

        return try await createStream(
            input: .file(fileURL),
            videoFormat: videoFormat
        )
    }

    /// 停止图片帧输出并释放本地预览绑定。
    func stopLocalImageStream() async {
        let track = stateLock.withLock { () -> RealtimeVideoTrack? in
            let track = activeTrack
            activeTrack = nil
            return track
        }
        imageSourceController.stop()

        if let track {
            await MainActor.run {
                do {
                    try VideoRenderRegistry.binding(for: track)?.detach()
                } catch {
                    Self.logCleanupFailure(
                        title: "解除本地图片预览绑定失败 (Failed to Detach Local Image Preview)",
                        error: error
                    )
                }
                VideoRenderRegistry.unregister(track)
            }
        }
    }
}

private extension ImageController {
    enum ImageInput: Sendable {
        case data(Data)
        case decoded(any DecodedImage)
        case file(URL)
    }

    func createStream(
        input: ImageInput,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        var track: RealtimeVideoTrack?

        do {
            let preparedSource: (
                videoFormat: RealtimeVideoFormat,
                previewFrame: VideoFrame
            )
            switch input {
            case .data(let imageData):
                preparedSource = try await imageSourceController.prepare(
                    imageData: imageData,
                    videoFormat: videoFormat
                )
            case .decoded(let decodedImage):
                preparedSource = try await imageSourceController.prepare(
                    decodedImage: decodedImage,
                    videoFormat: videoFormat
                )
            case .file(let fileURL):
                preparedSource = try await imageSourceController.prepare(
                    fileURL: fileURL,
                    videoFormat: videoFormat
                )
            }
            let localTrack = RealtimeVideoTrack(
                id: Self.localVideoTrackID,
                videoFormat: preparedSource.videoFormat
            )
            track = localTrack

            try rtcManager.useExternalVideoSource()
            await registerPreview(
                for: localTrack,
                frame: preparedSource.previewFrame
            )
            try imageSourceController.start()
            stateLock.withLock {
                activeTrack = localTrack
            }

            return RealtimeMediaStream(
                id: StreamID.local.rawValue,
                videoTrack: localTrack
            )
        } catch {
            imageSourceController.stop()
            if let track {
                await MainActor.run {
                    VideoRenderRegistry.unregister(track)
                }
            }
            throw XmaxError.from(error)
        }
    }

    @MainActor
    func registerPreview(
        for track: RealtimeVideoTrack,
        frame: VideoFrame
    ) {
        VideoRenderRegistry.register(
            track,
            binding: VideoRenderBinding(imageFrame: frame)
        )
    }

    static func logCleanupFailure(
        title: String,
        error: any Error
    ) {
        XmaxLogger.error(
            category: "Realtime",
            message: "\(title)\n└─ 原因：" +
                (error as NSError).localizedDescription
        )
    }
}
