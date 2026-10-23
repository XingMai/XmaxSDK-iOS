//
//  XmaxDebugCapture.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#if DEBUG
@preconcurrency import AVFoundation
import Foundation

/// An opt-in, process-wide recorder for investigating remote audio and video timing.
///
/// Available only in Debug builds. Capture is limited to 90 seconds and records media locally;
/// it does not upload files or change audio subscriptions or playback volume. Stop capture before
/// sharing the archive. The original directory remains in Documents/XmaxDiagnostics.
public actor XmaxDebugCapture {

    /// The shared diagnostic recorder.
    public static let shared = XmaxDebugCapture()

    /// The recording or exporting session.
    private var session: RealtimeDebugCaptureSession?

    /// Prevents concurrent exporters from finishing the same files twice.
    private var exporting = false

    /// Whether capture is recording or awaiting export completion.
    public var isCapturing: Bool {
        session != nil
    }

    /// The most recently created directory, retained even when ZIP export fails.
    public private(set) var latestDirectory: URL?

    /// The most recently completed archive, including captures exported while leaving a screen.
    public private(set) var latestArchiveURL: URL?

    /// Creates a local capture and starts accepting remote media.
    ///
    /// - Returns: The directory containing the diagnostic files.
    /// - Throws: An error if a capture already exists or its files cannot be created.
    @discardableResult
    public func start() throws -> URL {
        guard session == nil else {
            throw XmaxError(code: .invalidConfiguration, message: "A debug capture is already active")
        }
        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("XmaxDiagnostics", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let session = try RealtimeDebugCaptureSession(directory: directory)
        self.session = session
        latestDirectory = directory
        RealtimeDebugCaptureBridge.shared.install(session)
        return directory
    }

    /// Stops media delivery, finishes video segments, and exports a ZIP archive.
    ///
    /// The archive includes owned PCM bytes, per-packet timing, decoded and final video timing,
    /// video-only MP4 segments, lifecycle events, and capture-loss counters. Audio timestamps are
    /// recorded verbatim; this tool does not claim or manufacture synchronization.
    ///
    /// - Returns: A ZIP file beside the capture directory, suitable for a system share sheet.
    /// - Throws: An error if capture is inactive, files cannot be finalized, or archiving fails.
    public func stopAndExport() async throws -> URL {
        guard let session else {
            throw XmaxError(code: .invalidConfiguration, message: "No debug capture is active")
        }
        guard !exporting else {
            throw XmaxError(code: .invalidConfiguration, message: "Debug capture export is already running")
        }
        exporting = true
        RealtimeDebugCaptureBridge.shared.install(nil)
        defer {
            self.session = nil
            exporting = false
        }
        try await session.finish()
        let archive = try await Task.detached(priority: .utility) {
            try Self.archive(session.directory)
        }.value
        latestArchiveURL = archive
        return archive
    }

    /// Copies the file coordinator's temporary ZIP before its accessor returns.
    private nonisolated static func archive(
        _ directory: URL
    ) throws -> URL {
        let destination = directory.appendingPathExtension("zip")
        var coordinationError: NSError?
        var result: Result<URL, any Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: directory,
            options: .forUploading,
            error: &coordinationError
        ) { snapshot in
            result = Result {
                try FileManager.default.copyItem(at: snapshot, to: destination)
                return destination
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else {
            throw XmaxError(code: .invalidConfiguration, message: "Debug archive was not created")
        }
        return try result.get()
    }
}

/// A thread-safe bridge between native callbacks and the optional diagnostic writer.
final class RealtimeDebugCaptureBridge: @unchecked Sendable {

    /// The process-wide bridge, independent of public frame listeners.
    static let shared = RealtimeDebugCaptureBridge()

    /// Protects capture and room-to-stream mappings.
    private let lock = NSLock()

    /// The active capture, or `nil` while diagnostics are disabled.
    private var session: RealtimeDebugCaptureSession?

    /// Opaque room lifetimes; actual channel names are never written to disk.
    private var rooms: [String: String] = [:]

    /// Maps result stream keys to opaque room lifetimes and numeric remote UIDs.
    private var streams: [String: (epoch: String, uid: UInt)] = [:]

    /// The latest observer, subscription, and volume settings for captures started mid-session.
    private var roomSettings: [String: [String: [String: String]]] = [:]

    /// Changes the active writer and snapshots already registered rooms.
    func install(
        _ session: RealtimeDebugCaptureSession?
    ) {
        lock.withLock {
            self.session = session
            for epoch in rooms.values {
                session?.event(["event": "room_snapshot", "epoch": epoch])
            }
            for settings in roomSettings.values {
                for var fields in settings.values {
                    fields["snapshot"] = "true"
                    session?.event(fields)
                }
            }
        }
    }

    /// Registers a room lifetime before native observers are installed.
    func registerRoom(
        _ roomID: String
    ) {
        lock.withLock {
            let epoch = UUID().uuidString
            rooms[roomID] = epoch
            session?.event(["event": "room_created", "epoch": epoch])
        }
    }

    /// Invalidates room mappings after native observers have been removed.
    func unregisterRoom(
        _ roomID: String
    ) {
        lock.withLock {
            guard let epoch = rooms.removeValue(forKey: roomID) else { return }
            roomSettings.removeValue(forKey: roomID)
            streams = streams.filter { $0.value.epoch != epoch }
            session?.event(["event": "room_closed", "epoch": epoch])
        }
    }

    /// Associates the SDK result track with its native numeric UID.
    func bindStream(
        _ stream: RemoteStream,
        uid: UInt
    ) {
        lock.withLock {
            guard let epoch = rooms[stream.roomID] else { return }
            streams[stream.key] = (epoch, uid)
            session?.event(["event": "result_stream", "epoch": epoch, "uid": String(uid)])
        }
    }

    /// Records a room-scoped event without writing credentials or channel identifiers.
    func event(
        _ name: String,
        roomID: String,
        fields: [String: String] = [:]
    ) {
        lock.withLock {
            guard let epoch = rooms[roomID] else { return }
            var fields = fields
            fields["event"] = name
            fields["epoch"] = epoch
            if ["audio_observer", "audio_subscription", "audio_volume", "native_audio_subscription", "native_audio_state"].contains(name) {
                roomSettings[roomID, default: [:]]["\(name)_\(fields["uid"] ?? "")"] = fields
            }
            session?.event(fields)
        }
    }

    /// Records public lifecycle states without task identifiers, prompts, or reference URLs.
    func state(
        _ state: RealtimeState
    ) {
        lock.withLock {
            session?.event([
                "event": "lifecycle",
                "state": state.connectionState.rawValue,
                "error_code": {
                    if case .failure(let error) = state.reason { return String(error.code.rawValue) }
                    return ""
                }()
            ])
        }
    }

    /// Copies a native audio packet before its callback-owned buffer can be reused.
    func audio(
        roomID: String,
        uid: UInt,
        data: Data,
        fields: [String: String]
    ) {
        lock.withLock {
            guard let session, let epoch = rooms[roomID] else { return }
            session.audio(data, epoch: epoch, uid: uid, fields: fields)
        }
    }

    /// Whether native callbacks should copy audio bytes for an active capture.
    var isRecording: Bool {
        lock.withLock { session != nil }
    }

    /// Records the public output contract separately from the original native clock evidence.
    func mediaOutput(
        _ frame: RealtimeMediaFrame
    ) {
        var fields: [String: String] = [
            "event": "media_output",
            "stream_id": frame.streamID.uuidString,
            "discontinuous": String(frame.isDiscontinuous),
            "pts_value": String(frame.presentationTimeStamp.value),
            "pts_scale": String(frame.presentationTimeStamp.timescale),
            "duration_value": String(frame.duration.value),
            "duration_scale": String(frame.duration.timescale)
        ]
        switch frame.content {
        case .audio(let audio):
            fields["track"] = "audio"
            fields["sample_rate"] = String(audio.sampleRate)
            fields["channels"] = String(audio.channels)
            fields["samples_per_channel"] = String(audio.samplesPerChannel)
        case .video:
            fields["track"] = "video"
        }
        lock.withLock { session?.event(fields) }
    }

    /// Records native decoded video timing before asynchronous interpolation.
    func decodedVideo(
        _ frame: RealtimeVideoFrame,
        roomID: String,
        uid: UInt
    ) {
        lock.withLock {
            guard let session, let epoch = rooms[roomID] else { return }
            session.video(frame, epoch: epoch, uid: uid, final: false)
        }
    }

    /// Records final frames with the same stream mapping as native audio and video.
    func finalVideo(
        _ frame: RealtimeVideoFrame,
        stream: RemoteStream
    ) {
        lock.withLock {
            guard let session, let context = streams[stream.key] else { return }
            session.video(frame, epoch: context.epoch, uid: context.uid, final: true)
        }
    }
}

/// Writes bounded diagnostic media on a dedicated serial queue.
final class RealtimeDebugCaptureSession: @unchecked Sendable {

    /// The persistent directory containing this capture's files.
    let directory: URL

    /// Serializes file I/O and video encoder access.
    private let queue = DispatchQueue(label: "ai.xmax.sdk.debug-capture", qos: .utility)

    /// Protects callback admission and queue pressure counters.
    private let lock = NSLock()

    /// Bounds retained pixel buffers and audio packets awaiting I/O.
    private var pendingBytes = 0

    /// Bounds small metadata events awaiting I/O.
    private var pendingCount = 0

    /// Whether callbacks may still enqueue work.
    private var accepting = true

    /// Counts samples rejected by the diagnostic queue, separately from RTC loss.
    private var dropped: [String: Int] = [:]

    /// Whether the 90-second admission limit was reached.
    private var durationLimitReached = false

    /// The monotonic capture start time, in nanoseconds.
    private let startTime = DispatchTime.now().uptimeNanoseconds

    /// The JSON Lines file containing timestamps and payload locations.
    private let eventFile: FileHandle

    /// Open PCM files keyed by opaque stream and actual negotiated format.
    private var audioFiles: [String: FileHandle] = [:]

    /// The next byte offset in each PCM file.
    private var audioOffsets: [String: UInt64] = [:]

    /// The total PCM bytes saved, bounded independently of queue pressure.
    private var audioBytes = 0

    /// The active video-only MP4 segment.
    private var videoSegment: RealtimeDebugVideoSegment?

    /// The number of video segments created so far.
    private var segmentCount = 0

    /// Whether a video encoder failure prevents further encoding attempts.
    private var videoFailed = false

    /// Tracks asynchronous completion of every video segment.
    private let videoFinishing = DispatchGroup()

    /// Diagnostic failures retained even if the event file cannot be written.
    private var errors: [String] = []

    /// Counts accepted events by media stage.
    private var counts: [String: Int] = [:]

    /// Counts encoder backpressure and other explicitly recorded payload omissions.
    private var skipped: [String: Int] = [:]

    /// Creates the event file and describes the unmodified timing fields.
    init(
        directory: URL
    ) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("events.jsonl")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw XmaxError(code: .invalidConfiguration, message: "Cannot create debug event file")
        }
        eventFile = try FileHandle(forWritingTo: url)
        let readme = """
        XmaxSDK remote-media debug capture (schema 2)

        events.jsonl: all numeric values are decimal strings. host_ns is receiver monotonic time,
        never a replacement for media PTS. epoch is an opaque room lifetime, uid is the remote UID.
        audio: raw native render_ms, presentation_ms and rtp_timestamp; pcm_file/offset/length locate
        owned packet bytes. Format is described by sample_rate, channels and bytes_per_sample.
        PCM packets are concatenated without filling gaps; use each packet's timing, not file offsets,
        to reconstruct its media time. tap distinguishes before_mixing (one UID) from playback_mixed
        (aggregate remote playback, uid 0). Different taps are stored in separate PCM files.
        audio_callback_seen records callback entry before channel/buffer filtering; no callback-seen
        events means the native observer never entered that tap during capture.
        Both taps explicitly request 48000 Hz mono, 480 samples per callback through the native
        engine setters; audio_observer logs their return codes. Packet fields report actual format.
        media_output: delivered public output timing, stream_id, track and discontinuous flag.
        Its audio PTS is derived from sample count; compare it with original audio events separately.
        video_decoded/video_final: pts_value/pts_scale and duration_value/duration_scale are CMTime;
        pts_flags preserve invalid and indefinite times. Final video is after optional interpolation.
        video_segment: source_origin_value/source_origin_scale map an MP4's zero to its source PTS.
        Each segment is video-only; PCM is separate. Dimensions or stream changes start new segments.
        Video encoding may drop frames under backpressure; appended and skip explain each final frame.
        Source timestamps are never repaired or independently rebased for audio and video.
        summary.json: accepted events, diagnostic queue drops, resource limits and writer errors.
        Registration, subscription and audio decode events help diagnose captures with no audio.

        Capture is opt-in and capped at 90 seconds, 32 MiB queued bytes, 2048 queued events,
        32 MiB PCM and 32 video segments. Queued media and hardware encoding can affect performance.
        No API keys, tokens, prompts, reference URLs or actual room names are intentionally recorded.
        The archive contains remote media; share it only with the intended reviewer.
        """
        try readme.write(to: directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        write([
            "event": "capture_started",
            "probe_schema": "2",
            "sdk_version": XmaxSDKInfo.version,
            "agora_version": "4.6.4",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "device_model": RuntimeInfo.current.deviceModel,
            "start_host_ns": String(startTime)
        ])
    }

    /// Enqueues a small diagnostic event.
    func event(
        _ fields: [String: String]
    ) {
        let host = DispatchTime.now().uptimeNanoseconds
        enqueue(kind: fields["event"] ?? "event", bytes: 0) { session in
            var fields = fields
            fields["host_ns"] = String(host)
            session.write(fields)
        }
    }

    /// Saves an owned PCM packet with its original native timing and format.
    func audio(
        _ data: Data,
        epoch: String,
        uid: UInt,
        fields: [String: String]
    ) {
        enqueue(kind: "audio", bytes: data.count) { session in
            var fields = fields
            fields["event"] = "audio"
            fields["epoch"] = epoch
            fields["uid"] = String(uid)
            let tap = fields["tap"] == "playback_mixed" ? "playback_mixed" : "before_mixing"
            fields["tap"] = tap
            let name = "audio_\(tap)_\(epoch)_\(uid)_\(fields["sample_rate"] ?? "0")_\(fields["channels"] ?? "0")_\(fields["bytes_per_sample"] ?? "0").pcm"
            do {
                guard session.audioBytes + data.count <= 32 * 1024 * 1024 else {
                    fields["skip"] = "pcm_size_limit"
                    session.write(fields)
                    return
                }
                let file: FileHandle
                if let existing = session.audioFiles[name] {
                    file = existing
                } else {
                    let url = session.directory.appendingPathComponent(name)
                    guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                        throw XmaxError(code: .invalidConfiguration, message: "Cannot create PCM file")
                    }
                    file = try FileHandle(forWritingTo: url)
                    session.audioFiles[name] = file
                }
                let offset = session.audioOffsets[name] ?? 0
                try file.write(contentsOf: data)
                session.audioOffsets[name] = offset + UInt64(data.count)
                session.audioBytes += data.count
                fields["pcm_file"] = name
                fields["offset"] = String(offset)
                fields["length"] = String(data.count)
            } catch {
                fields["skip"] = "pcm_write_error"
                session.recordError(error)
            }
            session.write(fields)
        }
    }

    /// Records frame timing and optionally encodes final pixels without changing their PTS.
    func video(
        _ frame: RealtimeVideoFrame,
        epoch: String,
        uid: UInt,
        final: Bool
    ) {
        let host = DispatchTime.now().uptimeNanoseconds
        let kind = final ? "video_final" : "video_decoded"
        let cost = final ? CVPixelBufferGetDataSize(frame.pixelBuffer) : 0
        // Decoded metadata does not retain a second pixel buffer in the I/O queue.
        var fields = Self.videoFields(frame)
        fields["event"] = kind
        fields["epoch"] = epoch
        fields["uid"] = String(uid)
        fields["host_ns"] = String(host)
        let metadata = fields
        if final {
            enqueue(kind: kind, bytes: cost) { session in
                var fields = metadata
                session.appendVideo(frame, key: "\(epoch)_\(uid)", fields: &fields)
                session.write(fields)
            }
        } else {
            enqueue(kind: kind, bytes: 0) { $0.write(metadata) }
        }
    }

    /// Stops admission, drains accepted samples, and waits for all encoders before closing files.
    func finish() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            lock.withLock {
                accepting = false
                queue.async { [self] in
                    finishVideoSegment()
                    videoFinishing.notify(queue: queue) { [self] in
                        do {
                            for file in audioFiles.values {
                                do { try file.close() } catch { recordError(error) }
                            }
                            audioFiles.removeAll()
                            write(["event": "capture_stopped", "host_ns": String(DispatchTime.now().uptimeNanoseconds)])
                            try eventFile.close()
                            let pressure = lock.withLock { (dropped, durationLimitReached) }
                            let summary: [String: Any] = [
                                "schema": 2, "events": counts, "diagnostic_queue_drops": pressure.0,
                                "payload_skips": skipped,
                                "duration_limit_reached": pressure.1, "pcm_bytes": audioBytes,
                                "video_segments": segmentCount, "errors": errors,
                                "elapsed_seconds": Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000_000
                            ]
                            try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
                                .write(to: directory.appendingPathComponent("summary.json"), options: .atomic)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }

    /// Admits bounded work without blocking a native media callback on file I/O.
    private func enqueue(
        kind: String,
        bytes: Int,
        work: @escaping @Sendable (RealtimeDebugCaptureSession) -> Void
    ) {
        lock.withLock {
            guard accepting else { return }
            guard DispatchTime.now().uptimeNanoseconds - startTime <= 90_000_000_000 else {
                durationLimitReached = true
                return
            }
            guard pendingBytes + bytes <= 32 * 1024 * 1024, pendingCount < 2048 else {
                dropped[kind, default: 0] += 1
                return
            }
            pendingBytes += bytes
            pendingCount += 1
            queue.async { [self] in
                work(self)
                lock.withLock {
                    pendingBytes -= bytes
                    pendingCount -= 1
                }
            }
        }
    }

    /// Appends one JSON object per line, retaining write errors for the summary.
    private func write(
        _ fields: [String: String]
    ) {
        counts[fields["event"] ?? "event", default: 0] += 1
        if let reason = fields["skip"] { skipped[reason, default: 0] += 1 }
        do {
            var data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            data.append(0x0A)
            try eventFile.write(contentsOf: data)
        } catch {
            recordError(error)
        }
    }

    /// Retains a bounded list of diagnostic I/O failures.
    private func recordError(
        _ error: any Error
    ) {
        if errors.count < 20 { errors.append(error.localizedDescription) }
    }

    /// Preserves exact CMTime components and flags for offline validation.
    private static func videoFields(
        _ frame: RealtimeVideoFrame
    ) -> [String: String] {
        [
            "pts_value": String(frame.presentationTimeStamp.value),
            "pts_scale": String(frame.presentationTimeStamp.timescale),
            "pts_flags": String(frame.presentationTimeStamp.flags.rawValue),
            "duration_value": String(frame.duration.value),
            "duration_scale": String(frame.duration.timescale),
            "duration_flags": String(frame.duration.flags.rawValue),
            "width": String(CVPixelBufferGetWidth(frame.pixelBuffer)),
            "height": String(CVPixelBufferGetHeight(frame.pixelBuffer))
        ]
    }

    /// Starts new video segments on stream, size, or timestamp discontinuities.
    private func appendVideo(
        _ frame: RealtimeVideoFrame,
        key: String,
        fields: inout [String: String]
    ) {
        fields["appended"] = "false"
        guard frame.presentationTimeStamp.isNumeric else {
            fields["skip"] = "invalid_pts"
            return
        }
        guard !videoFailed else {
            fields["skip"] = "encoder_failed"
            return
        }
        do {
            if let segment = videoSegment,
               !segment.matches(frame, key: key)
                || (segment.lastPTS.isNumeric && frame.presentationTimeStamp <= segment.lastPTS) {
                finishVideoSegment()
            }
            if videoSegment == nil {
                guard segmentCount < 32 else {
                    fields["skip"] = "segment_limit"
                    return
                }
                segmentCount += 1
                let segment = try RealtimeDebugVideoSegment(
                    directory: directory,
                    index: segmentCount,
                    frame: frame,
                    key: key
                )
                videoSegment = segment
                write([
                    "event": "video_segment", "file": segment.url.lastPathComponent, "stream": key,
                    "source_origin_value": String(frame.presentationTimeStamp.value),
                    "source_origin_scale": String(frame.presentationTimeStamp.timescale)
                ])
            }
            guard let segment = videoSegment else { return }
            fields["video_file"] = segment.url.lastPathComponent
            guard segment.input.isReadyForMoreMediaData else {
                if segment.writer.status == .failed { throw segment.writer.error ?? CancellationError() }
                fields["skip"] = "encoder_backpressure"
                return
            }
            guard segment.adaptor.append(frame.pixelBuffer, withPresentationTime: frame.presentationTimeStamp) else {
                throw segment.writer.error ?? CancellationError()
            }
            segment.lastPTS = frame.presentationTimeStamp
            fields["appended"] = "true"
        } catch {
            videoFailed = true
            fields["skip"] = "encoder_error"
            recordError(error)
        }
    }

    /// Completes an encoder without blocking the serial writer queue.
    private func finishVideoSegment() {
        guard let segment = videoSegment else { return }
        videoSegment = nil
        guard segment.writer.status == .writing else {
            if let error = segment.writer.error { recordError(error) }
            return
        }
        segment.input.markAsFinished()
        videoFinishing.enter()
        segment.writer.finishWriting { [self, segment] in
            queue.async { [self, segment] in
                if let error = segment.writer.error { recordError(error) }
                write([
                    "event": "video_segment_finished", "file": segment.url.lastPathComponent,
                    "status": String(segment.writer.status.rawValue)
                ])
                videoFinishing.leave()
            }
        }
    }
}

/// A video-only MP4 preserving one stream's source presentation timestamps.
private final class RealtimeDebugVideoSegment: @unchecked Sendable {

    /// The encoded segment URL.
    let url: URL

    /// The segment writer, accessed on the capture queue.
    let writer: AVAssetWriter

    /// The real-time video writer input.
    let input: AVAssetWriterInput

    /// The pixel-buffer-to-video encoder adapter.
    let adaptor: AVAssetWriterInputPixelBufferAdaptor

    /// The stream and dimensions identifying this segment.
    private let signature: String

    /// The last successfully appended source timestamp.
    var lastPTS = CMTime.invalid

    /// Creates a bounded-bitrate H.264 encoder without modifying source timestamps.
    init(
        directory: URL,
        index: Int,
        frame: RealtimeVideoFrame,
        key: String
    ) throws {
        let width = CVPixelBufferGetWidth(frame.pixelBuffer)
        let height = CVPixelBufferGetHeight(frame.pixelBuffer)
        signature = "\(key)_\(width)_\(height)"
        url = directory.appendingPathComponent("video_\(index).mp4")
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000,
                    AVVideoAllowFrameReorderingKey: false
                ]
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw XmaxError(code: .mediaError, message: "Cannot add debug video encoder")
        }
        writer.add(input)
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.startWriting() else { throw writer.error ?? CancellationError() }
        writer.startSession(atSourceTime: frame.presentationTimeStamp)
    }

    /// Whether the frame belongs to the same stream and dimensions.
    func matches(
        _ frame: RealtimeVideoFrame,
        key: String
    ) -> Bool {
        signature == "\(key)_\(CVPixelBufferGetWidth(frame.pixelBuffer))_\(CVPixelBufferGetHeight(frame.pixelBuffer))"
    }
}
#endif
