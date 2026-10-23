//
//  RemoteMediaFrameTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import CoreVideo
import Foundation
import XCTest
@preconcurrency import AgoraRtcKit
@testable import XmaxSDK

final class RemoteMediaFrameTests: XCTestCase {

    func testNativeMediaCallbacksCompleteWhileEngineOperationWaits() throws {
        let listeners = RtcRemoteFrameListeners(roomID: "room")
        let received = NativeAudioRecorder()
        let videoReceived = DispatchSemaphore(value: 0)
        listeners.setAudioListener({ received.append($0) }, for: 7)
        listeners.setVideoListener({ _ in videoReceived.signal() }, for: 7)
        let sink = RtcRemoteAudioSink { uid, channel in
            listeners.audioListener(for: uid, channelID: channel)
        }
        let frame = try videoPacket(1_000)
        let completed = DispatchSemaphore(value: 0)
        // Model an engine operation holding its lock while waiting for its media worker.
        // The native worker must resolve both listeners without acquiring that lock.
        let engineLock = NSRecursiveLock()
        engineLock.lock()
        DispatchQueue.global().async {
            Data(repeating: 0x35, count: 960).withUnsafeBytes { bytes in
                sink.capturePCM(bytes.baseAddress, channelID: "room", uid: 7,
                    samplesPerChannel: 480, sampleRate: 48_000, channels: 1,
                    bytesPerSample: 2, renderTimeMs: 1_000)
            }
            listeners.videoListener(for: 7, channelID: "room")?(frame)
            completed.signal()
        }
        let result = completed.wait(timeout: .now() + 2)
        engineLock.unlock()
        XCTAssertEqual(result, .success)
        XCTAssertEqual(received.frames.count, 1)
        XCTAssertEqual(videoReceived.wait(timeout: .now()), .success)
    }

