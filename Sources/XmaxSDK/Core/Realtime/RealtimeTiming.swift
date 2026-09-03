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

    func beginConnection() {
        lock.withLock {
            state.connectionStartedAt = Self.now
        }
    }

    func beginSessionCreation() {
        lock.withLock {
            state.sessionStartedAt = Self.now
        }
    }

    func finishSessionCreation() {
        lock.withLock {
            state.sessionFinishedAt = Self.now
        }
    }

    func beginRoomJoin() {
        lock.withLock {
            state.roomJoinStartedAt = Self.now
        }
    }

    func finishRoomJoin() {
        lock.withLock {
            state.roomJoinFinishedAt = Self.now
        }
    }

    func finishConnection() {
        lock.withLock {
            state.connectionFinishedAt = Self.now
        }
    }

    func beginSignal(taskID: String) {
        lock.withLock {
            state.taskID = taskID
            state.signalStartedAt = Self.now
            state.signalFinishedAt = nil
            state.seiMatchedAt = nil
        }
    }

    func finishSignal(taskID: String) {
        lock.withLock {
            guard state.taskID == taskID else { return }
            state.signalFinishedAt = Self.now
        }
    }

    func matchSEI(taskID: String) {
        lock.withLock {
            guard state.taskID == taskID else { return }
            state.seiMatchedAt = Self.now
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

        XmaxLogger.info(
            category: "Timing",
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

        XmaxLogger.info(
            category: "Timing",
            message: Self.formatFailure(snapshot, error: xmaxError),
            option: .performance
        )
    }
}

private extension RealtimeTiming {
    struct State {
        var startedAt: UInt64?
        var connectionStartedAt: UInt64?
        var sessionStartedAt: UInt64?
        var sessionFinishedAt: UInt64?
        var roomJoinStartedAt: UInt64?
        var roomJoinFinishedAt: UInt64?
        var connectionFinishedAt: UInt64?
        var signalStartedAt: UInt64?
        var signalFinishedAt: UInt64?
        var seiMatchedAt: UInt64?
        var readyAt: UInt64?
        var failureAt: UInt64?
        var taskID: String?
    }

    static var now: UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static let minimumDetailMilliseconds = 1.0

    static func format(_ state: State) -> String {
        guard let startedAt = state.startedAt,
              let signalStartedAt = state.signalStartedAt,
              let seiMatchedAt = state.seiMatchedAt,
              let readyAt = state.readyAt else {
            return "实时生成启动耗时不可用 " +
                "(Realtime Generation Startup Timing Unavailable)"
        }

        var lines = [
            "实时生成启动耗时 (Realtime Generation Startup Timing)",
            "├─ 总耗时：\(duration(startedAt, readyAt))"
        ]

        if let connectionStartedAt = state.connectionStartedAt,
           let connectionFinishedAt = state.connectionFinishedAt {
            appendDetail(
                "调用与本地准备",
                milliseconds(startedAt, connectionStartedAt),
                to: &lines
            )
            let connectionDuration = milliseconds(
                connectionStartedAt,
                connectionFinishedAt
            ) ?? 0
            lines.append(
                "├─ 实时连接：\(format(connectionDuration))"
            )
            let sessionDuration = milliseconds(
                state.sessionStartedAt,
                state.sessionFinishedAt
            )
            let roomJoinDuration = milliseconds(
                state.roomJoinStartedAt,
                state.roomJoinFinishedAt
            )
            let knownConnectionDuration =
                (sessionDuration ?? 0) + (roomJoinDuration ?? 0)
            let remainingConnectionDuration = max(
                0,
                connectionDuration - knownConnectionDuration
            )
            appendConnectionDetails(
                [
                    ("服务端会话创建", sessionDuration),
                    ("RTC 房间连接", roomJoinDuration),
                    ("媒体发布与连接准备", remainingConnectionDuration)
                ],
                to: &lines
            )
            appendDetail(
                "连接后生成准备",
                milliseconds(connectionFinishedAt, signalStartedAt),
                to: &lines
            )
        } else {
            appendDetail(
                "生成前准备",
                milliseconds(startedAt, signalStartedAt),
                to: &lines
            )
        }

        lines.append(
            "├─ 等待生成结果流确认：" +
                duration(signalStartedAt, seiMatchedAt)
        )
        if let signalDuration = milliseconds(
            signalStartedAt,
            state.signalFinishedAt
        ), signalDuration >= minimumDetailMilliseconds {
            lines.append(
                "│  └─ 发送生成请求：\(format(signalDuration))"
            )
        }
        lines.append(
            "└─ 结果流确认到首帧就绪：" +
                duration(seiMatchedAt, readyAt)
        )
        return lines.joined(separator: "\n")
    }

    static func formatFailure(
        _ state: State,
        error: XmaxError
    ) -> String {
        guard let startedAt = state.startedAt,
              let failureAt = state.failureAt else {
            return "实时生成启动失败耗时不可用 " +
                "(Realtime Generation Startup Failure Timing Unavailable)"
        }

        var lines = [
            "实时生成启动未完成耗时 " +
                "(Incomplete Realtime Generation Startup Timing)",
            "├─ 已耗时：\(duration(startedAt, failureAt))",
            "├─ 停留阶段：\(pendingStage(state))"
        ]
        if let sessionStartedAt = state.sessionStartedAt {
            appendDetail(
                "服务端会话创建",
                milliseconds(
                    sessionStartedAt,
                    state.sessionFinishedAt ?? failureAt
                ),
                to: &lines
            )
        }
        if let roomJoinStartedAt = state.roomJoinStartedAt {
            appendDetail(
                "RTC 房间连接",
                milliseconds(
                    roomJoinStartedAt,
                    state.roomJoinFinishedAt ?? failureAt
                ),
                to: &lines
            )
        }
        if let connectionStartedAt = state.connectionStartedAt {
            appendDetail(
                "实时连接",
                milliseconds(
                    connectionStartedAt,
                    state.connectionFinishedAt ?? failureAt
                ),
                to: &lines
            )
        }
        if let signalStartedAt = state.signalStartedAt {
            appendDetail(
                "等待生成结果流确认",
                milliseconds(
                    signalStartedAt,
                    state.seiMatchedAt ?? failureAt
                ),
                to: &lines
            )
        }
        if let seiMatchedAt = state.seiMatchedAt {
            appendDetail(
                "结果流确认后等待首帧",
                milliseconds(seiMatchedAt, failureAt),
                to: &lines
            )
        }
        lines.append(
            "└─ 失败原因：\(error.localizedDescription)"
        )
        return lines.joined(separator: "\n")
    }

    static func pendingStage(_ state: State) -> String {
        if state.seiMatchedAt != nil {
            return "结果流已确认，正在等待首帧"
        }
        if state.signalStartedAt != nil {
            return "正在等待生成结果流确认"
        }
        if state.connectionFinishedAt != nil {
            return "连接完成后准备生成"
        }
        if state.roomJoinStartedAt != nil,
           state.roomJoinFinishedAt == nil {
            return "正在连接 RTC 房间"
        }
        if state.sessionFinishedAt != nil {
            return "RTC 连接准备"
        }
        if state.sessionStartedAt != nil {
            return "服务端会话创建"
        }
        return "调用与本地准备"
    }

    static func appendDetail(
        _ title: String,
        _ milliseconds: Double?,
        to lines: inout [String]
    ) {
        guard let milliseconds,
              milliseconds >= minimumDetailMilliseconds else {
            return
        }
        lines.append("├─ \(title)：\(format(milliseconds))")
    }

    static func appendConnectionDetails(
        _ details: [(String, Double?)],
        to lines: inout [String]
    ) {
        let visibleDetails = details.compactMap {
            detail -> (String, Double)? in
            guard let milliseconds = detail.1,
                  milliseconds >= minimumDetailMilliseconds else {
                return nil
            }
            return (detail.0, milliseconds)
        }
        for (index, detail) in visibleDetails.enumerated() {
            let branch = index == visibleDetails.count - 1
                ? "│  └─"
                : "│  ├─"
            lines.append(
                "\(branch) \(detail.0)：\(format(detail.1))"
            )
        }
    }

    static func duration(_ start: UInt64, _ end: UInt64) -> String {
        format(milliseconds(start, end) ?? 0)
    }

    static func milliseconds(
        _ start: UInt64?,
        _ end: UInt64?
    ) -> Double? {
        guard let start, let end, end >= start else { return nil }
        return Double(end - start) / 1_000_000
    }

    static func format(_ milliseconds: Double) -> String {
        String(format: "%.1f ms", milliseconds)
    }
}
