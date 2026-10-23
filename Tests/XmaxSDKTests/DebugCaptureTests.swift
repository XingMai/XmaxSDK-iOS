//
//  DebugCaptureTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#if DEBUG
@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import XCTest
@testable import XmaxSDK

final class DebugCaptureTests: XCTestCase {

    func testAudioObserverExposesNativeDelegateSelectors() {
        let sink = RtcDebugAudioSink(roomID: "expected")
        XCTAssertTrue(sink.responds(to: NSSelectorFromString("getObservedAudioFramePosition")))
        XCTAssertTrue(sink.responds(to: NSSelectorFromString("onPlaybackAudioFrameBeforeMixing:channelId:uid:")))
        XCTAssertTrue(sink.responds(to: NSSelectorFromString("onPlaybackAudioFrame:channelId:")))
        XCTAssertEqual(sink.getObservedAudioFramePosition().rawValue, 9)
    }

    func testFinalVideoCreatesReadableSegmentWithRecordedSourceOrigin() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try RealtimeDebugCaptureSession(directory: directory)
        let origin: Int64 = 1_700_000_000_000
        for index in 0..<12 {
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(
                nil, 64, 64, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer
            ), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            if let base = CVPixelBufferGetBaseAddress(pixels) {
                memset(base, Int32(index * 16), CVPixelBufferGetDataSize(pixels))
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            session.video(
                RealtimeVideoFrame(
                    pixelBuffer: pixels,
                    presentationTimeStamp: CMTime(value: origin + Int64(index * 33), timescale: 1000)
                ),
                epoch: "epoch", uid: 1, final: true
            )
        }
        try await session.finish()
        let events = try readEvents(directory)
        let segment = try XCTUnwrap(events.first { $0["event"] == "video_segment" })
        XCTAssertEqual(segment["source_origin_value"], String(origin))
        XCTAssertEqual(segment["source_origin_scale"], "1000")
        XCTAssertTrue(events.contains { $0["event"] == "video_final" && $0["appended"] == "true" })
        let asset = AVURLAsset(url: directory.appendingPathComponent(try XCTUnwrap(segment["file"])))
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        let sample = try XCTUnwrap(output.copyNextSampleBuffer())
        XCTAssertEqual(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)), 0, accuracy: 0.002)
        reader.cancelReading()
    }

    func testPublicCaptureFinishesAndExportsZip() async throws {
        let capture = XmaxDebugCapture.shared
        let directory = try await capture.start()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: directory.appendingPathExtension("zip"))
        }
        let archive = try await capture.stopAndExport()
        let active = await capture.isCapturing
        XCTAssertFalse(active)
        XCTAssertEqual(archive.pathExtension, "zip")
        let prefix = try Data(contentsOf: archive).prefix(4)
        XCTAssertEqual(Array(prefix), [0x50, 0x4B, 0x03, 0x04])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("summary.json").path))
    }

    func testNativeAudioIsCopiedAndOriginalClocksArePreserved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try RealtimeDebugCaptureSession(directory: directory)
        let bridge = RealtimeDebugCaptureBridge.shared
        bridge.registerRoom("private-room-name")
        bridge.install(session)
        defer {
            bridge.install(nil)
            bridge.unregisterRoom("private-room-name")
        }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 960, alignment: 8)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0x11, count: 960)
        let sink = RtcDebugAudioSink(roomID: "private-room-name")
        sink.capturePCM(
            buffer, channelId: "private-room-name", uid: 42,
            samplesPerChannel: 480, sampleRate: 48_000, channels: 1, bytesPerSample: 2,
            renderTimeMs: 0, presentationMs: 123_456, rtpTimestamp: UInt32.max - 10, avSyncType: 0
        )
        buffer.initializeMemory(as: UInt8.self, repeating: 0x22, count: 960)
        bridge.install(nil)
        try await session.finish()

        let events = try readEvents(directory)
        let audio = try XCTUnwrap(events.first { $0["event"] == "audio" }, "Events: \(events)")
        XCTAssertEqual(audio["render_ms"], "0")
        XCTAssertEqual(audio["presentation_ms"], "123456")
        XCTAssertEqual(audio["rtp_timestamp"], String(UInt32.max - 10))
        XCTAssertEqual(audio["uid"], "42")
        XCTAssertEqual(audio["offset"], "0")
        let payload = try Data(contentsOf: directory.appendingPathComponent(try XCTUnwrap(audio["pcm_file"])))
        XCTAssertEqual(payload, Data(repeating: 0x11, count: 960))
        let json = try String(contentsOf: directory.appendingPathComponent("events.jsonl"), encoding: .utf8)
        XCTAssertFalse(json.contains("private-room-name"))
    }

    func testPacketOffsetsSeparateFormatsAndStopRejectsLatePackets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try RealtimeDebugCaptureSession(directory: directory)
        let mono = ["sample_rate": "48000", "channels": "1", "bytes_per_sample": "2", "render_ms": "900"]
        let stereo = ["sample_rate": "48000", "channels": "2", "bytes_per_sample": "2", "render_ms": "100"]
        session.audio(Data([1, 2]), epoch: "epoch", uid: 1, fields: mono)
        session.audio(Data([3, 4]), epoch: "epoch", uid: 1, fields: mono)
        session.audio(Data([5, 6, 7, 8]), epoch: "epoch", uid: 1, fields: stereo)
        try await session.finish()
        session.audio(Data([9, 9]), epoch: "epoch", uid: 1, fields: mono)

        let packets = try readEvents(directory).filter { $0["event"] == "audio" }
        XCTAssertEqual(packets.count, 3)
        XCTAssertEqual(packets.map { $0["offset"] }, ["0", "2", "0"])
        XCTAssertEqual(packets.map { $0["render_ms"] }, ["900", "900", "100"])
        XCTAssertNotEqual(packets[0]["pcm_file"], packets[2]["pcm_file"])
        let monoFile = try XCTUnwrap(packets[0]["pcm_file"])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(monoFile)), Data([1, 2, 3, 4]))
    }

    func testPreMixAndPlaybackBytesAreNeverConcatenatedTogether() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try RealtimeDebugCaptureSession(directory: directory)
        let format = ["sample_rate": "48000", "channels": "1", "bytes_per_sample": "2"]
        session.audio(Data([1, 2]), epoch: "epoch", uid: 1, fields: format)
        session.audio(Data([3, 4]), epoch: "epoch", uid: 1, fields: format.merging(["tap": "playback_mixed"]) { _, value in value })
        try await session.finish()
        let packets = try readEvents(directory).filter { $0["event"] == "audio" }
        XCTAssertEqual(packets.map { $0["tap"] }, ["before_mixing", "playback_mixed"])
        XCTAssertEqual(packets.map { $0["offset"] }, ["0", "0"])
        XCTAssertNotEqual(packets[0]["pcm_file"], packets[1]["pcm_file"])
    }

    func testInvalidVideoTimestampIsLoggedWithoutBeingRepaired() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try RealtimeDebugCaptureSession(directory: directory)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let frame = RealtimeVideoFrame(pixelBuffer: try XCTUnwrap(buffer), presentationTimeStamp: .invalid)
        session.video(frame, epoch: "epoch", uid: 1, final: true)
        try await session.finish()

        let event = try XCTUnwrap(try readEvents(directory).first { $0["event"] == "video_final" })
        XCTAssertEqual(event["pts_scale"], "0")
        XCTAssertEqual(event["skip"], "invalid_pts")
        XCTAssertEqual(event["appended"], "false")
        XCTAssertNil(event["video_file"])
    }

    func testNativeAudioFromAnotherChannelIsIgnored() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try RealtimeDebugCaptureSession(directory: directory)
        let bridge = RealtimeDebugCaptureBridge.shared
        bridge.registerRoom("expected")
        bridge.install(session)
        let sink = RtcDebugAudioSink(roomID: "expected")
        sink.capturePCM(
            nil, channelId: "other", uid: 42,
            samplesPerChannel: 480, sampleRate: 48_000, channels: 1, bytesPerSample: 2,
            renderTimeMs: 0, presentationMs: 0, rtpTimestamp: 0, avSyncType: 0
        )
        bridge.install(nil)
        bridge.unregisterRoom("expected")
        try await session.finish()
        let events = try readEvents(directory)
        XCTAssertFalse(events.contains { $0["event"] == "audio" || $0["event"] == "invalid_audio_buffer" })
        let seen = try XCTUnwrap(events.first { $0["event"] == "audio_callback_seen" })
        XCTAssertEqual(seen["channel_matches"], "false")
    }

    func testAggregatePlaybackWithoutChannelIsAttributedToSoleOwnedRoom() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try RealtimeDebugCaptureSession(directory: directory)
        let bridge = RealtimeDebugCaptureBridge.shared
        bridge.registerRoom("expected")
        bridge.install(session)
        defer {
            bridge.install(nil)
            bridge.unregisterRoom("expected")
        }
        let sink = RtcDebugAudioSink(roomID: "expected")
        Data([1, 2]).withUnsafeBytes { bytes in
            sink.capturePCM(
                bytes.baseAddress, channelId: "", uid: 0,
                samplesPerChannel: 1, sampleRate: 48_000, channels: 1, bytesPerSample: 2,
                renderTimeMs: 100, presentationMs: 90, rtpTimestamp: 1, avSyncType: 0,
                tap: "playback_mixed"
            )
        }
        bridge.install(nil)
        try await session.finish()
        let events = try readEvents(directory)
        let seen = try XCTUnwrap(events.first { $0["event"] == "audio_callback_seen" })
        XCTAssertEqual(seen["channel_empty"], "true")
        XCTAssertEqual(seen["attributed_to_owned_room"], "true")
        let audio = try XCTUnwrap(events.first { $0["event"] == "audio" })
        XCTAssertEqual(audio["tap"], "playback_mixed")
        XCTAssertEqual(audio["uid"], "0")
        XCTAssertEqual(audio["length"], "2")
    }

    func testResolvedOutputTimingIsRecordedSeparatelyFromNativeAudio() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try RealtimeDebugCaptureSession(directory: directory)
        let bridge = RealtimeDebugCaptureBridge.shared
        bridge.registerRoom("output-room")
        bridge.install(session)
        defer {
            bridge.install(nil)
            bridge.unregisterRoom("output-room")
        }
        let queue = DispatchQueue(label: "test.capture.media-output")
        let output = RealtimeMediaFrameDispatcher(deliveryQueue: queue)
        output.setListener { _ in }
        let id = try XCTUnwrap(output.setStream(active: true))
        for _ in 0..<2 {
            bridge.audio(roomID: "output-room", uid: 7, data: audioPacket(1_000).data, fields: ["render_ms": "1000", "sample_rate": "48000", "channels": "1", "bytes_per_sample": "2"])
            output.dispatchAudio(audioPacket(1_000), streamID: id)
        }
        queue.sync {}
        bridge.install(nil)
        try await session.finish()
        let events = try readEvents(directory)
        let original = events.filter { $0["event"] == "audio" }
        let resolved = events.filter { $0["event"] == "media_output" }
        XCTAssertEqual(original.map { $0["render_ms"] }, ["1000", "1000"])
        XCTAssertEqual(resolved.count, 2)
        let times = try resolved.map { row in
            CMTime(value: try XCTUnwrap(Int64(row["pts_value"] ?? "")), timescale: try XCTUnwrap(Int32(row["pts_scale"] ?? "")))
        }
        XCTAssertEqual(times, [CMTime(value: 1_000, timescale: 1_000), CMTime(value: 1_010, timescale: 1_000)])
        XCTAssertEqual(resolved.map { $0["stream_id"] }, [id.uuidString, id.uuidString])
        XCTAssertEqual(resolved.map { $0["discontinuous"] }, ["true", "false"])
    }

    private func readEvents(_ directory: URL) throws -> [[String: String]] {
        let data = try Data(contentsOf: directory.appendingPathComponent("events.jsonl"))
        return try data.split(separator: 0x0A).map {
            try JSONDecoder().decode([String: String].self, from: Data($0))
        }
    }
}

#endif
