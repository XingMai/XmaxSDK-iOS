import Foundation

/// 循环解码本地视频文件，并按目标帧率向 RTC 输出 NV12 帧。
final class VideoSourceController: VideoSourceControlling, @unchecked Sendable {

    // 视频帧参数
    private static let samplingTolerance = 0.75

    // 视频帧监听器
    private let frameListener: VideoSourceFrameListener
    private let errorListener: VideoSourceErrorListener

    // 并发控制
    private let stateLock = NSLock()

    // 解码资源
    private var decoder: VideoFileFrameDecoder?

    // 配置状态
    private var configuration: Configuration?

    // 运行状态
    private var generationID: UUID?
    private var timeline: MediaTimeline?
    private var loopIndex: Int64 = 0
    private var lastOutputTimestampUs: Int64?

    init(
        frameListener: @escaping VideoSourceFrameListener,
        errorListener: @escaping VideoSourceErrorListener
    ) {
        self.frameListener = frameListener
        self.errorListener = errorListener
    }

    func configure(
        fileURL: URL,
        rotation: VideoRotation,
        frameRate: Int
    ) throws {
        guard fileURL.isFileURL,
              !fileURL.path.isEmpty,
              frameRate > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video source configuration is invalid"
            )
        }
        guard stateLock.withLock({ generationID == nil }) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current video source before configuring it"
            )
        }

        stateLock.withLock {
            configuration = Configuration(
                fileURL: fileURL,
                rotation: rotation,
                frameIntervalUs: max(1_000_000 / Int64(frameRate), 1)
            )
        }
    }

    func start(timeline: MediaTimeline) async throws {
        try await begin(timeline: timeline)
    }

    func restart(timeline: MediaTimeline) async throws {
        stop()
        try await begin(timeline: timeline)
    }

    func stop() {
        let decoder = stateLock.withLock { () -> VideoFileFrameDecoder? in
            generationID = nil
            timeline = nil
            loopIndex = 0
            lastOutputTimestampUs = nil
            let decoder = self.decoder
            self.decoder = nil
            return decoder
        }
        decoder?.release()
    }
}

private extension VideoSourceController {
    struct Configuration: Sendable {
        let fileURL: URL
        let rotation: VideoRotation
        let frameIntervalUs: Int64
    }

