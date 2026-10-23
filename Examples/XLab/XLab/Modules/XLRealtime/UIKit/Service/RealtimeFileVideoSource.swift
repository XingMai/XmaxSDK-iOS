import AVFoundation
import CoreMedia
import XmaxSDK

/// Supplies decoded file video and PCM through the SDK's external input API.
@MainActor
final class RealtimeFileVideoSource: RealtimeExternalVideoSource {

    /// Immutable source settings shared with the decoding task.
    private struct Configuration: Sendable {
        let fileURL: URL
        let videoFormat: RealtimeVideoFormat
        let hasAudio: Bool
        let duration: CMTime
        let transform: CGAffineTransform
    }

    /// A reader and its outputs, used only by their owning decoding task.
    private struct ReadingSession {
        let reader: AVAssetReader
        let video: AVAssetReaderVideoCompositionOutput
        let audio: AVAssetReaderTrackOutput?
    }

    private let configuration: Configuration
    private var playbackTask: Task<Void, Never>?

    var videoFormat: RealtimeVideoFormat {
        configuration.videoFormat
    }
    var hasAudio: Bool {
        configuration.hasAudio
    }

    private init(
        configuration: Configuration
    ) {
        self.configuration = configuration
    }

    /// Reads the display dimensions before binding the file as an external source.
    static func make(
        fileURL: URL,
        frameRate: Int
    ) async throws -> RealtimeFileVideoSource {
        let asset = AVURLAsset(url: fileURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw sourceError("The selected file does not contain video")
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let bounds = CGRect(
            origin: .zero,
            size: naturalSize
        ).applying(preferredTransform).standardized
        let duration = try await asset.load(.duration)
        guard bounds.width.isFinite, bounds.height.isFinite,
            bounds.width >= 2, bounds.height >= 2,
            bounds.width < CGFloat(Int32.max), bounds.height < CGFloat(Int32.max),
            duration.isNumeric, CMTimeGetSeconds(duration) > 0,
            frameRate > 0, frameRate <= Int(Int32.max)
        else {
            throw sourceError("The selected video has an invalid format or duration")
        }

        let width = Int(bounds.width) / 2 * 2
        let height = Int(bounds.height) / 2 * 2
        let transform =
            preferredTransform
            .concatenating(
                CGAffineTransform(
                    translationX: -bounds.minX,
                    y: -bounds.minY
                )
            )
            .concatenating(
                CGAffineTransform(
                    scaleX: CGFloat(width) / bounds.width,
                    y: CGFloat(height) / bounds.height
                )
            )
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        try Task.checkCancellation()
        return RealtimeFileVideoSource(
            configuration: Configuration(
                fileURL: fileURL,
                videoFormat: RealtimeVideoFormat(
                    width: width,
                    height: height,
                    fps: frameRate
                ),
                hasAudio: hasAudio,
                duration: duration,
                transform: transform
            )
        )
    }

    /// Starts paced frame delivery without connecting or starting generation.
    func start(
        sink: any RealtimeExternalFrameSink
    ) async throws {
        guard playbackTask == nil else {
            throw Self.sourceError("The external video source is already running")
        }
        try Task.checkCancellation()
        let configuration = configuration
        playbackTask = Task.detached(priority: .userInitiated) {
            do {
                try await Self.play(
                    configuration: configuration,
                    sink: sink
                )
            } catch is CancellationError {
                // Cancellation ends this reader without reporting a source failure.
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                sink.reportError(error)
            }
        }
    }

    /// Cancels decoding and waits for the owning task to release its reader.
    func stop() async {
        let task = playbackTask
        playbackTask = nil
        task?.cancel()
        await task?.value
    }

    isolated deinit {
        playbackTask?.cancel()
    }
}

private extension RealtimeFileVideoSource {