    func testClosingListenersDoesNotWaitForRunningNativeCallback() {
        let listeners = RtcRemoteFrameListeners(roomID: "room")
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        listeners.setAudioListener({ _ in
            entered.signal()
            _ = release.wait(timeout: .now() + 3)
        }, for: 7)
        DispatchQueue.global().async {
            listeners.audioListener(for: 7, channelID: "room")?(audioPacket(1_000))
            finished.signal()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        let closed = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            listeners.close()
            closed.signal()
        }
        let result = closed.wait(timeout: .now() + 1)
        release.signal()
        XCTAssertEqual(result, .success)
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success)
        XCTAssertNil(listeners.audioListener(for: 7, channelID: "room"))
        listeners.setAudioListener({ _ in XCTFail("Closed room must reject registration") }, for: 7)
        XCTAssertNil(listeners.audioListener(for: 7, channelID: "room"))
    }

    func testNativeListenerSnapshotsFilterRoomAndUserAndAllowRemoval() {
        let listeners = RtcRemoteFrameListeners(roomID: "room")
        listeners.setAudioListener({ _ in }, for: 7)
        listeners.setVideoListener({ _ in }, for: 7)
        XCTAssertNil(listeners.audioListener(for: 7, channelID: "other"))
        XCTAssertNil(listeners.audioListener(for: 8, channelID: "room"))
        XCTAssertNil(listeners.videoListener(for: 7, channelID: "other"))
        XCTAssertNil(listeners.videoListener(for: 8, channelID: "room"))
        XCTAssertNotNil(listeners.audioListener(for: 7, channelID: "room"))
        XCTAssertNotNil(listeners.videoListener(for: 7, channelID: "room"))
        listeners.setAudioListener(nil, for: 7)
        listeners.setVideoListener(nil, for: 7)
        XCTAssertNil(listeners.audioListener(for: 7, channelID: "room"))
        XCTAssertNil(listeners.videoListener(for: 7, channelID: "room"))
    }

    func testBatchedNativeTimesAdvanceBySamplesWithoutLosingVideoOffset() throws {
        let queue = DispatchQueue(label: "test.media.offset")
        let output = RealtimeMediaFrameDispatcher(deliveryQueue: queue)
        let recorder = MediaOutputRecorder()
        output.setListener { recorder.append($0) }
        let id = try XCTUnwrap(output.setStream(active: true))
        output.dispatchVideo(try videoPacket(935), streamID: id)
        for time in [1_000, 1_000, 1_020, 1_020] {
            output.dispatchAudio(audioPacket(Int64(time)), streamID: id)
        }
        queue.sync {}

        let events = recorder.frames
        XCTAssertEqual(events.count, 5)
        XCTAssertTrue(events.allSatisfy { $0.streamID == id })
        XCTAssertEqual(events.map { CMTimeConvertScale($0.presentationTimeStamp, timescale: 1_000, method: .default).value }, [935, 1_000, 1_010, 1_020, 1_030])
        XCTAssertEqual(events.map(\.isDiscontinuous), [true, true, false, false, false])
        XCTAssertEqual(events[1].duration, CMTime(value: 1, timescale: 100))
        XCTAssertFalse(recorder.ranOnMainThread)
    }

    func testLongBatchedAudioRunDoesNotAccumulateFloatingPointError() throws {
        var timeline = RemoteAudioTimeline()
        var last: RealtimeAudioFrame?
        for index in 0..<7_656 {
            let nativeTime = 1_792_752_953_188 + Int64(index / 2) * 20
            let result = try XCTUnwrap(timeline.resolve(audioPacket(nativeTime)))
            XCTAssertEqual(result.discontinuous, index == 0)
            last = result.frame
        }
        let end = CMTimeAdd(try XCTUnwrap(last).presentationTimeStamp, try XCTUnwrap(last).duration)
        XCTAssertEqual(CMTimeSubtract(end, CMTime(value: 1_792_752_953_188, timescale: 1_000)), CMTime(value: 7_656, timescale: 100))
    }

    func testClockJumpsAndFormatChangesExposeDiscontinuities() throws {
        var timeline = RemoteAudioTimeline()
        _ = try XCTUnwrap(timeline.resolve(audioPacket(1_000)))
        let forward = try XCTUnwrap(timeline.resolve(audioPacket(2_000)))
        XCTAssertEqual(forward.frame.presentationTimeStamp, CMTime(value: 2, timescale: 1))
        XCTAssertTrue(forward.discontinuous)
        let backward = try XCTUnwrap(timeline.resolve(audioPacket(500)))
        XCTAssertEqual(backward.frame.presentationTimeStamp, CMTime(value: 1, timescale: 2))
        XCTAssertTrue(backward.discontinuous)
        let formatChange = RtcRemoteAudioFrame(data: Data(repeating: 0, count: 1_764), sampleRate: 44_100, channels: 2, samplesPerChannel: 441, renderTimeMs: 511)
        let changed = try XCTUnwrap(timeline.resolve(formatChange))
        XCTAssertEqual(changed.frame.presentationTimeStamp, CMTime(value: 511, timescale: 1_000))
        XCTAssertEqual(changed.frame.duration, CMTime(value: 1, timescale: 100))
        XCTAssertTrue(changed.discontinuous)
    }

    func testInvalidPCMAndMissingClockAreRejectedRatherThanInventingTimes() throws {
        var timeline = RemoteAudioTimeline()
        _ = timeline.resolve(audioPacket(1_000))
        XCTAssertNil(timeline.resolve(audioPacket(0)))
        XCTAssertTrue(try XCTUnwrap(timeline.resolve(audioPacket(1_020))).discontinuous)
        let invalid = RtcRemoteAudioFrame(data: Data([0]), sampleRate: 48_000, channels: 1, samplesPerChannel: 480, renderTimeMs: 1_030)
        XCTAssertNil(timeline.resolve(invalid))
    }

    func testQueuePressureKeepsTimeGapAndMarksNextAcceptedPacket() throws {
        let queue = DispatchQueue(label: "test.media.pressure")
        let output = RealtimeMediaFrameDispatcher(maximumPendingFrames: 1, deliveryQueue: queue)
        let recorder = MediaOutputRecorder()
        output.setListener { recorder.append($0) }
        let id = try XCTUnwrap(output.setStream(active: true))
        queue.suspend()
        output.dispatchAudio(audioPacket(1_000), streamID: id)
        output.dispatchAudio(audioPacket(1_010), streamID: id)
        output.dispatchAudio(audioPacket(1_020), streamID: id)
        queue.resume()
        queue.sync {}
        output.dispatchAudio(audioPacket(1_030), streamID: id)
        queue.sync {}

        XCTAssertEqual(recorder.frames.map { CMTimeConvertScale($0.presentationTimeStamp, timescale: 1_000, method: .default).value }, [1_000, 1_030])
        XCTAssertEqual(recorder.frames.map(\.isDiscontinuous), [true, true])
    }

    func testStreamReplacementRejectsQueuedAndLateOldPackets() throws {
        let queue = DispatchQueue(label: "test.media.replacement")
        let output = RealtimeMediaFrameDispatcher(deliveryQueue: queue)
        let recorder = MediaOutputRecorder()
        output.setListener { recorder.append($0) }
        let old = try XCTUnwrap(output.setStream(active: true))
        queue.suspend()
        output.dispatchAudio(audioPacket(1_000), streamID: old)
        let current = try XCTUnwrap(output.setStream(active: true))
        output.dispatchAudio(audioPacket(1_010), streamID: old)
        output.dispatchAudio(audioPacket(2_000), streamID: current)
        queue.resume()
        queue.sync {}

        XCTAssertNotEqual(old, current)
        XCTAssertEqual(recorder.frames.count, 1)
        XCTAssertEqual(recorder.frames.first?.streamID, current)
        output.setStream(active: false)
        output.dispatchAudio(audioPacket(2_010), streamID: current)
        queue.sync {}
        XCTAssertEqual(recorder.frames.count, 1)
    }

    func testByteLimitDiscardsOversizedOutputWithoutBlockingLaterAudio() throws {
        let queue = DispatchQueue(label: "test.media.bytes")
        let output = RealtimeMediaFrameDispatcher(maximumPendingBytes: 960, deliveryQueue: queue)
        let recorder = MediaOutputRecorder()
        output.setListener { recorder.append($0) }
        let id = try XCTUnwrap(output.setStream(active: true))
        output.dispatchVideo(try videoPacket(1_000), streamID: id)
        output.dispatchAudio(audioPacket(1_000), streamID: id)
        queue.sync {}
        XCTAssertEqual(recorder.frames.count, 1)
        guard case .audio = recorder.frames[0].content else { return XCTFail("Expected audio") }
    }

    func testVideoDimensionChangeStartsADiscontinuousRun() throws {
        let queue = DispatchQueue(label: "test.media.dimensions")
        let output = RealtimeMediaFrameDispatcher(deliveryQueue: queue)
        let recorder = MediaOutputRecorder()
        output.setListener { recorder.append($0) }
        let id = try XCTUnwrap(output.setStream(active: true))
        output.dispatchVideo(try videoPacket(1_000), streamID: id)
        output.dispatchVideo(try videoPacket(1_040), streamID: id)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 32, 16, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        output.dispatchVideo(RealtimeVideoFrame(pixelBuffer: try XCTUnwrap(buffer), presentationTimeStamp: CMTime(value: 1_080, timescale: 1_000)), streamID: id)
        queue.sync {}
        XCTAssertEqual(recorder.frames.map(\.isDiscontinuous), [true, false, true])
    }

    func testNativeInvalidBufferBreaksContinuityWithoutPublishingAnEmptyPacket() throws {
        let queue = DispatchQueue(label: "test.media.invalid-native")
        let output = RealtimeMediaFrameDispatcher(deliveryQueue: queue)
        let recorder = MediaOutputRecorder()
        output.setListener { recorder.append($0) }
        let id = try XCTUnwrap(output.setStream(active: true))
        let sink = RtcRemoteAudioSink { _, _ in
            { output.dispatchAudio($0, streamID: id) }
        }
        output.dispatchAudio(audioPacket(1_000), streamID: id)
        sink.capturePCM(nil, channelID: "room", uid: 7, samplesPerChannel: 480, sampleRate: 48_000, channels: 1, bytesPerSample: 2, renderTimeMs: 1_010)
        output.dispatchAudio(audioPacket(1_020), streamID: id)
        queue.sync {}
        XCTAssertEqual(recorder.frames.count, 2)
        XCTAssertEqual(recorder.frames.map(\.isDiscontinuous), [true, true])
        XCTAssertEqual(recorder.frames[1].presentationTimeStamp, CMTime(value: 1_020, timescale: 1_000))
    }

    func testListenerRemovalAndReplacementDiscardQueuedCallbacks() throws {
        let queue = DispatchQueue(label: "test.media.listener")
        let output = RealtimeMediaFrameDispatcher(deliveryQueue: queue)
        let first = MediaOutputRecorder()
        let second = MediaOutputRecorder()
        output.setListener { first.append($0) }
        let id = try XCTUnwrap(output.setStream(active: true))
        queue.suspend()
        output.dispatchAudio(audioPacket(1_000), streamID: id)
        output.setListener(nil)
        output.setListener { second.append($0) }
        output.dispatchAudio(audioPacket(1_020), streamID: id)
        queue.resume()
        queue.sync {}

        XCTAssertTrue(first.frames.isEmpty)
        XCTAssertEqual(second.frames.count, 1)
        XCTAssertTrue(try XCTUnwrap(second.frames.first).isDiscontinuous)
    }

    func testInvalidAndBackwardVideoPTSRemainExplicit() throws {
        let queue = DispatchQueue(label: "test.media.video")
        let output = RealtimeMediaFrameDispatcher(deliveryQueue: queue)
        let recorder = MediaOutputRecorder()
        output.setListener { recorder.append($0) }
        let id = try XCTUnwrap(output.setStream(active: true))
        let original = try videoPacket(1_000)
        output.dispatchVideo(RealtimeVideoFrame(pixelBuffer: original.pixelBuffer, presentationTimeStamp: .invalid), streamID: id)
        output.dispatchVideo(original, streamID: id)
        output.dispatchVideo(try videoPacket(900), streamID: id)
        queue.sync {}

        XCTAssertEqual(recorder.frames.count, 2)
        XCTAssertEqual(recorder.frames[0].presentationTimeStamp, original.presentationTimeStamp)
        XCTAssertEqual(recorder.frames[1].presentationTimeStamp, CMTime(value: 900, timescale: 1_000))
        XCTAssertTrue(recorder.frames.allSatisfy(\.isDiscontinuous))
        guard case .video(let video) = recorder.frames[0].content else { return XCTFail("Expected video") }
        XCTAssertTrue(video.pixelBuffer === original.pixelBuffer)
    }

    func testNativeAudioBytesAreOwnedAndOnlyMatchingRemoteUserIsDelivered() throws {
        let storage = NativeAudioRecorder()
        let sink = RtcRemoteAudioSink { uid, channel in
            guard uid == 7, channel == "room" else { return nil }
            return { storage.append($0) }
        }
        var data = Data(repeating: 0x35, count: 960)
        data.withUnsafeMutableBytes { bytes in
            for (uid, room) in [(UInt(8), "room"), (UInt(7), "other"), (UInt(7), "room")] {
                sink.capturePCM(bytes.baseAddress, channelID: room, uid: uid, samplesPerChannel: 480, sampleRate: 48_000, channels: 1, bytesPerSample: 2, renderTimeMs: 1_000)
            }
            bytes.initializeMemory(as: UInt8.self, repeating: 0)
        }
        let packet = try XCTUnwrap(storage.frames.first)
        XCTAssertEqual(storage.frames.count, 1)
        XCTAssertEqual(packet.data, Data(repeating: 0x35, count: 960))
        XCTAssertEqual(packet.renderTimeMs, 1_000)
        XCTAssertTrue(sink.responds(to: NSSelectorFromString("onPlaybackAudioFrameBeforeMixing:channelId:uid:")))
        XCTAssertEqual(sink.getObservedAudioFramePosition(), .beforeMixing)
        XCTAssertFalse(sink.responds(to: NSSelectorFromString("onPlaybackAudioFrame:channelId:")))
    }
}

