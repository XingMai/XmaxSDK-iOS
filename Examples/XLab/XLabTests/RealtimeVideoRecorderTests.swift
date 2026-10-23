@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import XCTest

@testable import XmaxSDK

@MainActor
final class RealtimeVideoRecorderTests: XCTestCase {
    func testAudioFirstArrivalPreservesLaterAudioPTSAndExportsDecodableAAC() async throws {
        let url = try await record(videoStartMs: 1_000_000, audioStartMs: 1_000_065)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let video = try await mediaTrack(asset, type: .video)
        let audio = try await mediaTrack(asset, type: .audio)
        XCTAssertEqual(try firstVideoPTS(asset, track: video).seconds, 0, accuracy: 0.005)
        let formats = try await audio.load(.formatDescriptions)
        let format = try XCTUnwrap(formats.first)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kAudioFormatMPEG4AAC)
        let pcm = try decodeAudio(asset, track: audio)
        XCTAssertEqual(pcm.firstSoundTime, 0.065, accuracy: 0.005)
        XCTAssertGreaterThan(pcm.sampleCount, 20_000)
        XCTAssertGreaterThan(pcm.peak, 1_000)
        XCTAssertGreaterThan(pcm.lastEnd.seconds, 0.9)
    }

    func testEarlierAudioPTSPlacesVideoLaterOnTheSameTimeline() async throws {
        let url = try await record(videoStartMs: 1_000_065, audioStartMs: 1_000_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let video = try await mediaTrack(asset, type: .video)
        let audio = try await mediaTrack(asset, type: .audio)
        XCTAssertEqual(try firstVideoPTS(asset, track: video).seconds, 0.065, accuracy: 0.005)
        XCTAssertEqual(try decodeAudio(asset, track: audio).firstSoundTime, 0, accuracy: 0.005)
    }

    func testAudioCanBeginAfterVideoEncodingHasAlreadyStarted() async throws {
        let recorder = RealtimeVideoRecorder { _ in XCTFail("Unexpected recording failure") }
        let id = UUID()
        try recorder.start()
        for i in 0..<12 { recorder.append(try video(id, ms: 1_000_000 + Int64(i * 40))) }
        for i in 0..<40 { recorder.append(audio(id, ms: 1_000_500 + Int64(i * 10))) }
        for i in 12..<24 { recorder.append(try video(id, ms: 1_000_000 + Int64(i * 40))) }
        let url = try await recorder.stop()
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let track = try await mediaTrack(asset, type: .audio)
        let decoded = try decodeAudio(asset, track: track)
        XCTAssertEqual(decoded.firstSoundTime, 0.5, accuracy: 0.005)
        XCTAssertGreaterThan(decoded.peak, 1_000)
    }

    func testVideoWithoutRemoteAudioStillExports() async throws {
        let recorder = RealtimeVideoRecorder { _ in XCTFail("Unexpected recording failure") }
        let id = UUID()
        try recorder.start()
        for i in 0..<24 { recorder.append(try video(id, ms: 1_000_000 + Int64(i * 40))) }
        let url = try await recorder.stop()
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertTrue(audioTracks.isEmpty)
        XCTAssertEqual(videoTracks.count, 1)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 0.96, accuracy: 0.01)
    }

    func testForwardAudioGapDoesNotCompressTheRecordingTimeline() async throws {
        let recorder = RealtimeVideoRecorder { _ in XCTFail("Unexpected recording failure") }
        let id = UUID()
        try recorder.start()
        for i in 0..<15 { recorder.append(try video(id, ms: 1_000_000 + Int64(i * 40))) }
        for i in 0..<20 { recorder.append(audio(id, ms: 1_000_000 + Int64(i * 10))) }
        for i in 0..<20 { recorder.append(audio(id, ms: 1_000_300 + Int64(i * 10))) }
        let url = try await recorder.stop()
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let track = try await mediaTrack(asset, type: .audio)
        let decoded = try decodeAudio(asset, track: track, silenceRange: 0.24...0.26)
        XCTAssertGreaterThan(decoded.lastEnd.seconds, 0.48)
        XCTAssertLessThan(decoded.silencePeak, 500)
    }

    func testAudioOnlyIsRejectedAndRecorderCanStartAgain() async throws {
        let recorder = RealtimeVideoRecorder { _ in }
        let id = UUID()
        try recorder.start()
        recorder.append(audio(id, ms: 1_000_000))
        do {
            _ = try await recorder.stop()
            XCTFail("Expected no video error")
        } catch {
            guard case .noFrames? = error as? RealtimeVideoRecorder.RecorderError else {
                return XCTFail("Wrong error: \(error)")
            }
        }
        try recorder.start()
        recorder.append(try video(id, ms: 1_000_000))
        let url = try await recorder.stop()
        try FileManager.default.removeItem(at: url)
    }

    func testBackwardTimeIsReportedInsteadOfRepairingOnlyOneTrack() async throws {
        let failed = expectation(description: "Timeline failure")
        let recorder = RealtimeVideoRecorder { error in
            guard case .timelineChanged = error else { return XCTFail("Wrong error: \(error)") }
            failed.fulfill()
        }
        let id = UUID()
        try recorder.start()
        recorder.append(try video(id, ms: 1_000_000))
        recorder.append(try video(id, ms: 1_000_040))
        recorder.append(try video(id, ms: 1_000_020))
        await fulfillment(of: [failed], timeout: 3)
    }

    func testStreamReplacementIsReportedInsteadOfMixingDifferentGenerations() async throws {
        let failed = expectation(description: "Stream failure")
        let recorder = RealtimeVideoRecorder { error in
            guard case .timelineChanged = error else { return XCTFail("Wrong error: \(error)") }
            failed.fulfill()
        }
        try recorder.start()
        recorder.append(try video(UUID(), ms: 1_000_000))
        recorder.append(audio(UUID(), ms: 1_000_065))
        await fulfillment(of: [failed], timeout: 3)
    }

    func testOversizedPacketFailsWithBoundedAdmission() async throws {
        let failed = expectation(description: "Bounded recording")
        let recorder = RealtimeVideoRecorder(maximumPendingBytes: 1) { error in
            guard case .bufferFull = error else { return XCTFail("Wrong error: \(error)") }
            failed.fulfill()
        }
        try recorder.start()
        recorder.append(try video(UUID(), ms: 1_000_000))
        await fulfillment(of: [failed], timeout: 3)
    }

    private func record(videoStartMs: Int64, audioStartMs: Int64) async throws -> URL {
        let recorder = RealtimeVideoRecorder { _ in XCTFail("Unexpected recording failure") }
        let id = UUID()
        try recorder.start()
        // Audio arrives first, while its media PTS may be earlier or later than video's.
        recorder.append(audio(id, ms: audioStartMs))
        for i in 0..<24 { recorder.append(try video(id, ms: videoStartMs + Int64(i * 40))) }
        for i in 1..<96 { recorder.append(audio(id, ms: audioStartMs + Int64(i * 10))) }
        return try await recorder.stop()
    }

    private func video(_ id: UUID, ms: Int64) throws -> RealtimeMediaFrame {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                64,
                64,
                kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                &buffer
            ),
            kCVReturnSuccess
        )
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            memset(base, 0x65, CVPixelBufferGetDataSize(pixels))
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return RealtimeMediaFrame(
            streamID: id,
            isDiscontinuous: false,
            content: .video(
                RealtimeVideoFrame(
                    pixelBuffer: pixels,
                    presentationTimeStamp: CMTime(value: ms, timescale: 1_000),
                    duration: CMTime(value: 40, timescale: 1_000)
                )
            )
        )
    }

    private func audio(_ id: UUID, ms: Int64) -> RealtimeMediaFrame {
        let samples = (0..<480).map { Int16(sin(Double($0) * .pi * 2 * 440 / 48_000) * 10_000) }
        let data = samples.withUnsafeBytes { Data($0) }
        return RealtimeMediaFrame(
            streamID: id,
            isDiscontinuous: false,
            content: .audio(
                RealtimeAudioFrame(
                    data: data,
                    sampleRate: 48_000,
                    channels: 1,
                    samplesPerChannel: 480,
                    presentationTimeStamp: CMTime(value: ms, timescale: 1_000)
                )
            )
        )
    }

    private func mediaTrack(_ asset: AVAsset, type: AVMediaType) async throws -> AVAssetTrack {
        let tracks = try await asset.loadTracks(withMediaType: type)
        return try XCTUnwrap(tracks.first)
    }

    private func firstVideoPTS(_ asset: AVAsset, track: AVAssetTrack) throws -> CMTime {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        defer { reader.cancelReading() }
        // An empty MP4 edit can produce black frames before the inserted video begins.
        while let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            let bytes = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self)
            let visible = bytes.map { $0[0] > 30 || $0[1] > 30 || $0[2] > 30 } ?? false
            CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
            if visible { return CMSampleBufferGetPresentationTimeStamp(sample) }
        }
        XCTFail("No recorded video content was decoded")
        return .invalid
    }

    private func decodeAudio(
        _ asset: AVAsset,
        track: AVAssetTrack,
        silenceRange: ClosedRange<Double>? = nil
    ) throws -> (sampleCount: Int, peak: Int, lastEnd: CMTime, firstSoundTime: Double, silencePeak: Int) {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        )
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var count = 0
        var peak = 0
        var lastEnd = CMTime.zero
        var firstSoundTime: Double?
        var silencePeak = 0
        while let sample = output.copyNextSampleBuffer() {
            count += CMSampleBufferGetNumSamples(sample)
            lastEnd = CMSampleBufferGetPresentationTimeStamp(sample) + CMSampleBufferGetDuration(sample)
            if let block = CMSampleBufferGetDataBuffer(sample) {
                var bytes = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(block))
                XCTAssertEqual(
                    CMBlockBufferCopyDataBytes(
                        block,
                        atOffset: 0,
                        dataLength: bytes.count,
                        destination: &bytes
                    ),
                    noErr
                )
                for i in stride(from: 0, to: bytes.count - 1, by: 2) {
                    let value = Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8)
                    let amplitude = abs(Int(value))
                    peak = max(peak, amplitude)
                    let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds + Double(i / 2) / 48_000
                    if firstSoundTime == nil, amplitude > 100 { firstSoundTime = time }
                    if silenceRange?.contains(time) == true { silencePeak = max(silencePeak, amplitude) }
                }
            }
        }
        XCTAssertEqual(reader.status, .completed, "\(String(describing: reader.error))")
        return (count, peak, lastEnd, firstSoundTime ?? -1, silencePeak)
    }
}
