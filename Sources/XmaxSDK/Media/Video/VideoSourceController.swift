import Foundation

/// 循环解码本地视频文件，并按目标帧率向 RTC 输出 NV12 帧。
final class VideoSourceController: VideoSourceControlling, @unchecked Sendable {

    // 视频帧参数
    private static let samplingTolerance = 0.75

    // 视频帧监听器
    private let frameListener: MediaVideoFrameListener
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
        frameListener: @escaping MediaVideoFrameListener,
        errorListener: @escaping VideoSourceErrorListener
    ) {
        self.frameListener = frameListener
        self.errorListener = errorListener
    }

    func configure(
        fileURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        frameRate: Int
    ) throws {
        guard fileURL.isFileURL,
              !fileURL.path.isEmpty,
              outputWidth > 0,
              outputHeight > 0,
              outputWidth.isMultiple(of: 2),
              outputHeight.isMultiple(of: 2),
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
                outputWidth: outputWidth,
                outputHeight: outputHeight,
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
        let outputWidth: Int
        let outputHeight: Int
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
        try await VideoFileFrameDecoder(
            fileURL: configuration.fileURL,
            outputWidth: configuration.outputWidth,
            outputHeight: configuration.outputHeight,
            rotation: configuration.rotation,
            playbackAnchorUs: try timeline.playbackAnchorUs(
                forLoop: loopIndex
            ),
            onFrame: { [weak self] frame in
                self?.handleFrame(
                    frame,
                    generationID: generationID,
                    loopIndex: loopIndex
                )
            },
            onEndOfStream: { [weak self] in
                self?.handleEndOfStream(
                    generationID: generationID,
                    loopIndex: loopIndex
                )
            },
            onError: { [weak self] message in
                self?.handleError(
                    message,
                    generationID: generationID,
                    loopIndex: loopIndex
                )
            }
        )
    }

    func handleFrame(
        _ decodedFrame: VideoFrame,
        generationID: UUID,
        loopIndex: Int64
    ) {
        let shouldOutput = stateLock.withLock { () -> Bool in
            guard self.generationID == generationID,
                  self.loopIndex == loopIndex,
                  let configuration else {
                return false
            }

            let nowUs = VideoFileFrameDecoder.currentTimestampUs()
            guard nowUs - decodedFrame.timestampUs
                <= configuration.frameIntervalUs else {
                return false
            }
            let minimumOutputIntervalUs = Int64(
                Double(configuration.frameIntervalUs)
                    * Self.samplingTolerance
            )
            if let lastOutputTimestampUs,
               decodedFrame.timestampUs - lastOutputTimestampUs
                < minimumOutputIntervalUs {
                return false
            }
            self.lastOutputTimestampUs = decodedFrame.timestampUs
            return true
        }
        guard shouldOutput else {
            return
        }

        do {
            try frameListener(decodedFrame)
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
