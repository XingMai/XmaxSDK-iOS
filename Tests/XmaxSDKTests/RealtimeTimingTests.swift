//
//  RealtimeTimingTests.swift
//  XmaxSDK
//  Repo: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import XCTest
@testable import XmaxSDK

final class RealtimeTimingTests: XCTestCase {
    override func tearDown() {
        XmaxLogger.configure(options: [])
        super.tearDown()
    }

    func testStartupHasFourSiblingStagesUnderTotalDuration() {
        XmaxLogger.configure(options: [], environment: .china)
        let state = RealtimeTiming.State(
            startedAt: 0,
            sessionStartedAt: 1000000,
            sessionFinishedAt: 151000000,
            roomJoinStartedAt: 152000000,
            roomJoinFinishedAt: 312000000,
            publicationStartedAt: 312000000,
            publicationFinishedAt: 312400000,
            signalStartedAt: 320000000,
            firstFrameAt: 1320000000,
            readyAt: 1321000000
        )

        XCTAssertEqual(RealtimeTiming.format(state), """
        实时生成启动耗时 (Realtime Generation Startup Timing)
        └─ 总耗时：1321.0 ms
           ├─ 创建会话：150.0 ms
           ├─ RTC 进房：160.0 ms
           ├─ 发布本地流：0.4 ms
           └─ 首帧到达：1000.0 ms
        """)
    }

    func testReusedConnectionDoesNotInventConnectionDurations() {
        XmaxLogger.configure(options: [], environment: .global)
        let state = RealtimeTiming.State(
            startedAt: 0,
            signalStartedAt: 1000000,
            firstFrameAt: 501000000,
            readyAt: 502000000
        )

        XCTAssertEqual(RealtimeTiming.format(state), """
        实时生成启动耗时 (Realtime Generation Startup Timing)
        └─ Total Duration: 502.0 ms
           ├─ Session Creation: —
           ├─ RTC Room Join: —
           ├─ Local Stream Publication: —
           └─ First Frame Arrival: 500.0 ms
        """)
    }

    func testFailureKeepsCompletedStagesAndMeasuresPendingStage() {
        XmaxLogger.configure(options: [], environment: .china)
        let state = RealtimeTiming.State(
            startedAt: 0,
            sessionStartedAt: 0,
            sessionFinishedAt: 100000000,
            roomJoinStartedAt: 100000000,
            roomJoinFinishedAt: 200000000,
            publicationStartedAt: 200000000,
            failureAt: 205000000
        )
        let message = RealtimeTiming.formatFailure(
            state,
            error: XmaxError(code: .rtcError, message: "publish failed")
        )

        XCTAssertTrue(message.contains("停留阶段：发布本地流"))
        XCTAssertTrue(message.contains("创建会话：100.0 ms"))
        XCTAssertTrue(message.contains("RTC 进房：100.0 ms"))
        XCTAssertTrue(message.contains("发布本地流：5.0 ms"))
        XCTAssertTrue(message.contains("首帧到达：—"))
        XCTAssertTrue(message.contains("│  ├─ 创建会话：100.0 ms"))
        XCTAssertTrue(message.contains("│  └─ 首帧到达：—"))
        XCTAssertFalse(message.contains("结果流确认"))
    }
}
