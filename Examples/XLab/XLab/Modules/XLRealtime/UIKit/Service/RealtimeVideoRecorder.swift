@preconcurrency import AVFoundation
import Foundation
import XmaxSDK

/// 将 SDK 的远端 PCM 和处理后视频编码为带音轨的 MP4，保留两路 PTS 的偏移。
final class RealtimeVideoRecorder: @unchecked Sendable {

    enum RecorderError: LocalizedError, Sendable {
        case alreadyRecording
        case notRecording
        case noFrames
        case videoFormatChanged
        case timelineChanged
        case bufferFull
        case writingFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: XLLocalization.text("record.alreadyRecording")
            case .notRecording: XLLocalization.text("record.notRecording")
            case .noFrames: XLLocalization.text("record.noFrames")
            case .videoFormatChanged: XLLocalization.text("record.sizeChanged")
            case .timelineChanged: XLLocalization.text("record.timelineChanged")
            case .bufferFull: XLLocalization.text("record.bufferFull")
            case .writingFailed(let message): XLLocalization.format("record.failed", message)
            }
        }
    }

    private enum State {
        case idle, recording, finishing
    }

    private struct Packet {
        let frame: RealtimeMediaFrame
        let bytes: Int
    }

    /// 轨道分别从零编码；合并时用 origin 恢复它们在共同时间线上的偏移。
    private final class Track: @unchecked Sendable {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let origin: CMTime
        let format: [Int]
        let videoAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        let audioDescription: CMAudioFormatDescription?
        var pending: [Packet] = []
        var lastQueuedPTS = CMTime.invalid
        var lastQueuedEnd = CMTime.invalid
        var endTime = CMTime.zero
        var finishing = false
        var finished = false

        init(
            writer: AVAssetWriter,
            input: AVAssetWriterInput,
            origin: CMTime,
            format: [Int],
            videoAdaptor: AVAssetWriterInputPixelBufferAdaptor? = nil,
            audioDescription: CMAudioFormatDescription? = nil
        ) {
            self.writer = writer
            self.input = input
            self.origin = origin
            self.format = format
            self.videoAdaptor = videoAdaptor
            self.audioDescription = audioDescription
        }
    }

    typealias FailureListener = @Sendable (RecorderError) -> Void

    private let failureListener: FailureListener
    private let recordingQueue = DispatchQueue(
        label: "ai.xmax.xlab.realtime-media-recorder",
        qos: .userInitiated
    )

    // 包括待入队和等待编码的媒体，避免慢编码器导致回调积压无界增长。
    private let admissionLock = NSLock()
    private let maximumPendingBytes: Int
    private let maximumPendingPackets: Int
    private var acceptingID: UUID?
    private var retainedBytes = 0
    private var retainedPackets = 0

    // 以下状态仅由 recordingQueue 访问。
    private var state = State.idle
    private var recordingID: UUID?
    private var streamID: UUID?
    private var directory: URL?
    private var outputURL: URL?
    private var video: Track?
    private var audio: Track?
    private var isDrainScheduled = false
    private var isExporting = false
    private var finishDeadline: UInt64?
    private var finishContinuation: CheckedContinuation<URL, any Swift.Error>?

    init(
        maximumPendingBytes: Int = 32 * 1_024 * 1_024,
        maximumPendingPackets: Int = 512,
        failureListener: @escaping FailureListener
    ) {
        self.maximumPendingBytes = maximumPendingBytes
        self.maximumPendingPackets = maximumPendingPackets
        self.failureListener = failureListener
    }

    /// 开始录制后续远端媒体，不会更改订阅或播放音量。
    func start() throws {
        try recordingQueue.sync {
            guard state == .idle else { throw RecorderError.alreadyRecording }
            let id = UUID()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                id.uuidString,
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.directory = directory
            outputURL = directory.deletingLastPathComponent().appendingPathComponent(id.uuidString + ".mp4")
            recordingID = id
            state = .recording
            admissionLock.withLock { acceptingID = id }
        }
    }

    /// 复制已由 SDK 持有的媒体引用，编码和文件操作不占用 SDK 回调队列。
    func append(_ frame: RealtimeMediaFrame) {
        let bytes: Int
        switch frame.content {
        case .audio(let audio): bytes = audio.data.count
        case .video(let video): bytes = CVPixelBufferGetDataSize(video.pixelBuffer)
        }
        admissionLock.withLock {
            guard let id = acceptingID else { return }
            guard retainedPackets < maximumPendingPackets,
                bytes <= maximumPendingBytes - retainedBytes
            else {
                acceptingID = nil
                recordingQueue.async { [weak self] in
                    guard let self, recordingID == id else { return }
                    fail(.bufferFull)
                }
                return
            }
            retainedPackets += 1
            retainedBytes += bytes
            let packet = Packet(frame: frame, bytes: bytes)
            recordingQueue.async { [weak self] in self?.enqueue(packet, recordingID: id) }
        }
    }

    /// 完成两路编码并合并为 MP4；无远端音频时返回纯视频文件。
    func stop() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            admissionLock.withLock {
                acceptingID = nil
                recordingQueue.async { [self] in
                    guard state == .recording else {
                        continuation.resume(throwing: RecorderError.notRecording)
                        return
                    }
                    state = .finishing
                    finishContinuation = continuation
                    finishDeadline = DispatchTime.now().uptimeNanoseconds + 10_000_000_000
                    guard video != nil else {
                        fail(.noFrames)
                        return
                    }
                    drainFrames()
                }
            }
        }
    }
}

