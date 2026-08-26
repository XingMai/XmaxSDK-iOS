import XCTest
@testable import XmaxSDK

@MainActor
final class QualityControllerTests: XCTestCase {
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