/// Collects output without assuming callback thread or cross-track presentation order.
final class MediaOutputRecorder: @unchecked Sendable {

    private let lock = NSLock()
    private var recorded: [RealtimeMediaFrame] = []
    private var mainThread = false

    var frames: [RealtimeMediaFrame] { lock.withLock { recorded } }
    var ranOnMainThread: Bool { lock.withLock { mainThread } }

    func append(_ frame: RealtimeMediaFrame) {
        lock.withLock {
            recorded.append(frame)
            mainThread = mainThread || Thread.isMainThread
        }
    }
}

private final class NativeAudioRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [RtcRemoteAudioFrame] = []
    var frames: [RtcRemoteAudioFrame] { lock.withLock { recorded } }
    func append(_ frame: RtcRemoteAudioFrame) { lock.withLock { recorded.append(frame) } }
}

func audioPacket(_ renderMs: Int64) -> RtcRemoteAudioFrame {
    RtcRemoteAudioFrame(data: Data(repeating: 0x25, count: 960), sampleRate: 48_000, channels: 1, samplesPerChannel: 480, renderTimeMs: renderMs)
}

private func videoPacket(_ renderMs: Int64) throws -> RealtimeVideoFrame {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
    return RealtimeVideoFrame(pixelBuffer: try XCTUnwrap(buffer), presentationTimeStamp: CMTime(value: renderMs, timescale: 1_000))
}
