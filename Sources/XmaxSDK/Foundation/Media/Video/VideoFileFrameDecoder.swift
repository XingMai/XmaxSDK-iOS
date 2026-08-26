@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// 使用系统视频解码器按媒体时间戳连续输出 NV12 帧。
///
/// 解码结果直接转换为统一视频帧，并交由后续业务链路处理。
final class VideoFileFrameDecoder: @unchecked Sendable {

    // 并发控制
    private let lock = NSLock()

    // 解码资源
    private let operation: VideoFileDecodeOperation
    private var task: Task<Void, Never>?

    // 运行状态
    private var isReleased = false

    init(
        fileURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        playbackAnchorUs: Int64? = nil,
        mediaStartUs: Int64 = 0,
        onFrame: @escaping @Sendable (VideoFrame) -> Void,
        onEndOfStream: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws {
        let resolvedPlaybackAnchorUs = playbackAnchorUs
            ?? Self.currentTimestampUs()
        guard fileURL.isFileURL,
              outputWidth > 0,
              outputHeight > 0,
              outputWidth.isMultiple(of: 2),
              outputHeight.isMultiple(of: 2),
              resolvedPlaybackAnchorUs > 0,
              mediaStartUs >= 0 else {
            throw Self.mediaError("Video file decoder arguments are invalid")
        }

        let operation = try await VideoFileDecodeOperation.make(
            fileURL: fileURL,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            rotation: rotation,
            playbackAnchorUs: resolvedPlaybackAnchorUs,
            mediaStartUs: mediaStartUs,
            onFrame: onFrame,
            onEndOfStream: onEndOfStream,
            onError: onError
        )
        self.operation = operation
        task = Task.detached(priority: .userInitiated) {
            await operation.run()
        }
    }

    deinit {
        release()
    }

    func release() {
        lock.withLock {
            guard !isReleased else {
                return
            }

            isReleased = true
            operation.release()
            task?.cancel()
            task = nil
        }
    }

    static func currentTimestampUs() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000)
    }

    private static func mediaError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}

private final class VideoFileDecodeOperation: @unchecked Sendable {

    // 并发控制
    private let lock = NSLock()

    // 平台资源
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    // 时间线配置
    private let playbackAnchorUs: Int64
    private let mediaStartUs: Int64

    // 输出配置
    private let outputWidth: Int
    private let outputHeight: Int
    private let rotation: VideoRotation

    // 事件监听
    private let onFrame: @Sendable (VideoFrame) -> Void
    private let onEndOfStream: @Sendable () -> Void
    private let onError: @Sendable (String) -> Void

    // 运行状态
    private var isReleased = false
    private var hasReportedTerminalEvent = false

    private init(
        reader: AVAssetReader,
        output: AVAssetReaderTrackOutput,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        playbackAnchorUs: Int64,
        mediaStartUs: Int64,
        onFrame: @escaping @Sendable (VideoFrame) -> Void,
        onEndOfStream: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.reader = reader
        self.output = output
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.rotation = rotation
        self.playbackAnchorUs = playbackAnchorUs
        self.mediaStartUs = mediaStartUs
        self.onFrame = onFrame
        self.onEndOfStream = onEndOfStream
        self.onError = onError
    }

