//
//  RtcFoundationTests.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import Foundation
@preconcurrency import AgoraRtcKit
import XCTest
@testable import XmaxSDK

final class RtcFoundationTests: XCTestCase {
    func testEncoderConverterPreservesBitratesAndMapsPreferences() {
        let cases: [(VideoEncodingConfiguration.EncoderPreference, AgoraDegradationPreference)] = [
            (.auto, .maintainAuto),
            (.maintainFramerate, .maintainFramerate),
            (.maintainQuality, .maintainQuality)
        ]
        for (preference, expected) in cases {
            let converted = RtcVideoConverter.makeEncoderConfiguration(VideoEncodingConfiguration(
                width: 832, height: 1472, frameRate: 24,
                minimumBitrate: 1500, maximumBitrate: 3000,
                encoderPreference: preference
            ))
            XCTAssertEqual(converted.dimensions.width, 832)
            XCTAssertEqual(converted.dimensions.height, 1472)
            XCTAssertEqual(converted.frameRate, 24)
            XCTAssertEqual(converted.minBitrate, 1500)
            XCTAssertEqual(converted.bitrate, 3000)
            XCTAssertEqual(converted.degradationPreference, expected)
        }
    }


    func testRemoteStreamBuildsStableKey() {
        XCTAssertEqual(RemoteStream(roomID: "room-a", userID: "user-b").key, "room-a:user-b")
    }

    func testVideoEncodingConfigurationUsesAdaptiveBitrateDefaults() {
        let configuration = VideoEncodingConfiguration(width: 720, height: 1280, frameRate: 24)
        XCTAssertEqual(configuration.minimumBitrate, 0)
        XCTAssertEqual(configuration.maximumBitrate, -1)
        XCTAssertEqual(configuration.encoderPreference, .maintainFramerate)
        XCTAssertEqual(
            RtcVideoConverter.makeEncoderConfiguration(configuration).degradationPreference,
            .maintainFramerate
        )
    }

    func testQualityConverterMapsKnownAndUnsupportedLevels() {
        for level in RtcQualityLevel.allCases {
            let agora = AgoraNetworkQuality(rawValue: UInt(level.rawValue))!
            XCTAssertEqual(RtcQualityConverter.convertLevel(agora), level)
        }
        XCTAssertEqual(RtcQualityConverter.convertLevel(.detecting), .unknown)
    }

    func testAudioConverterPreservesPCMDataAndRejectsIncompleteFrame() throws {
        let data = Data(repeating: 7, count: 960)
        XCTAssertEqual(try RtcAudioConverter.convertFrame(AudioFrame(data: data, timestampUs: 10000)), data)
        XCTAssertThrowsError(try RtcAudioConverter.convertFrame(AudioFrame(data: Data(repeating: 0, count: 958), timestampUs: 0)))
    }

    func testVideoConverterOwnsSelectedPlaneRangesAndRemovesPadding() throws {
        let frame = try VideoFrame(
            format: VideoFormat(width: 2, height: 2, pixelFormat: .nv12),
            timestampUs: 12345,
            planes: [
                VideoFramePlane(data: Data([99, 1, 2, 88, 3, 4, 98]), stride: 3, byteOffset: 1, byteLength: 5),
                VideoFramePlane(data: Data([97, 5, 6, 96]), stride: 2, byteOffset: 1, byteLength: 2)
            ],
            rotation: .rotation90
        )
        let converted = try RtcVideoConverter.convertFrame(frame).value
        XCTAssertEqual(converted.format, 8)
        XCTAssertEqual(converted.strideInPixels, 2)
        XCTAssertEqual(converted.height, 2)
        XCTAssertEqual(converted.rotation, 90)
        XCTAssertEqual(converted.dataBuf, Data([1, 2, 3, 4, 5, 6]))
        XCTAssertEqual(CMTimeConvertScale(converted.time, timescale: 1000000, method: .default).value, 12345)
    }

    func testVideoConverterRetainsDataAfterSourceIsReleased() throws {
        let converted: RtcVideoFrame = try autoreleasepool {
            var data = Data((0..<24).map(UInt8.init))
            let frame = try VideoFrame(
                format: VideoFormat(width: 4, height: 4, pixelFormat: .nv12), timestampUs: 0,
                planes: [
                    VideoFramePlane(data: data, stride: 4, byteLength: 16),
                    VideoFramePlane(data: data, stride: 4, byteOffset: 16, byteLength: 8)
                ]
            )
            let result = try RtcVideoConverter.convertFrame(frame)
            data[0] = 255
            return result
        }
        XCTAssertEqual(converted.value.dataBuf, Data((0..<24).map(UInt8.init)))
    }

    func testVideoConverterRejectsWrongPlaneCountAndShortRows() throws {
        let missingPlane = try VideoFrame(
            format: VideoFormat(width: 2, height: 2, pixelFormat: .i420), timestampUs: 0,
            planes: [VideoFramePlane(data: Data(repeating: 0, count: 4), stride: 2)]
        )
        XCTAssertThrowsError(try RtcVideoConverter.convertFrame(missingPlane))
        let shortPlane = try VideoFrame(
            format: VideoFormat(width: 2, height: 2, pixelFormat: .bgra), timestampUs: 0,
            planes: [VideoFramePlane(data: Data(repeating: 0, count: 8), stride: 8)]
        )
        XCTAssertThrowsError(try RtcVideoConverter.convertFrame(shortPlane))
    }

    func testVideoFrameCacheReusesStaticPixelsAndUpdatesTimestamp() throws {
        let format = try VideoFormat(width: 2, height: 2, pixelFormat: .bgra)
        let plane = try VideoFramePlane(data: Data(repeating: 7, count: 16), stride: 8)
        let id = UUID()
        let cache = RtcVideoFrameCache()
        let first = try cache.frame(for: VideoFrame(format: format, timestampUs: 1000, planes: [plane], bufferReuseID: id))
        let second = try cache.frame(for: VideoFrame(format: format, timestampUs: 2000, planes: [plane], bufferReuseID: id))
        XCTAssertTrue(first === second)
        XCTAssertEqual(CMTimeConvertScale(second.value.time, timescale: 1000000, method: .default).value, 2000)
    }
}