extension RealtimeVideoRecorder {
    private func enqueue(_ packet: Packet, recordingID id: UUID) {
        guard recordingID == id, state == .recording else {
            release(packet)
            return
        }
        do {
            let event = packet.frame
            guard event.presentationTimeStamp.isNumeric else { throw RecorderError.timelineChanged }
            if let streamID, streamID != event.streamID { throw RecorderError.timelineChanged }
            streamID = event.streamID
            let track: Track
            let duration: CMTime
            switch event.content {
            case .video(let frame):
                if video == nil { video = try prepareVideo(frame) }
                guard let video else { throw RecorderError.noFrames }
                guard
                    video.format == [
                        CVPixelBufferGetWidth(frame.pixelBuffer), CVPixelBufferGetHeight(frame.pixelBuffer),
                    ]
                else {
                    throw RecorderError.videoFormatChanged
                }
                track = video
                duration = Self.validVideoDuration(frame.duration)
            case .audio(let frame):
                guard (8_000...192_000).contains(frame.sampleRate),
                    (1...2).contains(frame.channels), frame.samplesPerChannel > 0,
                    frame.samplesPerChannel <= 192_000,
                    frame.data.count == frame.samplesPerChannel * frame.channels * 2
                else {
                    throw RecorderError.writingFailed(XLLocalization.text("record.encoderFailed"))
                }
                if audio == nil { audio = try prepareAudio(frame) }
                guard let audio, audio.format == [frame.sampleRate, frame.channels] else {
                    throw RecorderError.timelineChanged
                }
                track = audio
                duration = frame.duration
            }
            if track.lastQueuedPTS.isNumeric {
                guard event.presentationTimeStamp > track.lastQueuedPTS else {
                    throw RecorderError.timelineChanged
                }
                if case .audio = event.content, event.presentationTimeStamp < track.lastQueuedEnd {
                    throw RecorderError.timelineChanged
                }
            }
            track.lastQueuedPTS = event.presentationTimeStamp
            track.lastQueuedEnd = event.presentationTimeStamp + duration
            track.pending.append(packet)
        } catch {
            release(packet)
            fail((error as? RecorderError) ?? .writingFailed(error.localizedDescription))
            return
        }
        drainFrames()
    }

