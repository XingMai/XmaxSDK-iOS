import Foundation

/// 循环解码本地媒体中的音频轨道，并输出 10 ms PCM 帧。
final class AudioSourceController: AudioSourceControlling, @unchecked Sendable {

    // 音频帧监听器
    private let frameListener: AudioSourceFrameListener
    private let errorListener: AudioSourceErrorListener

    // 并发控制
    private let stateLock = NSLock()

    // 解码资源
    private var decoder: AudioFileFrameDecoder?

    // 配置状态
    private var fileURL: URL?

    // 运行状态
    private var generationID: UUID?
    private var timeline: MediaTimeline?
    private var loopIndex: Int64 = 0

    init(
        frameListener: @escaping AudioSourceFrameListener,
        errorListener: @escaping AudioSourceErrorListener
    ) {
        self.frameListener = frameListener
        self.errorListener = errorListener
    }

    func configure(fileURL: URL) throws {
        guard fileURL.isFileURL, !fileURL.path.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Audio source file URL is invalid"
            )
        }
        guard stateLock.withLock({ generationID == nil }) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current audio source before configuring it"
            )
        }
        stateLock.withLock {
            self.fileURL = fileURL
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
        let decoder = stateLock.withLock { () -> AudioFileFrameDecoder? in
            generationID = nil
            timeline = nil
            loopIndex = 0
            let decoder = self.decoder
            self.decoder = nil
            return decoder
        }
        decoder?.release()
    }
}

private extension AudioSourceController {
    func begin(timeline: MediaTimeline) async throws {
        let state = try stateLock.withLock { () -> (URL, UUID) in
            guard let fileURL else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Configure the audio source before starting it"
                )
            }
            guard generationID == nil else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Local audio source is already active"
                )
            }

            let generationID = UUID()
            self.generationID = generationID
            self.timeline = timeline
            loopIndex = 0
            return (fileURL, generationID)
        }

        do {
            let decoder = try await makeDecoder(
                fileURL: state.0,
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
                    message: "Audio source start was cancelled"
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
        fileURL: URL,
        timeline: MediaTimeline,
        generationID: UUID,
        loopIndex: Int64
    ) async throws -> AudioFileFrameDecoder {
        let listener = AudioDecoderListener(
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
        return try await AudioFileFrameDecoder(
            fileURL: fileURL,
            playbackAnchorUs: try timeline.playbackAnchorUs(
                forLoop: loopIndex
            ),
            mediaStartUs: 0,
            cycleDurationUs: timeline.cycleDurationUs,
            listener: listener
        )
    }

    func handleFrame(
        _ frame: AudioFrame,
        generationID: UUID,
        loopIndex: Int64
    ) {
        guard stateLock.withLock({
            self.generationID == generationID && self.loopIndex == loopIndex
        }) else {
            return
        }

        do {
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
            URL,
            MediaTimeline,
            Int64,
            AudioFileFrameDecoder?
        )? in
            guard self.generationID == generationID,
                  loopIndex == completedLoopIndex,
                  let fileURL,
                  let timeline,
                  completedLoopIndex < Int64.max else {
                return nil
            }

            let oldDecoder = decoder
            decoder = nil
            loopIndex += 1
            return (fileURL, timeline, loopIndex, oldDecoder)
        }
        guard let state else {
            return
        }
        state.3?.release()

        do {
            let nextDecoder = try await makeDecoder(
                fileURL: state.0,
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

private final class AudioDecoderListener:
    AudioFileFrameDecoderListener,
    @unchecked Sendable {

    // 事件监听
    private let frameHandler: @Sendable (AudioFrame) -> Void
    private let endHandler: @Sendable () -> Void
    private let errorHandler: @Sendable (String) -> Void

    init(
        frameHandler: @escaping @Sendable (AudioFrame) -> Void,
        endHandler: @escaping @Sendable () -> Void,
        errorHandler: @escaping @Sendable (String) -> Void
    ) {
        self.frameHandler = frameHandler
        self.endHandler = endHandler
        self.errorHandler = errorHandler
    }

    func onFrame(_ frame: AudioFrame) {
        frameHandler(frame)
    }

    func onEndOfStream() {
        endHandler()
    }

    func onError(message: String) {
        errorHandler(message)
    }
}
