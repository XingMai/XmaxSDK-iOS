@preconcurrency import AVFoundation
import Foundation
import XmaxSDK

/// 将 SDK 输出的最终远端视频帧编码为无声 MP4 文件。
final class RealtimeVideoRecorder: @unchecked Sendable {

    enum RecorderError: LocalizedError, Sendable {
        case alreadyRecording
        case notRecording
        case noFrames
        case videoFormatChanged
        case writingFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording:
                return "视频正在录制中。"
            case .notRecording:
                return "当前没有正在进行的录制。"
            case .noFrames:
                return "尚未录制到生成画面，请稍后重试。"
            case .videoFormatChanged:
                return "录制期间视频分辨率发生变化，录制已停止。"
            case let .writingFailed(message):
                return "视频录制失败：\(message)"
            }
        }
    }

    private enum State {
        case idle
        case recording
        case finishing
    }

    typealias FailureListener = @Sendable (RecorderError) -> Void

    // 事件监听
    private let failureListener: FailureListener

    // 编码资源
    private let recordingQueue = DispatchQueue(
        label: "ai.xmax.xlab.realtime-video-recorder",
        qos: .userInitiated
    )
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var pendingFrames: [RealtimeVideoFrame] = []
    private var finishContinuation:
        CheckedContinuation<URL, any Swift.Error>?

    // 输出规格
    private var outputURL: URL?
    private var videoWidth = 0
    private var videoHeight = 0

    // 时间信息
    private var hasStartedTimeline = false
    private var sourceTimeOrigin: CMTime?
    private var lastOutputTime = CMTime.invalid
    private var lastFrameDuration = CMTime(value: 1, timescale: 24)

    // 运行状态
    private var state = State.idle
    private var isDrainScheduled = false
    private var isFinishingWriter = false

    init(failureListener: @escaping FailureListener) {
        self.failureListener = failureListener
    }

    /// 开始接收后续远端最终视频帧。
    func start() throws {
        try recordingQueue.sync {
            guard state == .idle else {
                throw RecorderError.alreadyRecording
            }
            resetRecordingResources()
            outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            state = .recording
        }
    }

    /// 接收一帧；非录制状态下直接忽略。
    func append(_ frame: RealtimeVideoFrame) {
        recordingQueue.async { [weak self] in
            self?.enqueue(frame)
        }
    }

    /// 停止接收帧，等待编码完成并返回临时 MP4 文件地址。
    func stop() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            recordingQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(
                        throwing: RecorderError.notRecording
                    )
                    return
                }
                guard state == .recording else {
                    continuation.resume(
                        throwing: RecorderError.notRecording
                    )
                    return
                }
                state = .finishing
                finishContinuation = continuation
                guard writer != nil else {
                    fail(.noFrames)
                    return
                }
                drainFrames()
            }
        }
    }
}

private extension RealtimeVideoRecorder {
    func enqueue(_ frame: RealtimeVideoFrame) {
        guard state == .recording else { return }
        do {
            if writer == nil {
                try prepareWriter(for: frame)
            }
            guard CVPixelBufferGetWidth(frame.pixelBuffer) == videoWidth,
                  CVPixelBufferGetHeight(frame.pixelBuffer) == videoHeight else {
                throw RecorderError.videoFormatChanged
            }
            pendingFrames.append(frame)
            drainFrames()
        } catch let error as RecorderError {
            fail(error)
        } catch {
            fail(.writingFailed(error.localizedDescription))
        }
    }

