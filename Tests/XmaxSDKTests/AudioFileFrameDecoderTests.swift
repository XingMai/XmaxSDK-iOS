import AVFoundation
import Foundation
import XCTest
@testable import XmaxSDK

final class AudioFileFrameDecoderTests: XCTestCase {
    func testPacketizerSplitsPCMIntoTenMillisecondFrames() {
        let packetizer = AudioPCMFramePacketizer(
            mediaStartUs: 25_000,
            cycleDurationUs: 20_000
        )
        let source = Data(repeating: 7, count: 1_920)

        let frames = packetizer.append(
            source,
            sourceTimestampUs: 25_000
        )

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames.map(\.data.count), [960, 960])
        XCTAssertEqual(frames.map(\.timestampUs), [25_000, 35_000])
        XCTAssertTrue(packetizer.finish().isEmpty)
    }

    func testPacketizerAddsInitialSilenceFromSourceTimestamp() {
        let packetizer = AudioPCMFramePacketizer(
            mediaStartUs: 100_000,
            cycleDurationUs: 20_000
        )
        let source = Data(repeating: 9, count: 960)

        let frames = packetizer.append(
            source,
            sourceTimestampUs: 110_000
        )

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].data, Data(repeating: 0, count: 960))
        XCTAssertEqual(frames[1].data, source)
        XCTAssertEqual(frames.map(\.timestampUs), [100_000, 110_000])
    }

    func testPacketizerPadsEndOfStreamToCompleteCycle() {
        let packetizer = AudioPCMFramePacketizer(
            mediaStartUs: 0,
            cycleDurationUs: 15_000
        )
        let partialSource = Data(repeating: 4, count: 480)

        XCTAssertTrue(packetizer.append(
            partialSource,
            sourceTimestampUs: 0
        ).isEmpty)

        let frames = packetizer.finish()

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames.map(\.data.count), [960, 960])
        XCTAssertEqual(frames.map(\.timestampUs), [0, 10_000])
        XCTAssertEqual(frames[0].data.prefix(480), partialSource)
        XCTAssertEqual(
            frames[0].data.suffix(480),
            Data(repeating: 0, count: 480)
        )
        XCTAssertEqual(frames[1].data, Data(repeating: 0, count: 960))
    }

    func testPacketizerTruncatesPCMAtCycleBoundary() {
        let packetizer = AudioPCMFramePacketizer(
            mediaStartUs: 0,
            cycleDurationUs: 10_000
        )

        let frames = packetizer.append(
            Data(repeating: 3, count: 1_920),
            sourceTimestampUs: 0
        )

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].data, Data(repeating: 3, count: 960))
        XCTAssertTrue(packetizer.finish().isEmpty)
    }

    func testDecoderRejectsMissingFile() async {
        do {
            _ = try await AudioFileFrameDecoder(
                fileURL: URL(fileURLWithPath: "/missing/audio.wav"),
                playbackAnchorUs: 1,
                mediaStartUs: 0,
                cycleDurationUs: 10_000,
                onFrame: { _ in },
                onEndOfStream: {},
                onError: { _ in }
            )
            XCTFail("Expected decoder creation to fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .mediaError)
        }
    }

    func testDecoderReadsWAVAndReportsPlaybackTimestamp() async throws {
        let sourceData = Data(repeating: 5, count: 960)
        let fileURL = try makePCM16WAV(pcmData: sourceData)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let frameExpectation = expectation(description: "audio frame")
        let terminalExpectation = expectation(description: "end of stream")
        let recorder = AudioFileFrameDecoderRecorder(
            frameExpectation: frameExpectation,
            terminalExpectation: terminalExpectation
        )
        let playbackAnchorUs = AudioFileFrameDecoder.currentTimestampUs()
            + 500_000
        let decoder = try await AudioFileFrameDecoder(
            fileURL: fileURL,
            playbackAnchorUs: playbackAnchorUs,
            mediaStartUs: 0,
            cycleDurationUs: 10_000,
            onFrame: { recorder.onFrame($0) },
            onEndOfStream: { recorder.onEndOfStream() },
            onError: { recorder.onError(message: $0) }
        )
        defer {
            decoder.release()
        }

        await fulfillment(
            of: [frameExpectation, terminalExpectation],
            timeout: 2,
            enforceOrder: true
        )

        XCTAssertNil(recorder.errorMessage)
        XCTAssertEqual(recorder.frames.count, 1)
        XCTAssertEqual(recorder.frames[0].data, sourceData)
        XCTAssertEqual(recorder.frames[0].timestampUs, playbackAnchorUs)
    }

    func testDecoderStartsAtRequestedMediaCheckpoint() async throws {
        let skippedData = Data(repeating: 1, count: 960)
        let checkpointData = Data(repeating: 2, count: 960)
        let fileURL = try makePCM16WAV(
            pcmData: skippedData + checkpointData
        )
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let frameExpectation = expectation(description: "audio frame")
        let terminalExpectation = expectation(description: "end of stream")
        let recorder = AudioFileFrameDecoderRecorder(
            frameExpectation: frameExpectation,
            terminalExpectation: terminalExpectation
        )
        let playbackAnchorUs = AudioFileFrameDecoder.currentTimestampUs()
            + 500_000
        let decoder = try await AudioFileFrameDecoder(
            fileURL: fileURL,
            playbackAnchorUs: playbackAnchorUs,
            mediaStartUs: 10_000,
            cycleDurationUs: 10_000,
            onFrame: { recorder.onFrame($0) },
            onEndOfStream: { recorder.onEndOfStream() },
            onError: { recorder.onError(message: $0) }
        )
        defer {
            decoder.release()
        }

        await fulfillment(
            of: [frameExpectation, terminalExpectation],
            timeout: 2,
            enforceOrder: true
        )

        XCTAssertNil(recorder.errorMessage)
        XCTAssertEqual(recorder.frames.count, 1)
        XCTAssertEqual(recorder.frames[0].data, checkpointData)
        XCTAssertEqual(recorder.frames[0].timestampUs, playbackAnchorUs)
    }

    func testDecoderResamplesAndDownmixesToAudioFrameFormat() async throws {
        let sourceData = Data(repeating: 0, count: 441 * 2 * 2)
        let fileURL = try makePCM16WAV(
            pcmData: sourceData,
            sampleRate: 44_100,
            channelCount: 2
        )
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let frameExpectation = expectation(description: "audio frame")
        let terminalExpectation = expectation(description: "end of stream")
        let recorder = AudioFileFrameDecoderRecorder(
            frameExpectation: frameExpectation,
            terminalExpectation: terminalExpectation
        )
        let decoder = try await AudioFileFrameDecoder(
            fileURL: fileURL,
            playbackAnchorUs: AudioFileFrameDecoder.currentTimestampUs()
                + 500_000,
            mediaStartUs: 0,
            cycleDurationUs: 10_000,
            onFrame: { recorder.onFrame($0) },
            onEndOfStream: { recorder.onEndOfStream() },
            onError: { recorder.onError(message: $0) }
        )
        defer {
            decoder.release()
        }

        await fulfillment(
            of: [frameExpectation, terminalExpectation],
            timeout: 2,
            enforceOrder: true
        )

        XCTAssertNil(recorder.errorMessage)
        XCTAssertEqual(recorder.frames.count, 1)
        XCTAssertEqual(recorder.frames[0].data.count, 960)
        XCTAssertEqual(recorder.frames[0].data, Data(repeating: 0, count: 960))
    }

    func testDecoderReleaseIsIdempotentWhilePlaybackIsWaiting() async throws {
        let fileURL = try makePCM16WAV(
            pcmData: Data(repeating: 0, count: 960)
        )
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let recorder = AudioFileFrameDecoderRecorder()
        let decoder = try await AudioFileFrameDecoder(
            fileURL: fileURL,
            playbackAnchorUs: AudioFileFrameDecoder.currentTimestampUs()
                + 5_000_000,
            mediaStartUs: 0,
            cycleDurationUs: 10_000,
            onFrame: { recorder.onFrame($0) },
            onEndOfStream: { recorder.onEndOfStream() },
            onError: { recorder.onError(message: $0) }
        )

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    decoder.release()
                }
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(recorder.frames.isEmpty)
        XCTAssertNil(recorder.errorMessage)
    }

    private func makePCM16WAV(
        pcmData: Data,
        sampleRate: Int = AudioFrame.sampleRate,
        channelCount: Int = AudioFrame.channelCount
    ) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        var wavData = Data("RIFF".utf8)
        wavData.appendLittleEndian(UInt32(36 + pcmData.count))
        wavData.append(Data("WAVEfmt ".utf8))
        wavData.appendLittleEndian(UInt32(16))
        wavData.appendLittleEndian(UInt16(1))
        wavData.appendLittleEndian(UInt16(channelCount))
        wavData.appendLittleEndian(UInt32(sampleRate))
        wavData.appendLittleEndian(UInt32(
            sampleRate * channelCount * MemoryLayout<Int16>.size
        ))
        wavData.appendLittleEndian(UInt16(
            channelCount * MemoryLayout<Int16>.size
        ))
        wavData.appendLittleEndian(UInt16(16))
        wavData.append(Data("data".utf8))
        wavData.appendLittleEndian(UInt32(pcmData.count))
        wavData.append(pcmData)
        try wavData.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

private final class AudioFileFrameDecoderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let frameExpectation: XCTestExpectation?
    private let terminalExpectation: XCTestExpectation?
    private var receivedFrames: [AudioFrame] = []
    private var receivedErrorMessage: String?

    var frames: [AudioFrame] {
        lock.withLock { receivedFrames }
    }

    var errorMessage: String? {
        lock.withLock { receivedErrorMessage }
    }

    init(
        frameExpectation: XCTestExpectation? = nil,
        terminalExpectation: XCTestExpectation? = nil
    ) {
        self.frameExpectation = frameExpectation
        self.terminalExpectation = terminalExpectation
    }

    func onFrame(_ frame: AudioFrame) {
        lock.withLock {
            receivedFrames.append(frame)
        }
        frameExpectation?.fulfill()
    }

    func onEndOfStream() {
        terminalExpectation?.fulfill()
    }

    func onError(message: String) {
        lock.withLock {
            receivedErrorMessage = message
        }
        terminalExpectation?.fulfill()
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}
