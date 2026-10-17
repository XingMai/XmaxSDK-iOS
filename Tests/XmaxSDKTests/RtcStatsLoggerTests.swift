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
        XCTAssertTrue(message.contains("0%"))
        XCTAssertFalse(message.contains("—"))
    }

    func testDownlinkReportsMediaDelay() {
        let message = RtcStatsLogger.downlinkVideoStatisticsMessage(
            DownlinkVideoStatistics(userID: "bot", endToEndDelayMs: 85)
        )
        XCTAssertTrue(message.contains("85 ms"))
        XCTAssertFalse(message.contains("Stall Duration"))
    }
}
