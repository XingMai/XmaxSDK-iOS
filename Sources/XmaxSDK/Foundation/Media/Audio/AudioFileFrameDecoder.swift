@preconcurrency import AVFoundation
import CoreMedia
import Foundation

/// 使用系统音频解码器连续输出 48 kHz 单声道 PCM16 帧。
final class AudioFileFrameDecoder: @unchecked Sendable {

    // 并发控制
    private let lock = NSLock()

    // 解码资源
    private let operation: AudioFileDecodeOperation
    private var task: Task<Void, Never>?

    // 运行状态
    private var isReleased = false

    init(
        fileURL: URL,
        playbackAnchorUs: Int64,
        mediaStartUs: Int64,
        cycleDurationUs: Int64,
        onFrame: @escaping @Sendable (AudioFrame) -> Void,
        onEndOfStream: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws {
        guard fileURL.isFileURL,
              playbackAnchorUs > 0,
              mediaStartUs >= 0,
              cycleDurationUs > 0 else {
            throw Self.mediaError("Audio file decoder arguments are invalid")
        }

        let operation = try await AudioFileDecodeOperation.make(
            fileURL: fileURL,
            playbackAnchorUs: playbackAnchorUs,
            mediaStartUs: mediaStartUs,
            cycleDurationUs: cycleDurationUs,
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

private final class AudioFileDecodeOperation: @unchecked Sendable {

    // 解码参数
    private static let lateFrameThresholdUs: Int64 = 30_000
    private static let bytesPerSample = MemoryLayout<Int16>.size

    // 并发控制
    private let lock = NSLock()

    // 平台资源
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    // 时间线配置
    private let playbackAnchorUs: Int64
    private let mediaStartUs: Int64

    // 事件监听
    private let onFrame: @Sendable (AudioFrame) -> Void
    private let onEndOfStream: @Sendable () -> Void
    private let onError: @Sendable (String) -> Void

    // 解码资源
    private let packetizer: AudioPCMFramePacketizer

    // 运行状态
    private var isReleased = false
    private var hasReportedTerminalEvent = false

    private init(
        reader: AVAssetReader,
        output: AVAssetReaderTrackOutput,
        playbackAnchorUs: Int64,
        mediaStartUs: Int64,
        cycleDurationUs: Int64,
        onFrame: @escaping @Sendable (AudioFrame) -> Void,
        onEndOfStream: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.reader = reader
        self.output = output
        self.playbackAnchorUs = playbackAnchorUs
        self.mediaStartUs = mediaStartUs
        self.onFrame = onFrame
        self.onEndOfStream = onEndOfStream
        self.onError = onError
        packetizer = AudioPCMFramePacketizer(
            mediaStartUs: mediaStartUs,
            cycleDurationUs: cycleDurationUs
        )
    }

    static func make(
        fileURL: URL,
        playbackAnchorUs: Int64,
        mediaStartUs: Int64,
        cycleDurationUs: Int64,
        onFrame: @escaping @Sendable (AudioFrame) -> Void,
        onEndOfStream: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws -> AudioFileDecodeOperation {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw mediaError("Audio file does not exist")
        }

        let asset = AVURLAsset(url: fileURL)
        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw mediaError(
                "Failed to read audio tracks: \((error as NSError).localizedDescription)"
            )
        }
        guard let audioTrack = audioTracks.first else {
            throw mediaError("The media file does not contain an audio track")
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw mediaError(
                "Failed to create audio reader: \((error as NSError).localizedDescription)"
            )
        }
        if mediaStartUs > 0 {
            let duration: CMTime
            do {
                duration = try await asset.load(.duration)
            } catch {
                throw mediaError(
                    "Failed to read audio duration: " +
                        (error as NSError).localizedDescription
                )
            }
            let start = CMTime(
                value: mediaStartUs,
                timescale: 1_000_000
            )
            guard duration.isNumeric,
                  CMTimeCompare(start, duration) < 0 else {
                throw mediaError("Audio start time exceeds the file duration")
            }
            reader.timeRange = CMTimeRange(start: start, end: duration)
        }

        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: AudioFrame.sampleRate,
                AVNumberOfChannelsKey: AudioFrame.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        guard reader.canAdd(output) else {
            throw mediaError("Failed to configure PCM audio output")
        }
        reader.add(output)

        return AudioFileDecodeOperation(
            reader: reader,
            output: output,
            playbackAnchorUs: playbackAnchorUs,
            mediaStartUs: mediaStartUs,
            cycleDurationUs: cycleDurationUs,
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
                fallback: "Failed to start audio decoding"
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
            do {
                let data = try Self.pcmData(from: sampleBuffer)
                let timestampUs = Self.timestampUs(from: sampleBuffer)
                let frames = packetizer.append(
                    data,
                    sourceTimestampUs: timestampUs
                )
                guard await dispatch(frames) else {
                    return
                }
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
                fallback: "Audio decoding did not complete"
            ))
            return
        }
        guard await dispatch(packetizer.finish()) else {
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

    private func dispatch(_ frames: [AudioFrame]) async -> Bool {
        for frame in frames {
            let playbackTimestampUs = playbackAnchorUs
                + max(frame.timestampUs - mediaStartUs, 0)
            let currentTimestampUs = AudioFileFrameDecoder
                .currentTimestampUs()
            var remainingDelayUs = playbackTimestampUs - currentTimestampUs
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
                remainingDelayUs = playbackTimestampUs
                    - AudioFileFrameDecoder.currentTimestampUs()
            }

            guard isActive, !Task.isCancelled else {
                return false
            }
            let latenessUs = AudioFileFrameDecoder.currentTimestampUs()
                - playbackTimestampUs
            if latenessUs > Self.lateFrameThresholdUs {
                continue
            }

            onFrame(AudioFrame(
                data: frame.data,
                timestampUs: playbackTimestampUs
            ))
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

    private static func pcmData(
        from sampleBuffer: CMSampleBuffer
    ) throws -> Data {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(
                  sampleBuffer
              ),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                  formatDescription
              )?.pointee,
              streamDescription.mFormatID == kAudioFormatLinearPCM,
              Int(streamDescription.mSampleRate.rounded()) == AudioFrame.sampleRate,
              streamDescription.mChannelsPerFrame == AudioFrame.channelCount,
              streamDescription.mBitsPerChannel == 16,
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw mediaError("Audio decoder returned an unsupported PCM format")
        }

        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let byteCount = sampleCount * Self.bytesPerSample
        guard sampleCount > 0,
              CMBlockBufferGetDataLength(blockBuffer) >= byteCount else {
            throw mediaError("Audio decoder returned invalid PCM data")
        }

        var data = Data(count: byteCount)
        let status = data.withUnsafeMutableBytes { bytes in
            guard let destination = bytes.baseAddress else {
                return kCMBlockBufferBadPointerParameterErr
            }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: destination
            )
        }
        guard status == kCMBlockBufferNoErr else {
            throw mediaError("Failed to access decoded PCM data")
        }
        return data
    }

    private static func timestampUs(
        from sampleBuffer: CMSampleBuffer
    ) -> Int64 {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid, timestamp.isNumeric else {
            return 0
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
