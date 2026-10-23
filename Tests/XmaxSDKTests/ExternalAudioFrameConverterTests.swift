//
//  ExternalAudioFrameConverterTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AVFoundation
import CoreMedia
import XCTest
@testable import XmaxSDK

final class ExternalAudioFrameConverterTests: XCTestCase {
    func testPCM16PacketsRetainOriginalTimeline() throws {
        let converter = ExternalAudioFrameConverter()
        let frames = Recorder()
        try converter.append(
            AudioSampleBufferFactory.make(count: 960, timestamp: CMTime(value: 2125, timescale: 1000)),
            handler: { frames.append($0) }
        )
        XCTAssertEqual(frames.values.map(\.timestampUs), [2125000, 2135000])
        XCTAssertEqual(frames.values.map { $0.data.count }, [960, 960])
        let firstSample = try XCTUnwrap(frames.values.first).data.withUnsafeBytes { $0.load(as: Int16.self) }
        XCTAssertEqual(firstSample, 1000)
    }

    func testSmallBuffersCombineWithoutLosingSamplesOrTiming() throws {
        let converter = ExternalAudioFrameConverter()
        let frames = Recorder()
        for index in 0..<20 {
            try converter.append(
                AudioSampleBufferFactory.make(
                    count: 240,
                    timestamp: CMTime(value: Int64(index * 5), timescale: 1000),
                    value: Int16(index + 1)
                ),
                handler: { frames.append($0) }
            )
        }
        XCTAssertEqual(frames.values.count, 10)
        XCTAssertEqual(frames.values.map(\.timestampUs), (0..<10).map { Int64($0 * 10000) })
        let data = try XCTUnwrap(frames.values.first).data
        XCTAssertEqual(data.withUnsafeBytes { $0.load(as: Int16.self) }, 1)
        XCTAssertEqual(data.withUnsafeBytes { $0.load(fromByteOffset: 480, as: Int16.self) }, 2)
    }

    func testResamplesStereoFloatPCMWithoutRebasingTimestamps() throws {
        let converter = ExternalAudioFrameConverter()
        let frames = Recorder()
        for index in 0..<10 {
            try converter.append(
                AudioSampleBufferFactory.make(
                    count: 441,
                    timestamp: CMTime(value: Int64(2000 + index * 10), timescale: 1000),
                    sampleRate: 44100,
                    channels: 2,
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                ),
                handler: { frames.append($0) }
            )
        }
        XCTAssertGreaterThanOrEqual(frames.values.count, 9)
        XCTAssertLessThanOrEqual(frames.values.count, 10)
        XCTAssertEqual(frames.values.first?.timestampUs, 2000000)
        for (index, frame) in frames.values.enumerated() {
            XCTAssertEqual(frame.timestampUs, 2000000 + Int64(index * 10000))
            XCTAssertEqual(frame.data.count, 960)
        }
        XCTAssertTrue(frames.values.contains { $0.data.contains { $0 != 0 } })
    }

    func testGapsDiscardPartialPacketsWithoutInsertingSilence() throws {
        let converter = ExternalAudioFrameConverter()
        let frames = Recorder()
        try converter.append(
            AudioSampleBufferFactory.make(count: 240, timestamp: CMTime(value: 2, timescale: 1), value: 1),
            handler: { frames.append($0) }
        )
        try converter.append(
            AudioSampleBufferFactory.make(timestamp: CMTime(value: 60, timescale: 1), value: 2),
            handler: { frames.append($0) }
        )
        XCTAssertEqual(frames.values.map(\.timestampUs), [60000000])
        let sample = try XCTUnwrap(frames.values.first).data.withUnsafeBytes { $0.load(as: Int16.self) }
        XCTAssertEqual(sample, 2)
    }

    func testInvalidDuplicateAndOverlappingTimestampsAreIgnored() throws {
        let converter = ExternalAudioFrameConverter()
        let frames = Recorder()
        let times = [CMTime.invalid, .indefinite, CMTime(value: -1, timescale: 1),
                     CMTime(value: 2, timescale: 1), CMTime(value: 2, timescale: 1),
                     CMTime(value: 2005, timescale: 1000), CMTime(value: 2010, timescale: 1000)]
        for time in times {
            try converter.append(
                AudioSampleBufferFactory.make(timestamp: time),
                handler: { frames.append($0) }
            )
        }
        XCTAssertEqual(frames.values.map(\.timestampUs), [2000000, 2010000])
    }

    func testFormatChangeFailsTheBinding() throws {
        let converter = ExternalAudioFrameConverter()
        try converter.append(AudioSampleBufferFactory.make(), handler: { _ in })
        XCTAssertThrowsError(try converter.append(
            AudioSampleBufferFactory.make(timestamp: CMTime(value: 1, timescale: 1), channels: 2),
            handler: { _ in }
        )) { error in
            XCTAssertEqual((error as? XmaxError)?.code, .mediaError)
        }
    }

    func testDuplicateSingleSampleBuffersAreIgnored() throws {
        let converter = ExternalAudioFrameConverter()
        let frames = Recorder()
        let sample = try AudioSampleBufferFactory.make(count: 1, value: 3)
        try converter.append(sample, handler: { frames.append($0) })
        try converter.append(sample, handler: { frames.append($0) })
        try converter.append(
            AudioSampleBufferFactory.make(count: 479, timestamp: CMTime(value: 1, timescale: 48000), value: 7),
            handler: { frames.append($0) }
        )
        let frame = try XCTUnwrap(frames.values.first)
        XCTAssertEqual(frame.timestampUs, 0)
        XCTAssertEqual(frame.data.withUnsafeBytes { $0.load(fromByteOffset: 2, as: Int16.self) }, 7)
    }

    func testInputStorageCanBeReusedBeforePacketCompletes() throws {
        let converter = ExternalAudioFrameConverter()
        let frames = Recorder()
        let first = try AudioSampleBufferFactory.make(count: 240, value: 3)
        try converter.append(first, handler: { frames.append($0) })
        let storage = try XCTUnwrap(CMSampleBufferGetDataBuffer(first))
        XCTAssertEqual(CMBlockBufferFillDataBytes(with: 0, blockBuffer: storage, offsetIntoDestination: 0, dataLength: 480), noErr)
        try converter.append(
            AudioSampleBufferFactory.make(count: 240, timestamp: CMTime(value: 5, timescale: 1000), value: 7),
            handler: { frames.append($0) }
        )
        let frame = try XCTUnwrap(frames.values.first)
        XCTAssertEqual(frame.data.withUnsafeBytes { $0.load(as: Int16.self) }, 3)
        XCTAssertEqual(frame.data.withUnsafeBytes { $0.load(fromByteOffset: 480, as: Int16.self) }, 7)
    }

    private final class Recorder: @unchecked Sendable {
        private(set) var values: [AudioFrame] = []
        func append(_ frame: AudioFrame) { values.append(frame) }
    }
}
