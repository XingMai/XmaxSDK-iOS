import XCTest
@testable import XmaxSDK

@MainActor
final class QualityControllerTests: XCTestCase {
    func testUplinkStatisticsRequirePublicationAndClearOnStop() async {
        let controller = QualityController(rtcManager: RtcManagingStub())
        let sample = UplinkVideoStatistics(width: 832, height: 1472, captureFrameRate: 30)
        var received: [UplinkVideoStatistics?] = []
        let cleared = expectation(description: "Clear statistics")
        controller.setUplinkVideoStatisticsListener {
            received.append($0)
            if $0 == nil { cleared.fulfill() }
        }

        controller.onUplinkVideoStatistics(sample)
        XCTAssertTrue(received.isEmpty)
        controller.setUplinkVideoStatisticsEnabled(true)
        controller.onUplinkVideoStatistics(sample)
        controller.setUplinkVideoStatisticsEnabled(false)
        controller.onUplinkVideoStatistics(sample)
        await fulfillment(of: [cleared], timeout: 1)

        XCTAssertEqual(received, [sample, nil])
    }

    func testDownlinkStatisticsOnlyAcceptCurrentResultUser() async {
        let controller = QualityController(rtcManager: RtcManagingStub())
        var received: [DownlinkVideoStatistics?] = []
        let cleared = expectation(description: "Clear result statistics")
        controller.setDownlinkVideoStatisticsListener {
            received.append($0)
            if $0 == nil { cleared.fulfill() }
        }

        let sample = DownlinkVideoStatistics(userID: "bot", width: 704, height: 1280)
        controller.onDownlinkVideoStatistics(sample)
        controller.setDownlinkVideoStatisticsUser("bot")
        controller.onDownlinkVideoStatistics(DownlinkVideoStatistics(userID: "other"))
        controller.onDownlinkVideoStatistics(sample)
        controller.setDownlinkVideoStatisticsUser(nil)
        controller.onDownlinkVideoStatistics(sample)
        await fulfillment(of: [cleared], timeout: 1)

        XCTAssertEqual(received, [sample, nil])
    }

    func testStatisticsListenerReplacementInvalidatesQueuedClear() async {
        let controller = QualityController(rtcManager: RtcManagingStub())
        var oldCallbackCount = 0
        var newCallbackCount = 0
        controller.setUplinkVideoStatisticsListener { _ in oldCallbackCount += 1 }
        controller.setUplinkVideoStatisticsEnabled(true)
        controller.setUplinkVideoStatisticsListener { _ in newCallbackCount += 1 }
        let cleared = expectation(description: "Current clear")
        controller.setDownlinkVideoStatisticsListener { _ in cleared.fulfill() }
        controller.setDownlinkVideoStatisticsUser(nil)
        await fulfillment(of: [cleared], timeout: 1)

        XCTAssertEqual(oldCallbackCount, 0)
        XCTAssertEqual(newCallbackCount, 0)
        controller.onUplinkVideoStatistics(UplinkVideoStatistics())
        XCTAssertEqual(newCallbackCount, 1)
        controller.setUplinkVideoStatisticsListener(nil)
        controller.onUplinkVideoStatistics(UplinkVideoStatistics())
        XCTAssertEqual(newCallbackCount, 1)
    }

    func testNetworkQualityMapsEveryRtcLevel() {
        let rtcManager = RtcManagingStub()
        let controller = QualityController(rtcManager: rtcManager)
        var receivedQualities: [RealtimeNetworkQuality] = []
        controller.setNetworkQualityListener { quality in
            receivedQualities.append(quality)
        }

        let levels: [RtcQualityLevel] = [
            .unknown,
            .excellent,
            .good,
            .poor,
            .bad,
            .veryBad,
            .down
        ]
        for level in levels {
            rtcManager.emitNetworkQuality(
                uplink: level,
                downlink: level
            )
        }

        XCTAssertEqual(
            receivedQualities.map(\.uplink),
            [
                .unknown,
                .excellent,
                .good,
                .poor,
                .bad,
                .veryBad,
                .down
            ]
        )
        XCTAssertEqual(
            receivedQualities.map(\.downlink),
            receivedQualities.map(\.uplink)
        )
    }

    func testPerformanceAlarmMapsLimitedStateAndSuggestedFormat() {
        let rtcManager = RtcManagingStub()
        let controller = QualityController(rtcManager: rtcManager)
        var receivedAlarm: RealtimePerformanceAlarm?
        controller.setPerformanceAlarmListener { alarm in
            receivedAlarm = alarm
        }

        rtcManager.emitPerformanceAlarm(
            limited: true,
            suggestedWidth: 540,
            suggestedHeight: 960,
            suggestedFrameRate: 15
        )

        XCTAssertEqual(
            receivedAlarm,
            RealtimePerformanceAlarm(
                status: .limited,
                suggestedVideoFormat: RealtimeVideoFormat(
                    width: 540,
                    height: 960,
                    fps: 15
                )
            )
        )
    }

    func testPerformanceAlarmMapsRecoveryAndRejectsInvalidSuggestion() {
        let rtcManager = RtcManagingStub()
        let controller = QualityController(rtcManager: rtcManager)
        var receivedAlarm: RealtimePerformanceAlarm?
        controller.setPerformanceAlarmListener { alarm in
            receivedAlarm = alarm
        }

        rtcManager.emitPerformanceAlarm(
            limited: false,
            suggestedWidth: 0,
            suggestedHeight: 960,
            suggestedFrameRate: 15
        )

        XCTAssertEqual(receivedAlarm?.status, .recovered)
        XCTAssertNil(receivedAlarm?.suggestedVideoFormat)
    }

    func testClearedListenersIgnoreLaterEvents() {
        let rtcManager = RtcManagingStub()
        let controller = QualityController(rtcManager: rtcManager)
        var networkCallbackCount = 0
        var performanceCallbackCount = 0
        controller.setNetworkQualityListener { _ in
            networkCallbackCount += 1
        }
        controller.setPerformanceAlarmListener { _ in
            performanceCallbackCount += 1
        }

        controller.setNetworkQualityListener(nil)
        controller.setPerformanceAlarmListener(nil)
        rtcManager.emitNetworkQuality(
            uplink: .good,
            downlink: .poor
        )
        rtcManager.emitPerformanceAlarm(
            limited: true,
            suggestedWidth: 540,
            suggestedHeight: 960,
            suggestedFrameRate: 15
        )

        XCTAssertEqual(networkCallbackCount, 0)
        XCTAssertEqual(performanceCallbackCount, 0)
    }
}