    static func make(
        fileURL: URL,
        outputWidth: Int,
        outputHeight: Int,
        rotation: VideoRotation,
        playbackAnchorUs: Int64,
        mediaStartUs: Int64,
        onFrame: @escaping @Sendable (VideoFrame) -> Void,
        onEndOfStream: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws -> VideoFileDecodeOperation {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw mediaError("Video file does not exist")
        }

        let asset = AVURLAsset(url: fileURL)
        let videoTracks: [AVAssetTrack]
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw mediaError(
                "Failed to read video tracks: \((error as NSError).localizedDescription)"
            )
        }
        guard let videoTrack = videoTracks.first else {
            throw mediaError("The media file does not contain a video track")
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw mediaError(
                "Failed to create video reader: \((error as NSError).localizedDescription)"
            )
        }
        if mediaStartUs > 0 {
            let duration: CMTime
            do {
                duration = try await asset.load(.duration)
            } catch {
                throw mediaError(
                    "Failed to read video duration: " +
                        (error as NSError).localizedDescription
                )
            }
            let start = CMTime(
                value: mediaStartUs,
                timescale: 1_000_000
            )
            guard duration.isNumeric,
                  CMTimeCompare(start, duration) < 0 else {
                throw mediaError("Video start time exceeds the file duration")
            }
            reader.timeRange = CMTimeRange(start: start, end: duration)
        }

        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        )
        guard reader.canAdd(output) else {
            throw mediaError("Failed to configure NV12 video output")
        }
        reader.add(output)

        return VideoFileDecodeOperation(
            reader: reader,
            output: output,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            rotation: rotation,
            playbackAnchorUs: playbackAnchorUs,
            mediaStartUs: mediaStartUs,
            onFrame: onFrame,
            onEndOfStream: onEndOfStream,
            onError: onError
        )
    }

    func run() async {
        guard isActive else {
            return
        }
        guard reader.startReading() else {
            reportError(reader.errorMessage(
                fallback: "Failed to start video decoding"
            ))
            return
        }
        defer {
            if reader.status == .reading {
                reader.cancelReading()
            }
        }

        while isActive, !Task.isCancelled,
              let sampleBuffer = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(
                sampleBuffer
            ) else {
                reportError("Video decoder returned an invalid pixel buffer")
                return
            }

            let mediaTimestampUs = Self.timestampUs(
                from: sampleBuffer,
                fallback: mediaStartUs
            )
            let playbackTimestampUs = playbackAnchorUs
                + max(mediaTimestampUs - mediaStartUs, 0)
            guard await pace(until: playbackTimestampUs) else {
                return
            }

            do {
                let frame = try NV12VideoFrameConverter.convert(
                    pixelBuffer: pixelBuffer,
                    outputWidth: outputWidth,
                    outputHeight: outputHeight,
                    rotation: rotation,
                    timestampUs: playbackTimestampUs
                )
                guard isActive, !Task.isCancelled else {
                    return
                }
                onFrame(frame)
            } catch {
                reportError((error as NSError).localizedDescription)
                return
            }
        }

        guard isActive, !Task.isCancelled else {
            return
        }
        guard reader.status == .completed else {
            reportError(reader.errorMessage(
                fallback: "Video decoding did not complete"
            ))
            return
        }
        reportEndOfStream()
    }

    func release() {
        lock.withLock {
            guard !isReleased else {
                return
            }

            isReleased = true
        }
    }

    private var isActive: Bool {
        lock.withLock {
            !isReleased && !hasReportedTerminalEvent
        }
    }

    private func pace(until timestampUs: Int64) async -> Bool {
        var remainingDelayUs = timestampUs
            - VideoFileFrameDecoder.currentTimestampUs()
        while remainingDelayUs > 0 {
            let delayUs = UInt64(min(remainingDelayUs, 1_000_000))
            do {
                try await Task<Never, Never>.sleep(
                    nanoseconds: delayUs * 1_000
                )
            } catch {
                return false
            }
            guard isActive, !Task.isCancelled else {
                return false
            }
            remainingDelayUs = timestampUs
                - VideoFileFrameDecoder.currentTimestampUs()
        }
        return true
    }

    private func reportEndOfStream() {
        let shouldReport = lock.withLock {
            guard !isReleased, !hasReportedTerminalEvent else {
                return false
            }

            hasReportedTerminalEvent = true
            return true
        }
        if shouldReport {
            onEndOfStream()
        }
    }

    private func reportError(_ message: String) {
        let shouldReport = lock.withLock {
            guard !isReleased, !hasReportedTerminalEvent else {
                return false
            }

            hasReportedTerminalEvent = true
            return true
        }
        if shouldReport {
            onError(message)
        }
    }

    private static func timestampUs(
        from sampleBuffer: CMSampleBuffer,
        fallback: Int64
    ) -> Int64 {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid, timestamp.isNumeric else {
            return fallback
        }
        return Int64((CMTimeGetSeconds(timestamp) * 1_000_000).rounded())
    }

    private static func mediaError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}

private extension AVAssetReader {
    func errorMessage(fallback: String) -> String {
        error.map { ($0 as NSError).localizedDescription } ?? fallback
    }
}
