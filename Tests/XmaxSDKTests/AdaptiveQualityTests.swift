//
//  AdaptiveQualityTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import XCTest
@testable import XmaxSDK

final class AdaptiveQualityTests: XCTestCase {
    private let baseline = RealtimeVideoFormat(width: 1024, height: 1920, fps: 30)

    func testTiersAlwaysDeriveFromMediaBaseline() {
        let expected = [(1024, 1920, 30), (816, 1530, 24), (656, 1230, 24), (512, 960, 20), (512, 960, 16)]
        for (index, value) in expected.enumerated() {
            let format = QualityVideoFormat.resolve(baseline, level: index + 1, downlink: false)
            XCTAssertEqual(format.width, value.0)
            XCTAssertEqual(format.height, value.1)
            XCTAssertEqual(format.fps, value.2)
            XCTAssertEqual(format.width * baseline.height, format.height * baseline.width)
        }
        XCTAssertEqual(QualityVideoFormat.resolve(baseline, level: 1, downlink: false), baseline)
    }

    func testSmallInputsAreNotUpscaledAndFrameRateIsOnlyACeiling() {
        let small = RealtimeVideoFormat(width: 160, height: 120, fps: 12)
        for level in 1...5 {
            let format = QualityVideoFormat.resolve(small, level: level, downlink: false)
            XCTAssertEqual(format.size, small.size)
            XCTAssertEqual(format.fps, 12)
        }
    }

    func testExplicitUplinkBitratesAreNotAppliedToDownlink() {
        let custom = RealtimeVideoFormat(width: 1024, height: 1920, fps: 30, minimumBitrate: 1500, maximumBitrate: 3000, encoderPreference: .maintainQuality)
        let up = QualityVideoFormat.resolve(custom, level: 3, downlink: false)
        let down = QualityVideoFormat.resolve(custom, level: 3, downlink: true)
        XCTAssertEqual(up.minimumBitrate, 1500)
        XCTAssertEqual(up.maximumBitrate, 3000)
        XCTAssertEqual(up.encoderPreference, .maintainQuality)
        XCTAssertNil(down.minimumBitrate)
        XCTAssertNil(down.maximumBitrate)
        XCTAssertEqual(down.fps, 24)
    }

    func testThreePoorSamplesDowngradeOnlyAfterSuccessfulCommit() {
        var direction = QualityDirection(baseline: baseline, level: 2, downlink: false)
        XCTAssertNil(direction.observe(.bad, sampledAt: 1, now: 1))
        XCTAssertNil(direction.observe(.veryBad, sampledAt: 2, now: 2))
        XCTAssertEqual(direction.observe(.bad, sampledAt: 3, now: 3), 3)
        XCTAssertEqual(direction.level, 2)
        direction.complete(level: 3, success: false, now: 3)
        XCTAssertEqual(direction.level, 2)
        XCTAssertNil(direction.observe(.bad, sampledAt: 4, now: 4))
        direction.complete(level: 3, success: true, now: 5)
        XCTAssertEqual(direction.level, 3)
    }

    func testFailedUpgradeProbePreventsImmediateOscillation() {
        var direction = QualityDirection(baseline: baseline, level: 3, downlink: false)
        for time in 1...4 { XCTAssertNil(direction.observe(.good, sampledAt: Double(time), now: Double(time))) }
        XCTAssertEqual(direction.observe(.good, sampledAt: 5, now: 5), 2)
        direction.complete(level: 2, success: true, now: 5)
        for time in 9...10 { XCTAssertNil(direction.observe(.bad, sampledAt: Double(time), now: Double(time))) }
        XCTAssertEqual(direction.observe(.bad, sampledAt: 11, now: 11), 3)
        direction.complete(level: 3, success: true, now: 11)
        for time in 15...70 { XCTAssertNil(direction.observe(.good, sampledAt: Double(time), now: Double(time))) }
        XCTAssertEqual(direction.observe(.good, sampledAt: 71, now: 71), 2)
    }

    func testUnknownStaleAndNonMonotonicSamplesDoNotTriggerChanges() {
        var direction = QualityDirection(baseline: baseline, level: 2, downlink: true)
        XCTAssertNil(direction.observe(.bad, sampledAt: 1, now: 10))
        XCTAssertNil(direction.observe(.bad, sampledAt: 11, now: 11))
        XCTAssertNil(direction.observe(.bad, sampledAt: 11, now: 11))
        XCTAssertNil(direction.observe(.unknown, sampledAt: 12, now: 12))
        XCTAssertNil(direction.observe(.bad, sampledAt: 13, now: 13))
        XCTAssertNil(direction.observe(.bad, sampledAt: 20, now: 20))
        XCTAssertNil(direction.observe(.bad, sampledAt: 21, now: 21))
        XCTAssertEqual(direction.observe(.bad, sampledAt: 22, now: 22), 3)
    }

    func testDownlinkSkipsIdenticalLastTierAndDirectionsStayIndependent() {
        var down = QualityDirection(baseline: baseline, level: 4, downlink: true)
        var up = QualityDirection(baseline: baseline, level: 4, downlink: false)
        for time in 1...3 {
            XCTAssertNil(down.observe(.bad, sampledAt: Double(time), now: Double(time)))
            let candidate = up.observe(.bad, sampledAt: Double(time), now: Double(time))
            XCTAssertEqual(candidate, time == 3 ? 5 : nil)
        }
    }

    func testHistoryExpiresAndSeparatesModelsAndDirections() throws {
        let name = "xmax-quality-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let history = QualityHistory(model: "model-a", defaults: defaults)
        XCTAssertEqual(history.read(downlink: true, now: 100), 2)
        history.write(level: 4, downlink: true, now: 100)
        XCTAssertEqual(history.read(downlink: true, now: 200), 4)
        XCTAssertEqual(history.read(downlink: false, now: 200), 2)
        XCTAssertEqual(QualityHistory(model: "model-b", defaults: defaults).read(downlink: true, now: 200), 2)
        XCTAssertEqual(history.read(downlink: true, now: 99), 2)
        XCTAssertEqual(history.read(downlink: true, now: 3700), 2)
    }

    func testInternalSamplingDoesNotReplacePublicNetworkListener() async {
        let rtc = RtcManagingStub()
        let controller = QualityController(rtcManager: rtc)
        let internalEvent = expectation(description: "adaptive listener")
        let publicEvent = expectation(description: "public listener")
        controller.setAdaptiveQualityListener { _, _ in internalEvent.fulfill() }
        controller.setNetworkQualityListener { _ in publicEvent.fulfill() }
        await controller.onNetworkQuality(uplink: .good, downlink: .bad)
        await fulfillment(of: [internalEvent, publicEvent], timeout: 1)
        controller.resetQuality()
        XCTAssertNil(controller.qualityConfiguration)
    }
}
