//
//  RealtimeTiming.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Records the durations of realtime generation startup stages.
final class RealtimeTiming: @unchecked Sendable {

    /// The lock protecting stage timestamps across threads.
    private let lock = NSLock()

    /// The timing record for the current generation startup.
    private var state = State()

    /// Begins a new startup measurement.
    func begin() {
        lock.withLock {
            state = State(startedAt: Self.now)
        }
    }

    /// Records the start of server session creation.
    func beginSessionCreation() {
        lock.withLock {
            state.sessionStartedAt = Self.now
        }
    }

    /// Records the completion of server session creation.
    func finishSessionCreation() {
        lock.withLock {
            state.sessionFinishedAt = Self.now
        }
    }

    /// Records the start of RTC room join.
    func beginRoomJoin() {
        lock.withLock {
            state.roomJoinStartedAt = Self.now
        }
    }

    /// Records the completion of RTC room join.
    func finishRoomJoin() {
        lock.withLock {
            state.roomJoinFinishedAt = Self.now
        }
    }

    /// Records the start of local stream publication.
    func beginLocalPublication() {
        lock.withLock {
            state.publicationStartedAt = Self.now
        }
    }

    /// Records the completion of local stream publication.
    func finishLocalPublication() {
        lock.withLock {
            state.publicationFinishedAt = Self.now
        }
    }

    /// Records when generation signaling begins for a task.
    ///
    /// - Parameter taskID: The identifier of the generation task being measured.
    func beginSignal(
        taskID: String
    ) {
        lock.withLock {
            state.taskID = taskID
            state.signalStartedAt = Self.now
            state.firstFrameAt = nil
        }
    }

    /// Records when the current task's first remote frame is ready for display.
    ///
    /// - Parameter taskID: The frame's task identifier. Notifications for other tasks are ignored.
    func finishFirstFrame(
        taskID: String
    ) {
        lock.withLock {
            guard state.taskID == taskID else {
                return
            }
            state.firstFrameAt = Self.now
        }
    }

    /// Logs the completed startup measurement when performance logging is enabled.
    ///
    /// - Parameter taskID: The completed task identifier. Notifications for other tasks are
    ///   ignored.
    func finish(
        taskID: String
    ) {
        let snapshot = lock.withLock { () -> State? in
            guard state.taskID == taskID,
                state.startedAt != nil
            else {
                return nil
            }
            state.readyAt = Self.now
            return state
        }
        guard let snapshot else {
            return
        }

        XmaxLogger.realtime.info(
            message: Self.format(snapshot),
            option: .performance
        )
    }

    /// Logs an incomplete startup measurement when performance logging is enabled.
    ///
    /// Cancellation is not recorded as a failure.
    ///
    /// - Parameter error: The error that prevented startup from completing.
    func finishFailure(
        _ error: any Error
    ) {
        let xmaxError = XmaxError.from(error)
        guard xmaxError.code != .cancelled else {
            return
        }

        let snapshot = lock.withLock { () -> State? in
            guard state.startedAt != nil else {
                return nil
            }
            state.failureAt = Self.now
            return state
        }
        guard let snapshot else {
            return
        }

        XmaxLogger.realtime.info(
            message: Self.formatFailure(
                snapshot,
                error: xmaxError
            ),
            option: .performance
        )
    }
}

extension RealtimeTiming {

    /// The stage timestamps and task identifier for one startup, using monotonic nanoseconds.
    struct State {

        /// The start of the generation startup request.
        var startedAt: UInt64?

        /// The start of server session creation.
        var sessionStartedAt: UInt64?

        /// The completion of server session creation.
        var sessionFinishedAt: UInt64?

        /// The start of RTC room join.
        var roomJoinStartedAt: UInt64?

        /// The completion of RTC room join.
        var roomJoinFinishedAt: UInt64?

        /// The start of local stream publication.
        var publicationStartedAt: UInt64?

        /// The completion of local stream publication.
        var publicationFinishedAt: UInt64?

        /// The start of generation signaling.
        var signalStartedAt: UInt64?

        /// The time the first result frame becomes ready.
        var firstFrameAt: UInt64?

        /// The completion of generation startup.
        var readyAt: UInt64?

        /// The time startup fails.
        var failureAt: UInt64?

        /// The generation task associated with this timing record.
        var taskID: String?
    }

    /// Formats the timing summary for a completed startup.
    ///
    /// - Parameter state: The recorded startup and stage timestamps.
    ///
    /// - Returns: A timing summary, or an unavailable message if required timestamps are missing.
    static func format(
        _ state: State
    ) -> String {
        guard let startedAt = state.startedAt,
            state.firstFrameAt != nil,
            let readyAt = state.readyAt
        else {
            return "实时生成启动耗时不可用 " + "(Realtime Generation Startup Timing Unavailable)"
        }

        let lines =
            [
                "实时生成启动耗时 (Realtime Generation Startup Timing)",
                "└─ \(XmaxLogger.localized("总耗时：", "Total Duration: "))\(duration(startedAt, readyAt))"
            ] + stageDetails(state)
        return lines.joined(separator: "\n")
    }

