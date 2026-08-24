@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// 文件视频连续解码事件。
protocol VideoFileFrameDecoderListener: AnyObject, Sendable {

    /// 收到一帧 NV12 视频。
    func onFrame(_ frame: VideoFileDecodedFrame)

    /// 文件视频已输出到流末尾。
    func onEndOfStream()

    /// 文件视频读取或解码失败。
    func onError(message: String)
}

/// 使用系统视频解码器按媒体时间戳连续输出 NV12 帧。
///
/// 解码结果由媒体层转换为统一视频帧，并交由后续业务链路处理。
final class VideoFileFrameDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private let operation: VideoFileDecodeOperation
    private var task: Task<Void, Never>?
    private var isReleased = false

    init(
        fileURL: URL,
        listener: any VideoFileFrameDecoderListener,
        playbackAnchorUs: Int64? = nil,
        mediaStartUs: Int64 = 0
    ) async throws {
        let resolvedPlaybackAnchorUs = playbackAnchorUs
            ?? Self.currentTimestampUs()
        guard fileURL.isFileURL,
              resolvedPlaybackAnchorUs > 0,
              mediaStartUs >= 0 else {
            throw Self.mediaError("Video file decoder arguments are invalid")
        }

        let operation = try await VideoFileDecodeOperation.make(
            fileURL: fileURL,
            playbackAnchorUs: resolvedPlaybackAnchorUs,
            mediaStartUs: mediaStartUs,
            listener: listener
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
    private let lock = NSLock()
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let playbackAnchorUs: Int64
    private let mediaStartUs: Int64
    private let listener: any VideoFileFrameDecoderListener
    private var isReleased = false
    private var hasReportedTerminalEvent = false

    private init(
        reader: AVAssetReader,
        output: AVAssetReaderTrackOutput,
        playbackAnchorUs: Int64,
        mediaStartUs: Int64,
        listener: any VideoFileFrameDecoderListener
    ) {
        self.reader = reader
        self.output = output
        self.playbackAnchorUs = playbackAnchorUs
        self.mediaStartUs = mediaStartUs
        self.listener = listener
    }

    static func make(
        fileURL: URL,
        playbackAnchorUs: Int64,
        mediaStartUs: Int64,
        listener: any VideoFileFrameDecoderListener
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
            playbackAnchorUs: playbackAnchorUs,
            mediaStartUs: mediaStartUs,
            listener: listener
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

        while isActive, !Task.isCancelled,
              let sampleBuffer = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(
                sampleBuffer
            ) else {
                reader.cancelReading()
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
                    timestampUs: playbackTimestampUs
                )
                guard isActive, !Task.isCancelled else {
                    return
                }
                listener.onFrame(frame)
            } catch {
                reader.cancelReading()
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
        let shouldCancel = lock.withLock {
            guard !isReleased else {
                return false
            }

            isReleased = true
            return true
        }
        if shouldCancel {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                reader.cancelReading()
            }
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
            listener.onEndOfStream()
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
            listener.onError(message: message)
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
