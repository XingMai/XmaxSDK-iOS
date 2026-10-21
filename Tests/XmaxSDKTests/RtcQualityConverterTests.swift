//
//  RtcQualityConverterTests.swift
//  XmaxSDK
//  Repo: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AgoraRtcKit
import XCTest
@testable import XmaxSDK

final class RtcQualityConverterTests: XCTestCase {
    func testUplinkUsesActualMeasurements() {
        let stats = AgoraRtcLocalVideoStats()
        stats.encodedFrameWidth = 832
        stats.encodedFrameHeight = 1472
        stats.captureFrameRate = 29
        stats.encoderOutputFrameRate = 25
        stats.sentFrameRate = 24
        stats.sentBitrate = 1500
        stats.txPacketLossRate = 3

        XCTAssertEqual(
            RtcQualityConverter.uplinkVideoStatistics(stats),
            UplinkVideoStatistics(
                width: 832, height: 1472, captureFrameRate: 29,
                encodeFrameRate: 25, sendFrameRate: 24, bitrateKbps: 1500, packetLossPercent: 3
            )
        )
    }

    func testInvalidUplinkMetricsRemainUnavailable() {
        let stats = AgoraRtcLocalVideoStats()
        stats.encodedFrameWidth = 0
        stats.encodedFrameHeight = -1
        stats.captureFrameRate = -1
        stats.encoderOutputFrameRate = -1
        stats.txPacketLossRate = 101
        let result = RtcQualityConverter.uplinkVideoStatistics(stats)

        XCTAssertNil(result.width)
        XCTAssertNil(result.height)
        XCTAssertNil(result.captureFrameRate)
        XCTAssertNil(result.encodeFrameRate)
        XCTAssertNil(result.packetLossPercent)
        XCTAssertEqual(result.sendFrameRate, 0)
        XCTAssertEqual(result.bitrateKbps, 0)
    }

    func testDownlinkNormalizesInvalidMeasurements() {
        let stats = AgoraRtcRemoteVideoStats()
        stats.width = 704
        stats.height = 1280
        stats.decoderOutputFrameRate = -1
        stats.rendererOutputFrameRate = 24
        stats.packetLossRate = -1
        stats.receivedBitrate = 2100
        stats.e2eDelay = 85
        let result = RtcQualityConverter.downlinkVideoStatistics(userID: "bot", stats)

        XCTAssertEqual(result.userID, "bot")
        XCTAssertEqual(result.width, 704)
        XCTAssertEqual(result.height, 1280)
        XCTAssertNil(result.decodeFrameRate)
        XCTAssertEqual(result.renderFrameRate, 24)
        XCTAssertNil(result.packetLossPercent)
        XCTAssertEqual(result.bitrateKbps, 2100)
        XCTAssertEqual(result.endToEndDelayMs, 85)
    }
}
