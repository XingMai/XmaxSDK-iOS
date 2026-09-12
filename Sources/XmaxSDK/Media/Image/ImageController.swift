import CoreGraphics
import Foundation

/// 协调本地图片解码、循环帧输出和预览资源。
final class ImageController: ImageControlling, @unchecked Sendable {

    // 轨道标识
    private static let localVideoTrackID = "video0"

    // 基础层组件
    private let rtcManager: any RtcManaging
    private let imageManager: any ImageManaging

    // 服务层组件
    private let mediaService: any MediaServicing

    // 事件监听
    private let frameListener: MediaVideoFrameListener

    // 并发控制
    private let stateLock = NSLock()

    // 本地资源
    private var activeTrack: RealtimeVideoTrack?
    private var outputTask: Task<Void, Never>?

    init(
        rtcManager: any RtcManaging,
        imageManager: any ImageManaging = ImageManager(),
        mediaService: any MediaServicing = MediaService(),
        frameListener: @escaping MediaVideoFrameListener
    ) {
        self.rtcManager = rtcManager
        self.imageManager = imageManager
        self.mediaService = mediaService
        self.frameListener = frameListener
    }

    var currentTrack: RealtimeVideoTrack? {
        stateLock.withLock { activeTrack }
    }

    func createLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        try await createStream(input: .decoded(decodedImage), videoFormat: videoFormat)
    }

    func createLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        try await createStream(input: .data(imageData), videoFormat: videoFormat)
    }

    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        try await createStream(input: .file(fileURL), videoFormat: videoFormat)
    }

    func stopLocalImageStream() async {
        let (track, task) = stateLock.withLock {
            let resources = (activeTrack, outputTask)
            activeTrack = nil
            outputTask = nil
            return resources
        }

        task?.cancel()
        await task?.value

        if let track {
            await MainActor.run {
                do {
                    try VideoRenderRegistry.binding(for: track)?.detach()
                } catch {
                    XmaxLogger.realtime.error(
                        message: "解除本地图片预览绑定失败 (Failed to Detach Local Image Preview)\n" +
                            "└─ \(XmaxLogger.localized("原因：", "Reason: "))" + (error as NSError).localizedDescription
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
        guard currentTrack == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local image stream before creating another one"
            )
        }

        var track: RealtimeVideoTrack?

        do {
            let image = try decode(input)
            let resolvedFormat = try resolveVideoFormat(
                sourceSize: image.size,
                requestedFormat: videoFormat
            )
            let frame = try image.makeVideoFrame(
                width: resolvedFormat.width,
                height: resolvedFormat.height
            )
            let localTrack = RealtimeVideoTrack(
                id: Self.localVideoTrackID,
                videoFormat: resolvedFormat
            )
            track = localTrack

            try rtcManager.useExternalVideoSource()
            await MainActor.run {
                VideoRenderRegistry.register(
                    localTrack,
                    binding: VideoRenderBinding(imageFrame: frame)
                )
            }

            try emitFrame(frame)
            let task = startFrameOutput(frame: frame, frameRate: resolvedFormat.fps)
            stateLock.withLock {
                activeTrack = localTrack
                outputTask = task
            }

            return RealtimeMediaStream(
                id: StreamID.local.rawValue,
                videoTrack: localTrack
            )
        } catch {
            if let track {
                await MainActor.run {
                    VideoRenderRegistry.unregister(track)
                }
            }

            throw XmaxError.from(error)
        }
    }

    func decode(_ input: ImageInput) throws -> any DecodedImage {
        let data: Data

        switch input {
        case .decoded(let image):
            return image
        case .data(let imageData):
            data = imageData
        case .file(let fileURL):
            guard fileURL.isFileURL, !fileURL.path.isEmpty else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Local image file URL must reference a file"
                )
            }

            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        }

        guard !data.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image source data must not be empty"
            )
        }

        return try imageManager.decode(data)
    }

    func resolveVideoFormat(
        sourceSize: CGSize,
        requestedFormat: RealtimeVideoFormat?
    ) throws -> RealtimeVideoFormat {
        let requestedFormat = requestedFormat ?? RealtimeVideoFormat(
            width: Int(sourceSize.width),
            height: Int(sourceSize.height),
            fps: mediaService.model.defaultFrameRate
        )
        guard requestedFormat.fps > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image stream frame rate must be greater than zero"
            )
        }

        let targetSize = try mediaService.resolveModelInputSize(
            CGSize(width: requestedFormat.width, height: requestedFormat.height)
        )
        let resolvedFormat = requestedFormat.resized(
            width: Int(targetSize.width),
            height: Int(targetSize.height)
        )
        try resolvedFormat.validate()
        return resolvedFormat
    }

    func startFrameOutput(frame: VideoFrame, frameRate: Int) -> Task<Void, Never> {
        let interval = max(UInt64(1000000000 / frameRate), 1)

        return Task.detached { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                guard !Task.isCancelled, let self else {
                    return
                }

                do {
                    try self.emitFrame(frame)
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    XmaxLogger.media.error(message: "图片帧推送失败 (Image Frame Push Failed)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))\(error.localizedDescription)")
                }
            }
        }
    }

    func emitFrame(_ frame: VideoFrame) throws {
        let timestampUs = Int64(
            min(
                DispatchTime.now().uptimeNanoseconds / 1000,
                UInt64(Int64.max)
            )
        )
        try frameListener(try frame.updating(timestampUs: timestampUs))
    }
}