    func prepareWriter(for frame: RealtimeVideoFrame) throws {
        guard let outputURL else {
            throw RecorderError.writingFailed("缺少输出文件地址。")
        }
        videoWidth = CVPixelBufferGetWidth(frame.pixelBuffer)
        videoHeight = CVPixelBufferGetHeight(frame.pixelBuffer)
        guard videoWidth > 0, videoHeight > 0,
              videoWidth.isMultiple(of: 2),
              videoHeight.isMultiple(of: 2) else {
            throw RecorderError.writingFailed("视频分辨率无效。")
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoWidth,
                AVVideoHeightKey: videoHeight
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw RecorderError.writingFailed("无法创建视频编码轨道。")
        }
        writer.add(input)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: nil
        )
        guard writer.startWriting() else {
            throw Self.writerError(writer)
        }
        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        writerInput = input
        pixelBufferAdaptor = adaptor
    }

    func drainFrames() {
        isDrainScheduled = false
        guard let writer, let writerInput, let pixelBufferAdaptor else {
            return
        }
        if writer.status == .failed || writer.status == .cancelled {
            fail(Self.writerError(writer))
            return
        }

        while writerInput.isReadyForMoreMediaData,
              !pendingFrames.isEmpty {
            let frame = pendingFrames.removeFirst()
            let outputTime = resolveOutputTime(for: frame)
            guard pixelBufferAdaptor.append(
                frame.pixelBuffer,
                withPresentationTime: outputTime
            ) else {
                fail(Self.writerError(writer))
                return
            }
        }

        if !pendingFrames.isEmpty {
            scheduleDrainRetry()
        } else if state == .finishing {
            finishWriting()
        }
    }

    func scheduleDrainRetry() {
        guard !isDrainScheduled else { return }
        isDrainScheduled = true
        recordingQueue.asyncAfter(deadline: .now() + 0.005) { [weak self] in
            self?.drainFrames()
        }
    }

    func finishWriting() {
        guard !isFinishingWriter,
              let writer,
              let writerInput else {
            return
        }
        guard writer.status == .writing else {
            fail(Self.writerError(writer))
            return
        }
        isFinishingWriter = true
        writerInput.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self else { return }
            recordingQueue.async { [weak self] in
                self?.completeWriting()
            }
        }
    }

    func completeWriting() {
        guard let writer,
              let continuation = finishContinuation,
              let outputURL else {
            resetRecordingResources()
            state = .idle
            return
        }
        finishContinuation = nil
        if writer.status == .completed {
            resetRecordingResources(keepsOutputFile: true)
            state = .idle
            continuation.resume(returning: outputURL)
        } else {
            fail(Self.writerError(writer), continuation: continuation)
        }
    }

    func resolveOutputTime(for frame: RealtimeVideoFrame) -> CMTime {
        let duration = Self.validDuration(frame.duration)
        lastFrameDuration = duration

        guard hasStartedTimeline else {
            hasStartedTimeline = true
            if Self.isUsableTime(frame.presentationTimeStamp) {
                sourceTimeOrigin = frame.presentationTimeStamp
            }
            lastOutputTime = .zero
            return .zero
        }

        let outputTime: CMTime
        if let sourceTimeOrigin,
           Self.isUsableTime(frame.presentationTimeStamp) {
            let candidate = frame.presentationTimeStamp - sourceTimeOrigin
            if candidate.isValid, candidate > lastOutputTime {
                outputTime = candidate
            } else {
                outputTime = lastOutputTime + duration
            }
        } else {
            outputTime = lastOutputTime + duration
        }
        lastOutputTime = outputTime
        return outputTime
    }

    func fail(
        _ error: RecorderError,
        continuation explicitContinuation:
            CheckedContinuation<URL, any Swift.Error>? = nil
    ) {
        let wasRecording = state == .recording
        let continuation = explicitContinuation ?? finishContinuation
        finishContinuation = nil
        if let writer,
           writer.status == .unknown || writer.status == .writing {
            writer.cancelWriting()
        }
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        resetRecordingResources()
        state = .idle

        if let continuation {
            continuation.resume(throwing: error)
        } else if wasRecording {
            failureListener(error)
        }
    }

    func resetRecordingResources(keepsOutputFile: Bool = false) {
        writer = nil
        writerInput = nil
        pixelBufferAdaptor = nil
        pendingFrames.removeAll()
        if !keepsOutputFile {
            outputURL = nil
        }
        videoWidth = 0
        videoHeight = 0
        hasStartedTimeline = false
        sourceTimeOrigin = nil
        lastOutputTime = .invalid
        lastFrameDuration = CMTime(value: 1, timescale: 24)
        isDrainScheduled = false
        isFinishingWriter = false
    }

    static func isUsableTime(_ time: CMTime) -> Bool {
        time.isValid && !time.isIndefinite
    }

    static func validDuration(_ duration: CMTime) -> CMTime {
        guard isUsableTime(duration), duration > .zero else {
            return CMTime(value: 1, timescale: 24)
        }
        return duration
    }

    static func writerError(_ writer: AVAssetWriter) -> RecorderError {
        .writingFailed(
            writer.error?.localizedDescription ?? "视频编码器异常。"
        )
    }
}