    /// Loops the file with audio and video on one monotonic host timeline.
    private nonisolated static func play(
        configuration: Configuration,
        sink: any RealtimeExternalFrameSink
    ) async throws {
        var nextLoopStart: CMTime?
        while sink.isRequestingFrames {
            try Task.checkCancellation()
            let session = try await makeReadingSession(configuration: configuration)
            defer {
                if session.reader.status == .reading {
                    session.reader.cancelReading()
                }
            }
            try Task.checkCancellation()
            var video = session.video.copyNextSampleBuffer()
            var audio = session.audio?.copyNextSampleBuffer()
            guard video != nil else {
                throw session.reader.error
                    ?? sourceError("The selected video has no decodable frames")
            }

            let earliestStart = CMTimeAdd(
                hostTime(),
                CMTime(
                    value: 20,
                    timescale: 1000
                )
            )
            let loopStart =
                nextLoopStart.map {
                    CMTimeMaximum(
                        $0,
                        earliestStart
                    )
                } ?? earliestStart
            while video != nil || audio != nil {
                try Task.checkCancellation()
                guard sink.isRequestingFrames else {
                    return
                }
                let sendsVideo: Bool
                if let video, let audio {
                    sendsVideo =
                        CMTimeCompare(
                            CMSampleBufferGetPresentationTimeStamp(video),
                            CMSampleBufferGetPresentationTimeStamp(audio)
                        ) <= 0
                } else {
                    sendsVideo = video != nil
                }

                if sendsVideo, let sample = video {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    if pts.isNumeric, pts >= .zero,
                        let pixels = CMSampleBufferGetImageBuffer(sample)
                    {
                        let target = CMTimeAdd(
                            loopStart,
                            pts
                        )
                        let lateness = CMTimeGetSeconds(
                            CMTimeSubtract(
                                hostTime(),
                                target
                            )
                        )
                        if lateness <= 1 / Double(configuration.videoFormat.fps) {
                            try await wait(until: target)
                            sink.pushVideo(
                                pixels,
                                timestamp: target
                            )
                        }
                    }
                    video = session.video.copyNextSampleBuffer()
                } else if let sample = audio {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    if pts.isNumeric, pts >= .zero {
                        let target = CMTimeAdd(
                            loopStart,
                            pts
                        )
                        let lateness = CMTimeGetSeconds(
                            CMTimeSubtract(
                                hostTime(),
                                target
                            )
                        )
                        if lateness <= 0.1 {
                            try await wait(until: target)
                            sink.pushAudio(
                                try retimeAudio(
                                    sample,
                                    to: target
                                )
                            )
                        }
                    }
                    audio = session.audio?.copyNextSampleBuffer()
                }
            }
            if session.reader.status == .failed {
                throw session.reader.error ?? sourceError("External video decoding failed")
            }
            nextLoopStart = CMTimeAdd(
                loopStart,
                configuration.duration
            )
        }
    }

    /// Prepares oriented BGRA video and source-rate PCM without using a player.
    private nonisolated static func makeReadingSession(
        configuration: Configuration
    ) async throws -> ReadingSession {
        let asset = AVURLAsset(url: configuration.fileURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw sourceError("The selected file no longer contains video")
        }
        let reader = try AVAssetReader(asset: asset)
        let range = CMTimeRange(
            start: .zero,
            duration: configuration.duration
        )
        reader.timeRange = range

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(
            configuration.transform,
            at: .zero
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(
            width: configuration.videoFormat.width,
            height: configuration.videoFormat.height
        )
        composition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(configuration.videoFormat.fps)
        )
        composition.instructions = [instruction]
        let video = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        video.videoComposition = composition
        video.alwaysCopiesSampleData = false
        guard reader.canAdd(video) else {
            throw sourceError("The selected video cannot be decoded")
        }
        reader.add(video)

        var audio: AVAssetReaderTrackOutput?
        if configuration.hasAudio {
            guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                throw sourceError("The selected video's audio is unavailable")
            }
            let output = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw sourceError("The selected video's audio cannot be decoded")
            }
            reader.add(output)
            audio = output
        }
        try Task.checkCancellation()
        guard reader.startReading() else {
            throw reader.error ?? sourceError("External video decoding could not start")
        }
        return ReadingSession(
            reader: reader,
            video: video,
            audio: audio
        )
    }

    /// Moves a PCM buffer onto the same host timeline used by video frames.
    nonisolated static func retimeAudio(
        _ sampleBuffer: CMSampleBuffer,
        to timestamp: CMTime
    ) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo()
        var status = CMSampleBufferGetSampleTimingInfo(
            sampleBuffer,
            at: 0,
            timingInfoOut: &timing
        )
        guard status == noErr else {
            throw sourceError("Could not read external audio timing (\(status))")
        }
        timing.presentationTimeStamp = timestamp
        timing.decodeTimeStamp = .invalid
        var result: CMSampleBuffer?
        status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &result
        )
        guard status == noErr, let result else {
            throw sourceError("Could not retime external audio (\(status))")
        }
        return result
    }

    nonisolated static func hostTime() -> CMTime {
        CMClockGetTime(CMClockGetHostTimeClock())
    }

    /// Waits without blocking the main actor or moving the reader to another task.
    nonisolated static func wait(
        until target: CMTime
    ) async throws {
        let seconds = CMTimeGetSeconds(
            CMTimeSubtract(
                target,
                hostTime()
            )
        )
        if seconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1000000000))
        }
        try Task.checkCancellation()
    }

    nonisolated static func sourceError(
        _ message: String
    ) -> XmaxError {
        XmaxError(
            code: .mediaError,
            message: message
        )
    }
}