    private func prepareVideo(_ frame: RealtimeVideoFrame) throws -> Track {
        let width = CVPixelBufferGetWidth(frame.pixelBuffer)
        let height = CVPixelBufferGetHeight(frame.pixelBuffer)
        guard width > 0, height > 0, width.isMultiple(of: 2), height.isMultiple(of: 2), let directory else {
            throw RecorderError.writingFailed(XLLocalization.text("record.invalidSize"))
        }
        let writer = try AVAssetWriter(
            outputURL: directory.appendingPathComponent("video.mp4"),
            fileType: .mp4
        )
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false],
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw Self.writerError(writer) }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: nil
        )
        guard writer.startWriting() else { throw Self.writerError(writer) }
        writer.startSession(atSourceTime: .zero)
        return Track(
            writer: writer,
            input: input,
            origin: frame.presentationTimeStamp,
            format: [width, height],
            videoAdaptor: adaptor
        )
    }

    private func prepareAudio(_ frame: RealtimeAudioFrame) throws -> Track {
        guard let directory else { throw RecorderError.notRecording }
        let description = try Self.audioDescription(frame)
        let writer = try AVAssetWriter(
            outputURL: directory.appendingPathComponent("audio.m4a"),
            fileType: .m4a
        )
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: frame.channels,
                AVEncoderBitRateKey: 96_000 * frame.channels,
            ],
            sourceFormatHint: description
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw Self.writerError(writer) }
        writer.add(input)
        guard writer.startWriting() else { throw Self.writerError(writer) }
        writer.startSession(atSourceTime: .zero)
        return Track(
            writer: writer,
            input: input,
            origin: frame.presentationTimeStamp,
            format: [frame.sampleRate, frame.channels],
            audioDescription: description
        )
    }

    private func drainFrames() {
        isDrainScheduled = false
        guard state != .idle else { return }
        if let deadline = finishDeadline, DispatchTime.now().uptimeNanoseconds > deadline, !isExporting {
            fail(.writingFailed(XLLocalization.text("record.encoderFailed")))
            return
        }
        do {
            for track in [video, audio].compactMap({ $0 }) where !track.finishing {
                guard track.writer.status == .writing else { throw Self.writerError(track.writer) }
                while track.input.isReadyForMoreMediaData, let packet = track.pending.first {
                    let pts = packet.frame.presentationTimeStamp - track.origin
                    switch packet.frame.content {
                    case .video(let frame):
                        guard track.videoAdaptor?.append(frame.pixelBuffer, withPresentationTime: pts) == true
                        else {
                            throw Self.writerError(track.writer)
                        }
                        track.endTime = pts + Self.validVideoDuration(frame.duration)
                    case .audio(let frame):
                        let gap = CMTimeConvertScale(
                            pts - track.endTime,
                            timescale: Int32(frame.sampleRate),
                            method: .roundHalfAwayFromZero
                        ).value
                        guard gap <= Int64(frame.sampleRate * 10), gap >= -1 else {
                            throw RecorderError.timelineChanged
                        }
                        if gap > 0 {
                            // AAC 编码器按样本连续输出，必须显式补静音才能保留 PCM 的时间缺口。
                            // 分块写入并继续观察背压；异常的大幅时钟跳变停止录制。
                            let count = Int(min(gap, 4_800))
                            let silence = try Self.audioSample(
                                data: Data(repeating: 0, count: count * frame.channels * 2),
                                samplesPerChannel: count,
                                description: track.audioDescription,
                                pts: track.endTime
                            )
                            guard track.input.append(silence) else { throw Self.writerError(track.writer) }
                            track.endTime =
                                track.endTime
                                + CMTime(value: Int64(count), timescale: Int32(frame.sampleRate))
                            continue
                        }
                        let sample = try Self.audioSample(
                            data: frame.data,
                            samplesPerChannel: frame.samplesPerChannel,
                            description: track.audioDescription,
                            pts: track.endTime
                        )
                        guard track.input.append(sample) else { throw Self.writerError(track.writer) }
                        track.endTime = track.endTime + frame.duration
                    }
                    track.pending.removeFirst()
                    release(packet)
                }
                if state == .finishing, track.pending.isEmpty { finish(track) }
            }
            if [video, audio].compactMap({ $0 }).contains(where: { !$0.pending.isEmpty }) {
                scheduleDrainRetry()
            }
        } catch {
            fail((error as? RecorderError) ?? .writingFailed(error.localizedDescription))
        }
    }

    private func scheduleDrainRetry() {
        guard !isDrainScheduled, let id = recordingID else { return }
        isDrainScheduled = true
        recordingQueue.asyncAfter(deadline: .now() + 0.005) { [weak self] in
            guard let self, recordingID == id else { return }
            drainFrames()
        }
    }

    private func finish(_ track: Track) {
        guard !track.finishing, let id = recordingID else { return }
        track.finishing = true
        track.writer.endSession(atSourceTime: track.endTime)
        track.input.markAsFinished()
        track.writer.finishWriting { [weak self, track] in
            guard let self else { return }
            recordingQueue.async { [self, track] in
                guard recordingID == id else { return }
                guard track.writer.status == .completed else {
                    fail(Self.writerError(track.writer))
                    return
                }
                track.finished = true
                completeTracksIfReady()
            }
        }
    }

    private func completeTracksIfReady() {
        guard let video, video.finished, audio?.finished != false,
            !isExporting, let id = recordingID, let outputURL
        else { return }
        isExporting = true
        let audio = audio
        Task { [self] in
            do {
                if let audio {
                    try await Self.combine(video: video, audio: audio, outputURL: outputURL)
                } else {
                    try FileManager.default.moveItem(at: video.writer.outputURL, to: outputURL)
                }
                recordingQueue.async { [self] in
                    guard recordingID == id else { return }
                    let continuation = finishContinuation
                    finishContinuation = nil
                    resetResources(keepsOutputFile: true)
                    continuation?.resume(returning: outputURL)
                }
            } catch {
                let failure = RecorderError.writingFailed(error.localizedDescription)
                recordingQueue.async { [self] in
                    guard recordingID == id else { return }
                    fail(failure)
                }
            }
        }
    }

    /// 两个编码文件的零点不同，只在此处按原始共同 PTS 放回同一时间线。
    private static func combine(video: Track, audio: Track, outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let origin = CMTimeMinimum(video.origin, audio.origin)
        for (track, mediaType) in [(video, AVMediaType.video), (audio, AVMediaType.audio)] {
            let asset = AVURLAsset(url: track.writer.outputURL)
            guard let source = try await asset.loadTracks(withMediaType: mediaType).first,
                let destination = composition.addMutableTrack(
                    withMediaType: mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            else {
                throw RecorderError.writingFailed(XLLocalization.text("record.trackFailed"))
            }
            try destination.insertTimeRange(
                CMTimeRange(start: .zero, duration: track.endTime),
                of: source,
                at: track.origin - origin
            )
            if mediaType == .video {
                destination.preferredTransform = try await source.load(.preferredTransform)
            }
        }
        guard
            let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetPassthrough
            )
        else {
            throw RecorderError.writingFailed(XLLocalization.text("record.encoderFailed"))
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else {
            throw RecorderError.writingFailed(
                exporter.error?.localizedDescription ?? XLLocalization.text("record.encoderFailed")
            )
        }
    }

    private func release(_ packet: Packet) {
        admissionLock.withLock {
            retainedPackets -= 1
            retainedBytes -= packet.bytes
        }
    }

    private func fail(_ error: RecorderError) {
        let wasRecording = state == .recording
        let continuation = finishContinuation
        finishContinuation = nil
        resetResources()
        if let continuation {
            continuation.resume(throwing: error)
        } else if wasRecording {
            failureListener(error)
        }
    }

    private func resetResources(keepsOutputFile: Bool = false) {
        admissionLock.withLock { acceptingID = nil }
        for track in [video, audio].compactMap({ $0 }) {
            if track.writer.status == .writing || track.writer.status == .unknown {
                track.writer.cancelWriting()
            }
            for packet in track.pending { release(packet) }
        }
        if let directory { try? FileManager.default.removeItem(at: directory) }
        if !keepsOutputFile, let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        video = nil
        audio = nil
        directory = nil
        outputURL = nil
        recordingID = nil
        streamID = nil
        state = .idle
        isDrainScheduled = false
        isExporting = false
        finishDeadline = nil
    }

    private static func audioDescription(_ frame: RealtimeAudioFrame) throws -> CMAudioFormatDescription {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(frame.sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(frame.channels * 2),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(frame.channels * 2),
            mChannelsPerFrame: UInt32(frame.channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var description: CMAudioFormatDescription?
        guard
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &asbd,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &description
            ) == noErr,
            let description
        else { throw RecorderError.writingFailed(XLLocalization.text("record.encoderFailed")) }
        return description
    }

    private static func audioSample(
        data: Data,
        samplesPerChannel: Int,
        description: CMAudioFormatDescription?,
        pts: CMTime
    ) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        guard let description,
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: data.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: data.count,
                flags: 0,
                blockBufferOut: &block
            ) == kCMBlockBufferNoErr,
            let block
        else { throw RecorderError.writingFailed(XLLocalization.text("record.encoderFailed")) }
        let result = data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(
                with: $0.baseAddress!,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }
        var sample: CMSampleBuffer?
        guard result == noErr,
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault,
                dataBuffer: block,
                formatDescription: description,
                sampleCount: samplesPerChannel,
                presentationTimeStamp: pts,
                packetDescriptions: nil,
                sampleBufferOut: &sample
            ) == noErr,
            let sample
        else { throw RecorderError.writingFailed(XLLocalization.text("record.encoderFailed")) }
        return sample
    }

    private static func validVideoDuration(_ duration: CMTime) -> CMTime {
        duration.isNumeric && duration > .zero ? duration : CMTime(value: 1, timescale: 24)
    }

    private static func writerError(_ writer: AVAssetWriter) -> RecorderError {
        .writingFailed(writer.error?.localizedDescription ?? XLLocalization.text("record.encoderFailed"))
    }
}
