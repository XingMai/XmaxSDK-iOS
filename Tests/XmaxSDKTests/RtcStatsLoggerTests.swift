import XCTest
@testable import XmaxSDK

final class RtcStatsLoggerTests: XCTestCase {
    func testUnavailableStatisticsUsePlaceholders() {
        let uplink = RtcStatsLogger.uplinkVideoStatisticsMessage(UplinkVideoStatistics())
        let downlink = RtcStatsLogger.downlinkVideoStatisticsMessage(
            DownlinkVideoStatistics(userID: "private-bot")
        )
        XCTAssertTrue(uplink.contains("Video Uplink Statistics"))
        XCTAssertTrue(downlink.contains("Video Downlink Statistics"))
        XCTAssertEqual(uplink.filter { $0 == "—" }.count, 6)
        XCTAssertEqual(downlink.filter { $0 == "—" }.count, 6)
        XCTAssertFalse(downlink.contains("private-bot"))
    }

    func testZeroMeasurementsAreNotMissingValues() {
        let message = RtcStatsLogger.uplinkVideoStatisticsMessage(
            UplinkVideoStatistics(
                width: 1024, height: 1920, captureFrameRate: 30,
                encodeFrameRate: 0, sendFrameRate: 0, bitrateKbps: 0, packetLossPercent: 0
            )
        )
        XCTAssertTrue(message.contains("1024 × 1920"))
        XCTAssertTrue(message.contains("30 fps"))
        XCTAssertTrue(message.contains("0 fps"))
        XCTAssertTrue(message.contains("0 kbps"))
        XCTAssertTrue(message.contains("0 %"))
        XCTAssertFalse(message.contains("—"))
    }

    func testDownlinkReportsMediaDelay() {
        let message = RtcStatsLogger.downlinkVideoStatisticsMessage(
            DownlinkVideoStatistics(userID: "bot", endToEndDelayMs: 85)
        )
        XCTAssertTrue(message.contains("85 ms"))
        XCTAssertFalse(message.contains("Stall Duration"))
    }

    func testUplinkFieldOrderAndUnitsMatchAndroid() {
        XmaxLogger.configure(options: [], environment: .china)
        defer { XmaxLogger.configure(options: []) }
        let statistics = UplinkVideoStatistics(
            width: 1024, height: 1920, captureFrameRate: 30,
            encodeFrameRate: 27, sendFrameRate: 24, bitrateKbps: 6293, packetLossPercent: 2
        )
        XCTAssertEqual(RtcStatsLogger.uplinkVideoStatisticsMessage(statistics), """
        视频上行统计 (Video Uplink Statistics)
        ├─ 分辨率：1024 × 1920
        ├─ 发送码率：6293 kbps
        ├─ 采集帧率：30 fps
        ├─ 编码帧率：27 fps
        ├─ 发送帧率：24 fps
        └─ 视频丢包率：2 %
        """)
    }

    func testEnglishDownlinkDistinguishesZeroAndUnavailableLikeAndroid() {
        XmaxLogger.configure(options: [], environment: .global)
        defer { XmaxLogger.configure(options: []) }
        let statistics = DownlinkVideoStatistics(
            userID: "bot", width: 1920, decodeFrameRate: 26,
            renderFrameRate: 0, bitrateKbps: 0, packetLossPercent: 0
        )
        XCTAssertEqual(RtcStatsLogger.downlinkVideoStatisticsMessage(statistics), """
        视频下行统计 (Video Downlink Statistics)
        ├─ Resolution: —
        ├─ Receive Bitrate: 0 kbps
        ├─ Decode Frame Rate: 26 fps
        ├─ Render Frame Rate: 0 fps
        ├─ Video Packet Loss: 0 %
        └─ End-to-End Delay: —
        """)
    }
}
