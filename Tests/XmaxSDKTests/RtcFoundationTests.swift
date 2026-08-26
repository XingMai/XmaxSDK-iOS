import CoreMedia
import Foundation
import UIKit
@preconcurrency import VolcEngineRTC
import XCTest
@testable import XmaxSDK

final class RtcFoundationTests: XCTestCase {
    func testRemoteStreamBuildsStableKey() {
        let stream = RemoteStream(roomID: "room-a", userID: "user-b")

        XCTAssertEqual(stream.key, "room-a:user-b")
    }

    func testVideoEncodingConfigurationUsesAdaptiveBitrateDefaults() {
        let configuration = VideoEncodingConfiguration(
            width: 720,
            height: 1280,
            frameRate: 24
        )

        XCTAssertEqual(configuration.minimumBitrate, 0)
        XCTAssertEqual(configuration.maximumBitrate, -1)
    }

    func testQualityConverterMapsAllKnownLevels() {
        XCTAssertEqual(RtcQualityConverter.convertLevel(.unknown), .unknown)
        XCTAssertEqual(RtcQualityConverter.convertLevel(.excellent), .excellent)
        XCTAssertEqual(RtcQualityConverter.convertLevel(.good), .good)
        XCTAssertEqual(RtcQualityConverter.convertLevel(.poor), .poor)
        XCTAssertEqual(RtcQualityConverter.convertLevel(.bad), .bad)
        XCTAssertEqual(RtcQualityConverter.convertLevel(.veryBad), .veryBad)
        XCTAssertEqual(RtcQualityConverter.convertLevel(.down), .down)
    }

    func testQualityConverterUsesWorstRemoteDownlink() {
        let excellent = ByteRTCNetworkQualityStats()
        excellent.rxQuality = .excellent
        let bad = ByteRTCNetworkQualityStats()
        bad.rxQuality = .bad
        let good = ByteRTCNetworkQualityStats()
        good.rxQuality = .good

        XCTAssertEqual(
            RtcQualityConverter.resolveDownlinkLevel([excellent, bad, good]),
            .bad
        )
        XCTAssertEqual(RtcQualityConverter.resolveDownlinkLevel([]), .unknown)
    }

    func testQualityConverterResolvesPerformanceState() {
        XCTAssertEqual(
            RtcQualityConverter.resolvePerformanceLimited(.bandwidthFallback),
            true
        )
        XCTAssertEqual(
            RtcQualityConverter.resolvePerformanceLimited(.fallback),
            true
        )
        XCTAssertEqual(
            RtcQualityConverter.resolvePerformanceLimited(.bandwidthResumed),
            false
        )
        XCTAssertEqual(
            RtcQualityConverter.resolvePerformanceLimited(.resumed),
            false
        )
    }

    func testAudioConverterBuildsExternalPCMFrame() throws {
        let data = Data(repeating: 7, count: 960)
        let rtcFrame = try RtcAudioConverter.convertFrame(
            AudioFrame(data: data, timestampUs: 10_000)
        )

        XCTAssertEqual(rtcFrame.buffer, data)
        XCTAssertEqual(rtcFrame.samples, 480)
        XCTAssertEqual(rtcFrame.channel.rawValue, 1)
        XCTAssertEqual(rtcFrame.sampleRate.rawValue, 48_000)
    }