    /// Formats the timing summary for an incomplete startup.
    ///
    /// - Parameters:
    ///   - state: The failure timestamp and available stage timestamps.
    ///   - error: The SDK error that prevented startup from completing.
    ///
    /// - Returns: The elapsed time, stage durations, current stage, and failure reason.
    static func formatFailure(
        _ state: State,
        error: XmaxError
    ) -> String {
        guard let startedAt = state.startedAt,
            let failureAt = state.failureAt
        else {
            return "实时生成启动失败耗时不可用 " + "(Realtime Generation Startup Failure Timing Unavailable)"
        }

        let lines =
            [
                "实时生成启动未完成耗时 (Incomplete Realtime Generation Startup Timing)",
                "├─ \(XmaxLogger.localized("已耗时：", "Elapsed Time: "))\(duration(startedAt, failureAt))"
            ]
            + stageDetails(
                state,
                failureAt: failureAt
            ) + [
                "├─ \(XmaxLogger.localized("停留阶段：", "Current Stage: "))\(pendingStage(state))",
                "└─ \(XmaxLogger.localized("失败原因：", "Failure Reason: "))\(error.localizedDescription)"
            ]
        return lines.joined(separator: "\n")
    }
}

private extension RealtimeTiming {

    /// The current monotonic clock time, in nanoseconds.
    static var now: UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    /// Formats the startup stage durations.
    ///
    /// - Parameters:
    ///   - state: The recorded startup timestamps.
    ///   - failureAt: The failure timestamp used as the end of unfinished stages, if supplied.
    ///
    /// - Returns: The stage detail lines for the timing summary.
    static func stageDetails(
        _ state: State,
        failureAt: UInt64? = nil
    ) -> [String] {
        let stages: [(String, UInt64?, UInt64?)] = [
            (
                XmaxLogger.localized(
                    "创建会话：",
                    "Session Creation: "
                ),
                state.sessionStartedAt, state.sessionFinishedAt
            ),
            (
                XmaxLogger.localized(
                    "RTC 进房：",
                    "RTC Room Join: "
                ),
                state.roomJoinStartedAt, state.roomJoinFinishedAt
            ),
            (
                XmaxLogger.localized(
                    "发布本地流：",
                    "Local Stream Publication: "
                ),
                state.publicationStartedAt, state.publicationFinishedAt
            ),
            (
                XmaxLogger.localized(
                    "首帧到达：",
                    "First Frame Arrival: "
                ),
                state.signalStartedAt, state.firstFrameAt
            )
        ]

        return stages.enumerated().map { index, stage in
            let indent = failureAt == nil ? "   " : "│  "
            let branch = index == stages.count - 1 ? "└─" : "├─"
            return "\(indent)\(branch) \(stage.0)\(duration(stage.1, stage.2 ?? failureAt))"
        }
    }

    /// Determines the current startup stage from recorded timestamps.
    ///
    /// - Parameter state: The recorded startup timestamps.
    ///
    /// - Returns: The stage name in the current log language.
    static func pendingStage(
        _ state: State
    ) -> String {
        if state.firstFrameAt != nil {
            return XmaxLogger.localized(
                "首帧已就绪，正在完成启动",
                "First Frame Ready, Completing Startup"
            )
        }
        if state.signalStartedAt != nil {
            return XmaxLogger.localized(
                "等待首帧到达",
                "Waiting for First Frame"
            )
        }
        if state.publicationFinishedAt != nil {
            return XmaxLogger.localized(
                "准备生成",
                "Preparing Generation"
            )
        }
        if state.publicationStartedAt != nil {
            return XmaxLogger.localized(
                "发布本地流",
                "Publishing Local Stream"
            )
        }
        if state.roomJoinFinishedAt != nil {
            return XmaxLogger.localized(
                "准备发布本地流",
                "Preparing Local Stream Publication"
            )
        }
        if state.roomJoinStartedAt != nil {
            return XmaxLogger.localized(
                "RTC 进房",
                "Joining RTC Room"
            )
        }
        if state.sessionFinishedAt != nil {
            return XmaxLogger.localized(
                "RTC 连接准备",
                "RTC Connection Setup"
            )
        }
        if state.sessionStartedAt != nil {
            return XmaxLogger.localized(
                "创建会话",
                "Creating Session"
            )
        }
        return XmaxLogger.localized(
            "调用与本地准备",
            "Invocation and Local Preparation"
        )
    }

    /// Formats the interval between two nanosecond timestamps in milliseconds.
    ///
    /// - Parameters:
    ///   - start: The stage's start timestamp.
    ///   - end: The stage's end timestamp.
    ///
    /// - Returns: Milliseconds with one decimal place, or `—` if timestamps are missing or
    ///   reversed.
    static func duration(
        _ start: UInt64?,
        _ end: UInt64?
    ) -> String {
        guard let start, let end, end >= start else {
            return "—"
        }
        return String(
            format: "%.1f ms",
            Double(end - start) / 1000000
        )
    }
}