    func begin(timeline: MediaTimeline) async throws {
        let state = try stateLock.withLock { () -> (
            Configuration,
            UUID
        ) in
            guard let configuration else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Configure the video source before starting it"
                )
            }
            guard generationID == nil else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Local video source is already active"
                )
            }

            let generationID = UUID()
            self.generationID = generationID
            self.timeline = timeline
            loopIndex = 0
            lastOutputTimestampUs = nil
            return (configuration, generationID)
        }

        do {
            let decoder = try await makeDecoder(
                configuration: state.0,
                timeline: timeline,
                generationID: state.1,
                loopIndex: 0
            )
            let shouldKeep = stateLock.withLock {
                guard generationID == state.1, self.decoder == nil else {
                    return false
                }
                self.decoder = decoder
                return true
            }
            if !shouldKeep {
                decoder.release()
                throw XmaxError(
                    code: .cancelled,
                    message: "Video source start was cancelled"
                )
            }
        } catch {
            stateLock.withLock {
                if generationID == state.1 {
                    generationID = nil
                    self.timeline = nil
                }
            }
            throw XmaxError.from(error)
        }
    }

    func makeDecoder(
        configuration: Configuration,
        timeline: MediaTimeline,
        generationID: UUID,
        loopIndex: Int64
    ) async throws -> VideoFileFrameDecoder {
        let listener = VideoDecoderListener(
            frameHandler: { [weak self] frame in
                self?.handleFrame(
                    frame,
                    generationID: generationID,
                    loopIndex: loopIndex
                )
            },
            endHandler: { [weak self] in
                self?.handleEndOfStream(
                    generationID: generationID,
                    loopIndex: loopIndex
                )
            },
            errorHandler: { [weak self] message in
                self?.handleError(
                    message,
                    generationID: generationID,
                    loopIndex: loopIndex
                )
            }
        )
        return try await VideoFileFrameDecoder(
            fileURL: configuration.fileURL,
            listener: listener,
            playbackAnchorUs: try timeline.playbackAnchorUs(
                forLoop: loopIndex
            )
        )
    }

    func handleFrame(
        _ decodedFrame: VideoFileDecodedFrame,
        generationID: UUID,
        loopIndex: Int64
    ) {
        let state = stateLock.withLock { () -> Configuration? in
            guard self.generationID == generationID,
                  self.loopIndex == loopIndex,
                  let configuration else {
                return nil
            }

            let nowUs = VideoFileFrameDecoder.currentTimestampUs()
            guard nowUs - decodedFrame.timestampUs
                <= configuration.frameIntervalUs else {
                return nil
            }
            let minimumOutputIntervalUs = Int64(
                Double(configuration.frameIntervalUs)
                    * Self.samplingTolerance
            )
            if let lastOutputTimestampUs,
               decodedFrame.timestampUs - lastOutputTimestampUs
                < minimumOutputIntervalUs {
                return nil
            }
            self.lastOutputTimestampUs = decodedFrame.timestampUs
            return configuration
        }
        guard let state else {
            return
        }

        do {
            let lumaLength = decodedFrame.width * decodedFrame.height
            let format = try VideoFormat(
                width: decodedFrame.width,
                height: decodedFrame.height,
                pixelFormat: decodedFrame.pixelFormat
            )
            let frame = try BufferVideoFrame(
                format: format,
                timestampUs: decodedFrame.timestampUs,
                planes: [
                    try VideoFramePlane(
                        data: decodedFrame.data,
                        stride: decodedFrame.width,
                        byteLength: lumaLength
                    ),
                    try VideoFramePlane(
                        data: decodedFrame.data,
                        stride: decodedFrame.width,
                        byteOffset: lumaLength,
                        byteLength: lumaLength / 2
                    )
                ],
                rotation: state.rotation
            )
            try frameListener(frame)
        } catch {
            errorListener(XmaxError.from(error))
        }
    }

    func handleEndOfStream(
        generationID: UUID,
        loopIndex: Int64
    ) {
        Task { [weak self] in
            await self?.startNextLoop(
                generationID: generationID,
                completedLoopIndex: loopIndex
            )
        }
    }

    func startNextLoop(
        generationID: UUID,
        completedLoopIndex: Int64
    ) async {
        let state = stateLock.withLock { () -> (
            Configuration,
            MediaTimeline,
            Int64,
            VideoFileFrameDecoder?
        )? in
            guard self.generationID == generationID,
                  loopIndex == completedLoopIndex,
                  let configuration,
                  let timeline,
                  completedLoopIndex < Int64.max else {
                return nil
            }

            let oldDecoder = decoder
            decoder = nil
            loopIndex += 1
            lastOutputTimestampUs = nil
            return (configuration, timeline, loopIndex, oldDecoder)
        }
        guard let state else {
            return
        }
        state.3?.release()

        do {
            let nextDecoder = try await makeDecoder(
                configuration: state.0,
                timeline: state.1,
                generationID: generationID,
                loopIndex: state.2
            )
            let shouldKeep = stateLock.withLock {
                guard self.generationID == generationID,
                      loopIndex == state.2,
                      decoder == nil else {
                    return false
                }
                decoder = nextDecoder
                return true
            }
            if !shouldKeep {
                nextDecoder.release()
            }
        } catch {
            handleLoopFailure(error, generationID: generationID)
        }
    }

    func handleError(
        _ message: String,
        generationID: UUID,
        loopIndex: Int64
    ) {
        guard stateLock.withLock({
            self.generationID == generationID && self.loopIndex == loopIndex
        }) else {
            return
        }
        errorListener(XmaxError(code: .mediaError, message: message))
    }

    func handleLoopFailure(
        _ error: any Error,
        generationID: UUID
    ) {
        guard stateLock.withLock({ self.generationID == generationID }) else {
            return
        }
        errorListener(XmaxError.from(error))
    }
}

private final class VideoDecoderListener:
    VideoFileFrameDecoderListener,
    @unchecked Sendable {

    // 事件监听
    private let frameHandler: @Sendable (VideoFileDecodedFrame) -> Void
    private let endHandler: @Sendable () -> Void
    private let errorHandler: @Sendable (String) -> Void

    init(
        frameHandler: @escaping @Sendable (VideoFileDecodedFrame) -> Void,
        endHandler: @escaping @Sendable () -> Void,
        errorHandler: @escaping @Sendable (String) -> Void
    ) {
        self.frameHandler = frameHandler
        self.endHandler = endHandler
        self.errorHandler = errorHandler
    }

    func onFrame(_ frame: VideoFileDecodedFrame) {
        frameHandler(frame)
    }

    func onEndOfStream() {
        endHandler()
    }

    func onError(message: String) {
        errorHandler(message)
    }
}
