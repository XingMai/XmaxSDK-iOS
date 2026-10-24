//
//  RemoteMediaOutputTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import XCTest
@testable import XmaxSDK

@MainActor
final class RemoteMediaOutputTests: XCTestCase {

    func testUnifiedOutputReceivesPCMAndFinalVideoWithoutAView() async throws {
        let rtc = RtcManagingStub()
        let controller = RenderController(rtcManager: rtc)
        let stream = RemoteStream(roomID: "room", userID: "bot")
        let recorder = MediaOutputRecorder()
        let media = expectation(description: "Both output tracks")
        media.expectedFulfillmentCount = 2
        try controller.setRemoteMediaFrameListener { frame in
            recorder.append(frame)
            media.fulfill()
        }
        try controller.setRemoteStream(stream)
        rtc.emitRemoteAudioFrame(audioPacket(1_065))
        try rtc.emitRemoteVideoFrame(presentationTimeStamp: CMTime(value: 1_000, timescale: 1_000))
        await fulfillment(of: [media], timeout: 3)

        let frames = recorder.frames
        XCTAssertEqual(Set(frames.map(\.streamID)).count, 1)
        let audio = try XCTUnwrap(frames.first { if case .audio = $0.content { true } else { false } })
        let video = try XCTUnwrap(frames.first { if case .video = $0.content { true } else { false } })
        XCTAssertEqual(CMTimeSubtract(audio.presentationTimeStamp, video.presentationTimeStamp), CMTime(value: 65, timescale: 1_000))
        XCTAssertEqual(video.duration, CMTime(value: 1, timescale: 24))
        XCTAssertFalse(rtc.calls.contains { if case .setRemoteAudioVolume = $0 { true } else { false } })
        try await controller.resetRemoteTrack(nil)
    }

    func testRegisteringAfterBindingAndClearingOnlyChangesAudioObservation() async throws {
        let rtc = RtcManagingStub()
        let controller = RenderController(rtcManager: rtc)
        let stream = RemoteStream(roomID: "room", userID: "bot")
        try controller.setRemoteStream(stream)
        try controller.setRemoteMediaFrameListener { _ in }
        try controller.setRemoteMediaFrameListener(nil)
        XCTAssertEqual(rtc.calls, [
            .setRemoteVideoFrameListener(stream, enabled: true),
            .setRemoteAudioFrameListener(stream, enabled: true),
            .setRemoteAudioFrameListener(stream, enabled: false)
        ])
        try await controller.resetRemoteTrack(nil)
    }

    func testReplacingStreamRebindsAudioAndRetainsListener() async throws {
        let rtc = RtcManagingStub()
        let controller = RenderController(rtcManager: rtc)
        let first = RemoteStream(roomID: "room", userID: "first")
        let second = RemoteStream(roomID: "room", userID: "second")
        let recorder = MediaOutputRecorder()
        let firstReceived = expectation(description: "First stream")
        let secondReceived = expectation(description: "Second stream")
        try controller.setRemoteMediaFrameListener {
            recorder.append($0)
            if recorder.frames.count == 1 { firstReceived.fulfill() } else { secondReceived.fulfill() }
        }
        try controller.setRemoteStream(first)
        rtc.emitRemoteAudioFrame(audioPacket(1_000))
        await fulfillment(of: [firstReceived], timeout: 2)
        try controller.setRemoteStream(second)
        rtc.emitRemoteAudioFrame(audioPacket(2_000))
        await fulfillment(of: [secondReceived], timeout: 2)

        XCTAssertNotEqual(recorder.frames[0].streamID, recorder.frames[1].streamID)
        XCTAssertTrue(recorder.frames.allSatisfy(\.isDiscontinuous))
        XCTAssertTrue(rtc.calls.contains(.setRemoteAudioFrameListener(first, enabled: false)))
        XCTAssertTrue(rtc.calls.contains(.setRemoteAudioFrameListener(second, enabled: true)))
        try await controller.resetRemoteTrack(nil)
    }

    func testAudioAttachmentFailureIsReportedWithoutRemovingVideo() async throws {
        let error = XmaxError(code: .rtcError, message: "Audio observation failed")
        let rtc = RtcManagingStub(setRemoteAudioFrameListenerError: error)
        let controller = RenderController(rtcManager: rtc)
        let stream = RemoteStream(roomID: "room", userID: "bot")
        try controller.setRemoteStream(stream)
        XCTAssertThrowsError(try controller.setRemoteMediaFrameListener { _ in }) {
            XCTAssertEqual(($0 as? XmaxError)?.code, .rtcError)
        }
        XCTAssertFalse(rtc.calls.contains(.setRemoteVideoFrameListener(stream, enabled: false)))
        try await controller.resetRemoteTrack(nil)
    }

    func testFailedNativeRemovalStillAllowsRebindingTheSameStream() async throws {
        let rtc = RtcManagingStub()
        let controller = RenderController(rtcManager: rtc)
        let stream = RemoteStream(roomID: "same-room", userID: "same-user")
        let recorder = MediaOutputRecorder()
        let first = expectation(description: "Original binding")
        let second = expectation(description: "New binding after cleanup failure")
        try controller.setRemoteMediaFrameListener {
            recorder.append($0)
            if recorder.frames.count == 1 { first.fulfill() } else { second.fulfill() }
        }
        try controller.setRemoteStream(stream)
        rtc.emitRemoteAudioFrame(audioPacket(1_000))
        await fulfillment(of: [first], timeout: 2)
        rtc.failNextAudioListenerRemoval(XmaxError(code: .rtcError, message: "Removal failed"))
        do {
            try await controller.resetRemoteTrack(nil)
            XCTFail("Expected the cleanup error")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .rtcError)
        }
        // The stub still owns a late native callback, which must not revive the old binding.
        rtc.emitRemoteAudioFrame(audioPacket(1_010))
        try controller.setRemoteStream(stream)
        rtc.emitRemoteAudioFrame(audioPacket(2_000))
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(recorder.frames.count, 2)
        XCTAssertNotEqual(recorder.frames[0].streamID, recorder.frames[1].streamID)
        try await controller.resetRemoteTrack(nil)
    }
}
