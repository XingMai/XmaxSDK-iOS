import CoreGraphics
import Foundation

/// 将本地图片处理为目标尺寸，并按固定帧率持续输出视频帧。
final class ImageSourceController: ImageSourceControlling, @unchecked Sendable {

    // 默认格式
    private static let defaultFrameRate = 24

    // 基础层组件
    private let imageManager: any ImageManaging

    // 服务层组件
    private let mediaService: any MediaServicing

    // 图片帧监听器
    private let frameListener: ImageSourceFrameListener
    private let errorListener: ImageSourceErrorListener

    // 并发控制
    private let stateLock = NSLock()

    // 图片帧资源
    private var preparedFrame: PreparedFrame?

    // 运行状态
    private var isRunning = false
    private var outputTask: Task<Void, Never>?

    init(
        imageManager: any ImageManaging,
        mediaService: any MediaServicing,
        frameListener: @escaping ImageSourceFrameListener,
        errorListener: @escaping ImageSourceErrorListener
    ) {
        self.imageManager = imageManager
        self.mediaService = mediaService
        self.frameListener = frameListener
        self.errorListener = errorListener
    }

    func prepare(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeVideoFormat {
        guard fileURL.isFileURL, !fileURL.path.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Local image file URL must reference a file"
            )
        }

        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            return try await prepare(
                imageData: data,
                videoFormat: videoFormat
            )
        } catch {
            throw XmaxError.from(error)
        }
    }

    func prepare(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeVideoFormat {
        guard !imageData.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image source data must not be empty"
            )
        }

        do {
            return try await prepare(
                decodedImage: imageManager.decode(imageData),
                videoFormat: videoFormat
            )
        } catch {
            throw XmaxError.from(error)
        }
    }

    func prepare(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeVideoFormat {
        guard stateLock.withLock({ preparedFrame == nil }) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current image source before preparing " +
                    "another image"
            )
        }

        do {
            let resolvedFormat = try resolveVideoFormat(
                sourceWidth: Int(decodedImage.size.width),
                sourceHeight: Int(decodedImage.size.height),
                requestedFormat: videoFormat
            )
            let frameData = try decodedImage.makeVideoFrameData(
                width: resolvedFormat.width,
                height: resolvedFormat.height
            )
            let frameFormat = try VideoFormat(
                width: frameData.width,
                height: frameData.height,
                pixelFormat: frameData.pixelFormat
            )
            let framePlane = try VideoFramePlane(
                data: frameData.data,
                stride: frameData.bytesPerRow
            )
            stateLock.withLock {
                preparedFrame = PreparedFrame(
                    bufferReuseID: UUID(),
                    format: frameFormat,
                    plane: framePlane,
                    videoFormat: resolvedFormat
                )
            }
            return resolvedFormat
        } catch {
            throw XmaxError.from(error)
        }
    }

    func start() throws {
        let videoFormat = try stateLock.withLock {
            guard let preparedFrame else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Prepare the local image before starting the " +
                        "image source"
                )
            }
            guard !isRunning else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Local image source is already active"
                )
            }
            isRunning = true
            return preparedFrame.videoFormat
        }

        do {
            try emitFrame()
        } catch {
            stateLock.withLock {
                isRunning = false
            }
            throw XmaxError.from(error)
        }

        let interval = max(
            UInt64(1_000_000_000 / videoFormat.fps),
            1
        )
        let task = Task.detached { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      let self,
                      self.stateLock.withLock({ self.isRunning }) else {
                    return
                }

                do {
                    try self.emitFrame()
                } catch {
                    self.errorListener(XmaxError.from(error))
                }
            }
        }
        stateLock.withLock {
            if isRunning {
                outputTask = task
            } else {
                task.cancel()
            }
        }
    }

    func stop() {
        let task = stateLock.withLock { () -> Task<Void, Never>? in
            isRunning = false
            preparedFrame = nil
            let task = outputTask
            outputTask = nil
            return task
        }
        task?.cancel()
    }
}

private extension ImageSourceController {
    struct PreparedFrame {
        let bufferReuseID: UUID
        let format: VideoFormat
        let plane: VideoFramePlane
        let videoFormat: RealtimeVideoFormat
    }

    func emitFrame() throws {
        guard let frame = stateLock.withLock({ preparedFrame }) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Local image frame is unavailable"
            )
        }
        let timestampUs = Int64(
            min(
                DispatchTime.now().uptimeNanoseconds / 1_000,
                UInt64(Int64.max)
            )
        )
        try frameListener(
            try BufferVideoFrame(
                format: frame.format,
                timestampUs: timestampUs,
                planes: [frame.plane],
                bufferReuseID: frame.bufferReuseID
            )
        )
    }

    func resolveVideoFormat(
        sourceWidth: Int,
        sourceHeight: Int,
        requestedFormat: RealtimeVideoFormat?
    ) throws -> RealtimeVideoFormat {
        let requestedFormat = requestedFormat ?? RealtimeVideoFormat(
            width: sourceWidth,
            height: sourceHeight,
            fps: Self.defaultFrameRate
        )
        guard requestedFormat.fps > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image stream frame rate must be greater than zero"
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