    func testAudioConverterRejectsIncompleteFrame() {
        XCTAssertThrowsError(
            try RtcAudioConverter.convertFrame(
                AudioFrame(data: Data(repeating: 0, count: 958), timestampUs: 0)
            )
        ) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Audio frame must contain exactly 960 bytes"
                )
            )
        }
    }

    func testVideoConverterMapsNeutralEnumsAndEncodingConfiguration() {
        XCTAssertEqual(
            RtcVideoConverter.convertPixelFormat(.i420).rawValue,
            ByteRTCVideoPixelFormat.I420.rawValue
        )
        XCTAssertEqual(
            RtcVideoConverter.convertPixelFormat(.nv12).rawValue,
            ByteRTCVideoPixelFormat.NV12.rawValue
        )
        XCTAssertEqual(
            RtcVideoConverter.convertRotation(.rotation270).rawValue,
            ByteRTCVideoRotation.rotation270.rawValue
        )
        XCTAssertEqual(
            RtcVideoConverter.convertCameraID(.front).rawValue,
            ByteRTCCameraID.front.rawValue
        )
        XCTAssertEqual(
            RtcVideoConverter.convertMirrorType(.back).rawValue,
            ByteRTCMirrorType.none.rawValue
        )

        let rtcConfiguration = RtcVideoConverter.makeEncoderConfiguration(
            VideoEncodingConfiguration(
                width: 1080,
                height: 1920,
                frameRate: 30,
                minimumBitrate: 500,
                maximumBitrate: 3_000
            )
        )
        XCTAssertEqual(rtcConfiguration.width, 1080)
        XCTAssertEqual(rtcConfiguration.height, 1920)
        XCTAssertEqual(rtcConfiguration.frameRate, 30)
        XCTAssertEqual(rtcConfiguration.minBitrate, 500)
        XCTAssertEqual(rtcConfiguration.maxBitrate, 3_000)
        XCTAssertEqual(
            rtcConfiguration.encoderPreference.rawValue,
            ByteRTCVideoEncoderPreference.maintainFramerate.rawValue
        )
    }

    func testVideoConverterOwnsSelectedPlaneRanges() throws {
        let format = try VideoFormat(
            width: 2,
            height: 2,
            pixelFormat: .nv12
        )
        let frame = try VideoFrame(
            format: format,
            timestampUs: 12_345,
            planes: [
                try VideoFramePlane(
                    data: Data([99, 1, 2, 3, 4, 98]),
                    stride: 2,
                    byteOffset: 1,
                    byteLength: 4
                ),
                try VideoFramePlane(
                    data: Data([97, 5, 6, 96]),
                    stride: 2,
                    byteOffset: 1,
                    byteLength: 2
                )
            ],
            rotation: .rotation90
        )
        let converted = try RtcVideoConverter.convertFrame(
            frame,
            seiData: Data("sei".utf8)
        )
        let rtcFrame = converted.value

        XCTAssertEqual(rtcFrame.bufferType.rawValue, 0)
        XCTAssertEqual(rtcFrame.pixelFormat.rawValue, 2)
        XCTAssertEqual(rtcFrame.width, 2)
        XCTAssertEqual(rtcFrame.height, 2)
        XCTAssertEqual(rtcFrame.numberOfPlanes, 2)
        XCTAssertEqual(rtcFrame.planeStrideArray?[0], 2)
        XCTAssertEqual(rtcFrame.planeStrideArray?[1], 2)
        XCTAssertEqual(rtcFrame.seiData, Data("sei".utf8))
        XCTAssertEqual(
            CMTimeConvertScale(
                rtcFrame.timestamp,
                timescale: 1_000_000,
                method: .default
            ).value,
            12_345
        )

        let firstPlane = try XCTUnwrap(rtcFrame.planeDataArray?[0])
        let secondPlane = try XCTUnwrap(rtcFrame.planeDataArray?[1])
        XCTAssertEqual(Data(bytes: firstPlane, count: 4), Data([1, 2, 3, 4]))
        XCTAssertEqual(Data(bytes: secondPlane, count: 2), Data([5, 6]))
    }

    func testVideoConverterRejectsWrongPlaneCount() throws {
        let format = try VideoFormat(
            width: 2,
            height: 2,
            pixelFormat: .i420
        )
        let frame = try VideoFrame(
            format: format,
            timestampUs: 0,
            planes: [
                try VideoFramePlane(
                    data: Data(repeating: 0, count: 4),
                    stride: 2
                )
            ]
        )

        XCTAssertThrowsError(try RtcVideoConverter.convertFrame(frame)) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Video frame requires 3 data planes"
                )
            )
        }
    }

    func testVideoFrameCacheReusesStaticPixelBufferAndUpdatesMetadata() throws {
        let format = try VideoFormat(
            width: 2,
            height: 2,
            pixelFormat: .bgra
        )
        let plane = try VideoFramePlane(
            data: Data(repeating: 7, count: 16),
            stride: 8
        )
        let bufferReuseID = UUID()
        let cache = RtcVideoFrameCache()
        let firstFrame = try VideoFrame(
            format: format,
            timestampUs: 1_000,
            planes: [plane],
            bufferReuseID: bufferReuseID
        )
        let secondFrame = try VideoFrame(
            format: format,
            timestampUs: 2_000,
            planes: [plane],
            bufferReuseID: bufferReuseID
        )

        let firstRtcFrame = try cache.frame(
            for: firstFrame,
            seiData: nil
        )
        let firstPlaneAddress = firstRtcFrame.value.planeDataArray?[0]
        let secondRtcFrame = try cache.frame(
            for: secondFrame,
            seiData: Data("task-id".utf8)
        )

        XCTAssertTrue(firstRtcFrame === secondRtcFrame)
        XCTAssertEqual(
            firstPlaneAddress,
            secondRtcFrame.value.planeDataArray?[0]
        )
        XCTAssertEqual(
            CMTimeConvertScale(
                secondRtcFrame.value.timestamp,
                timescale: 1_000_000,
                method: .default
            ).value,
            2_000
        )
        XCTAssertEqual(
            secondRtcFrame.value.seiData,
            Data("task-id".utf8)
        )
    }
}
