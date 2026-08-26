import Foundation

/// 协调本地图片解码、循环帧输出、编码和预览资源。
final class XmaxRealtimeImageManager: @unchecked Sendable {

    // 轨道标识
    private static let localVideoTrackID = "video0"

    // 基础层组件
    private let rtcProvider: any RtcProviding

    // 业务层组件
    private let imageSourceController: any ImageSourceControlling
    private let encodingController: any EncodingControlling

    // 并发控制
    private let stateLock = NSLock()

    // 本地资源
    private var activeTrack: RealtimeVideoTrack?

    @MainActor
    convenience init(
        rtcProvider: any RtcProviding,
        streamController: any StreamControlling,
        errorListener: @escaping ImageSourceErrorListener
    ) {
        let imageProvider = ImageProvider()
        self.init(
            rtcProvider: rtcProvider,
            imageSourceController: ImageSourceController(
                imageProvider: imageProvider,
                mediaService: MediaService(),
                frameListener: { frame in
                    try streamController.pushLocalVideoFrame(frame)
                },
                errorListener: errorListener
            ),
            encodingController: EncodingController(rtcProvider: rtcProvider)
        )
    }

    init(
        rtcProvider: any RtcProviding,
        imageSourceController: any ImageSourceControlling,
        encodingController: any EncodingControlling
    ) {
        self.rtcProvider = rtcProvider
        self.imageSourceController = imageSourceController
        self.encodingController = encodingController
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

private extension XmaxRealtimeImageManager {
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
            let resolvedFormat: RealtimeVideoFormat
            switch input {
            case .data(let imageData):
                resolvedFormat = try await imageSourceController.prepare(
                    imageData: imageData,
                    videoFormat: videoFormat
                )
            case .decoded(let decodedImage):
                resolvedFormat = try await imageSourceController.prepare(
                    decodedImage: decodedImage,
                    videoFormat: videoFormat
                )
            case .file(let fileURL):
                resolvedFormat = try await imageSourceController.prepare(
                    fileURL: fileURL,
                    videoFormat: videoFormat
                )
            }
            let localTrack = RealtimeVideoTrack(
                id: Self.localVideoTrackID,
                videoFormat: resolvedFormat
            )
            track = localTrack

            try encodingController.configure(resolvedFormat)
            try rtcProvider.useExternalVideoSource()
            await registerPreview(for: localTrack)
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
