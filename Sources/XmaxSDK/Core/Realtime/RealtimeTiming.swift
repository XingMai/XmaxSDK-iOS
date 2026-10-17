import Foundation

/// 记录实时生成启动链路各阶段耗时。
final class RealtimeTiming: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var state = State()

    func begin() {
        lock.withLock {
            state = State(startedAt: Self.now)
        }
    }

    func beginSessionCreation() {
        lock.withLock { state.sessionStartedAt = Self.now }
    }

    func finishSessionCreation() {
        lock.withLock { state.sessionFinishedAt = Self.now }
    }

    func beginRoomJoin() {
        lock.withLock { state.roomJoinStartedAt = Self.now }
    }

    func finishRoomJoin() {
        lock.withLock { state.roomJoinFinishedAt = Self.now }
    }

    func beginLocalPublication() {
        lock.withLock { state.publicationStartedAt = Self.now }
    }

    func finishLocalPublication() {
        lock.withLock { state.publicationFinishedAt = Self.now }
    }

    func beginSignal(taskID: String) {
        lock.withLock {
            state.taskID = taskID
            state.signalStartedAt = Self.now
            state.firstFrameAt = nil
        }
    }

    /// 生成请求发出后，首个结果帧已经可以显示。
    func finishFirstFrame(taskID: String) {
        lock.withLock {
            guard state.taskID == taskID else { return }
            state.firstFrameAt = Self.now
        }
    }

    func finish(taskID: String) {
        let snapshot = lock.withLock { () -> State? in
            guard state.taskID == taskID,
                  state.startedAt != nil else {
                return nil
            }
            state.readyAt = Self.now
            return state
        }
        guard let snapshot else { return }

        XmaxLogger.realtime.info(
            message: Self.format(snapshot),
            option: .performance
        )
    }

    func finishFailure(_ error: any Error) {
        let xmaxError = XmaxError.from(error)
        guard xmaxError.code != .cancelled else { return }

        let snapshot = lock.withLock { () -> State? in
            guard state.startedAt != nil else { return nil }
            state.failureAt = Self.now
            return state
        }
        guard let snapshot else { return }

        XmaxLogger.realtime.info(
            message: Self.formatFailure(snapshot, error: xmaxError),
            option: .performance
        )
    }
}

extension RealtimeTiming {
    struct State {
        var startedAt: UInt64?
        var sessionStartedAt: UInt64?
        var sessionFinishedAt: UInt64?
        var roomJoinStartedAt: UInt64?
        var roomJoinFinishedAt: UInt64?
        var publicationStartedAt: UInt64?
        var publicationFinishedAt: UInt64?
        var signalStartedAt: UInt64?
        var firstFrameAt: UInt64?
        var readyAt: UInt64?
        var failureAt: UInt64?
        var taskID: String?
    }

    static func format(_ state: State) -> String {
        guard let startedAt = state.startedAt,
              state.firstFrameAt != nil,
              let readyAt = state.readyAt else {
            return "实时生成启动耗时不可用 " +
                "(Realtime Generation Startup Timing Unavailable)"
        }

        let lines = [
            "实时生成启动耗时 (Realtime Generation Startup Timing)",
            "└─ \(XmaxLogger.localized("总耗时：", "Total Duration: "))\(duration(startedAt, readyAt))"
        ] + stageDetails(state)
        return lines.joined(separator: "\n")
    }

    static func formatFailure(_ state: State, error: XmaxError) -> String {
        guard let startedAt = state.startedAt,
              let failureAt = state.failureAt else {
            return "实时生成启动失败耗时不可用 " +
                "(Realtime Generation Startup Failure Timing Unavailable)"
        }

        let lines = [
            "实时生成启动未完成耗时 (Incomplete Realtime Generation Startup Timing)",
            "├─ \(XmaxLogger.localized("已耗时：", "Elapsed Time: "))\(duration(startedAt, failureAt))"
        ] + stageDetails(state, failureAt: failureAt) + [
            "├─ \(XmaxLogger.localized("停留阶段：", "Current Stage: "))\(pendingStage(state))",
            "└─ \(XmaxLogger.localized("失败原因：", "Failure Reason: "))\(error.localizedDescription)"
        ]
        return lines.joined(separator: "\n")
    }
}

private extension RealtimeTiming {
    static var now: UInt64 { DispatchTime.now().uptimeNanoseconds }

    static func stageDetails(_ state: State, failureAt: UInt64? = nil) -> [String] {
        let stages: [(String, UInt64?, UInt64?)] = [
            (XmaxLogger.localized("创建会话：", "Session Creation: "),
             state.sessionStartedAt, state.sessionFinishedAt),
            (XmaxLogger.localized("RTC 进房：", "RTC Room Join: "),
             state.roomJoinStartedAt, state.roomJoinFinishedAt),
            (XmaxLogger.localized("发布本地流：", "Local Stream Publication: "),
             state.publicationStartedAt, state.publicationFinishedAt),
            (XmaxLogger.localized("首帧到达：", "First Frame Arrival: "),
             state.signalStartedAt, state.firstFrameAt)
        ]

        return stages.enumerated().map { index, stage in
            let indent = failureAt == nil ? "   " : "│  "
            let branch = index == stages.count - 1 ? "└─" : "├─"
            return "\(indent)\(branch) \(stage.0)\(duration(stage.1, stage.2 ?? failureAt))"
        }
    }

    static func pendingStage(_ state: State) -> String {
        if state.firstFrameAt != nil {
            return XmaxLogger.localized("首帧已就绪，正在完成启动", "First Frame Ready, Completing Startup")
        }
        if state.signalStartedAt != nil {
            return XmaxLogger.localized("等待首帧到达", "Waiting for First Frame")
        }
        if state.publicationFinishedAt != nil {
            return XmaxLogger.localized("准备生成", "Preparing Generation")
        }
        if state.publicationStartedAt != nil {
            return XmaxLogger.localized("发布本地流", "Publishing Local Stream")
        }
        if state.roomJoinFinishedAt != nil {
            return XmaxLogger.localized("准备发布本地流", "Preparing Local Stream Publication")
        }
        if state.roomJoinStartedAt != nil {
            return XmaxLogger.localized("RTC 进房", "Joining RTC Room")
        }
        if state.sessionFinishedAt != nil {
            return XmaxLogger.localized("RTC 连接准备", "RTC Connection Setup")
        }
        if state.sessionStartedAt != nil {
            return XmaxLogger.localized("创建会话", "Creating Session")
        }
        return XmaxLogger.localized("调用与本地准备", "Invocation and Local Preparation")
    }

    static func duration(_ start: UInt64?, _ end: UInt64?) -> String {
        guard let start, let end, end >= start else { return "—" }
        return String(format: "%.1f ms", Double(end - start) / 1000000)
    }
}
