//
//  RtcMessageQueueTests.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import XCTest
@testable import XmaxSDK

final class RtcMessageQueueTests: XCTestCase {
    func testRecoverableConfigurationFailureDoesNotPoisonNextMessage() async throws {
        let recorder = PacketRecorder()
        let queue = RtcMessageQueue(send: { data in
            if data == Data("resize".utf8) {
                throw XmaxError(code: .rtcError, message: "resize failed")
            }
            recorder.append(data)
        }, onFailure: { _ in XCTFail("Recoverable configuration must not terminate the room") })
        let resize = try queue.enqueue("resize", reportFailure: false)
        try queue.enqueue("next condition")
        try await queue.flush()
        do {
            try await RtcMessageQueue.waitForCompletion(of: resize)
            XCTFail("A later successful message must not hide the configuration failure")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.message, "resize failed")
        }
        XCTAssertEqual(recorder.packets, [Data("next condition".utf8)])
        queue.close()
    }

    func testSmallMessageIsSentWithoutEnvelope() throws {
        let message = #"{"event":"heartbeat","user_id":"account"}"#
        XCTAssertEqual(try RtcMessageCodec.encode(message), [Data(message.utf8)])
    }

    func testFragmentedUnicodeAndEscapesRoundTripWithinPacketLimit() throws {
        let message = String(repeating: "中文🙂\\\"\n/", count: 250)
        let packets = try RtcMessageCodec.encode(message)
        XCTAssertGreaterThan(packets.count, 1)
        var result = ""
        var identifier: String?
        for (index, packet) in packets.enumerated() {
            XCTAssertLessThanOrEqual(packet.count, 800)
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: packet) as? [String: Any])
            XCTAssertEqual(value["event"] as? String, "__agora_chunk__")
            XCTAssertEqual(value["index"] as? Int, index)
            XCTAssertEqual(value["count"] as? Int, packets.count)
            let currentID = try XCTUnwrap(value["eventId"] as? String)
            if let identifier { XCTAssertEqual(currentID, identifier) }
            identifier = currentID
            result += try XCTUnwrap(value["data"] as? String)
        }
        XCTAssertEqual(result, message)
    }

    func testCodecRejectsEmptyAndOversizedMessages() {
        XCTAssertThrowsError(try RtcMessageCodec.encode(""))
        XCTAssertThrowsError(try RtcMessageCodec.encode(String(repeating: "a", count: 262145)))
    }

    func testQueuePreservesWholeMessageOrderAndFlushes() async throws {
        let recorder = PacketRecorder()
        let queue = RtcMessageQueue(send: recorder.append, onFailure: { _ in })
        let first = String(repeating: "a", count: 1200)
        try queue.enqueue(first)
        try queue.enqueue("last")
        try await queue.flush()
        XCTAssertEqual(recorder.packets.last, Data("last".utf8))
        XCTAssertEqual(recorder.packets.count, 3)
        queue.close()
        XCTAssertThrowsError(try queue.enqueue("after close"))
    }

    func testQueueRespectsByteRateLimit() async throws {
        let recorder = PacketRecorder()
        let queue = RtcMessageQueue(send: recorder.append, onFailure: { _ in })
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<8 { try queue.enqueue(String(repeating: "a", count: 800)) }
        try await queue.flush()
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        XCTAssertGreaterThanOrEqual(elapsed, 1000000000)
        XCTAssertEqual(recorder.packets.count, 8)
        queue.close()
    }

    func testQueueFlushReportsSendFailure() async throws {
        let expected = XmaxError(code: .rtcError, message: "send failed")
        let queue = RtcMessageQueue(send: { _ in throw expected }, onFailure: { _ in })
        try queue.enqueue("start")
        do {
            try await queue.flush()
            XCTFail("Expected send failure")
        } catch {
            XCTAssertEqual(error as? XmaxError, expected)
        }
        queue.close()
    }

    func testCancellingFlushDoesNotCancelQueuedMessages() async throws {
        let recorder = PacketRecorder()
        let queue = RtcMessageQueue(send: recorder.append, onFailure: { _ in })
        for _ in 0..<8 { try queue.enqueue(String(repeating: "a", count: 800)) }
        let flush = Task { try await queue.flush() }
        flush.cancel()
        do {
            try await flush.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        try await queue.flush()
        XCTAssertEqual(recorder.packets.count, 8)
        queue.close()
    }
}

private final class PacketRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data] = []

    var packets: [Data] { lock.withLock { values } }

    func append(_ data: Data) {
        lock.withLock { values.append(data) }
    }
}
