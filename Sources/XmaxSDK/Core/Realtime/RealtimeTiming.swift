//
//  RealtimeTiming.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 记录实时生成启动链路各阶段耗时。
final class RealtimeTiming: @unchecked Sendable {

    // 并发控制
    private let lock = NSLock()


    // 启动耗时记录
    private var state = State()

    /// 开始一次启动耗时记录，并清空上次的阶段时间。
    func begin() {
        lock.withLock {
            state = State(startedAt: Self.now)
        }
    }

    /// 记录服务端会话创建的开始时间。
    func beginSessionCreation() {
        lock.withLock { state.sessionStartedAt = Self.now }
    }

    /// 记录服务端会话创建的完成时间。
    func finishSessionCreation() {
        lock.withLock { state.sessionFinishedAt = Self.now }
    }

    /// 记录 RTC 进房的开始时间。
    func beginRoomJoin() {
        lock.withLock { state.roomJoinStartedAt = Self.now }
    }

    /// 记录 RTC 进房的完成时间。
    func finishRoomJoin() {
        lock.withLock { state.roomJoinFinishedAt = Self.now }
    }

    /// 记录本地流发布的开始时间。
    func beginLocalPublication() {
        lock.withLock { state.publicationStartedAt = Self.now }
    }

    /// 记录本地流发布的完成时间。
    func finishLocalPublication() {
        lock.withLock { state.publicationFinishedAt = Self.now }
    }

    /// 记录生成请求发送的开始时间，并重置该任务的首帧时间。
    ///
    /// - Parameter taskID: 本次生成任务的标识。
    func beginSignal(taskID: String) {
        lock.withLock {
            state.taskID = taskID
            state.signalStartedAt = Self.now
            state.firstFrameAt = nil
        }
    }

    /// 记录当前生成任务的结果首帧可显示时间。
    ///
    /// - Parameter taskID: 结果帧所属的任务标识；非当前任务的通知被忽略。
    func finishFirstFrame(taskID: String) {
        lock.withLock {
            guard state.taskID == taskID else { return }
            state.firstFrameAt = Self.now
        }
    }

    /// 记录启动完成时间，并在启用性能日志时输出完整耗时汇总。
    ///
    /// - Parameter taskID: 已完成启动的生成任务标识；非当前任务的通知被忽略。
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

    /// 记录启动失败时间，并在启用性能日志时输出未完成阶段的耗时；取消不计为失败。
    ///
    /// - Parameter error: 导致启动失败的错误。
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
    /// 保存一次启动的阶段时间与任务标识，所有时间均为单调时钟纳秒值。
    struct State {

        // 启动起点
        var startedAt: UInt64?


        // 服务端会话创建
        var sessionStartedAt: UInt64?
        var sessionFinishedAt: UInt64?


        // RTC 房间连接
        var roomJoinStartedAt: UInt64?
        var roomJoinFinishedAt: UInt64?


        // 本地流发布
        var publicationStartedAt: UInt64?
        var publicationFinishedAt: UInt64?


        // 生成请求与首帧
        var signalStartedAt: UInt64?
        var firstFrameAt: UInt64?


        // 启动结果
        var readyAt: UInt64?
        var failureAt: UInt64?


        // 生成任务
        var taskID: String?
    }

    /// 生成启动成功的耗时汇总文本。
    ///
    /// - Parameter state: 包含启动和各阶段时间的记录。
    /// - Returns: 包含总耗时与四个阶段耗时的日志文本；缺少关键时间时返回不可用提示。
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

    /// 生成启动未完成的耗时汇总文本。
    ///
    /// - Parameters:
    ///   - state: 包含失败时间与已记录阶段时间的记录。
    ///   - error: 导致启动失败的 SDK 错误。
    /// - Returns: 包含已耗时、阶段耗时、停留阶段和错误原因的日志文本。
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

    // 计时基准
    /// 当前单调时钟时间，单位为纳秒。
    static var now: UInt64 { DispatchTime.now().uptimeNanoseconds }

    /// 按启动顺序生成会话创建、RTC 进房、本地发布和首帧到达的耗时行。
    ///
    /// - Parameters:
    ///   - state: 启动阶段的时间记录。
    ///   - failureAt: 启动失败时间；非 `nil` 时用于计算尚未完成阶段的耗时。
    /// - Returns: 可拼接到汇总日志中的四个阶段明细。
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

    /// 根据已记录的时间确定启动当前停留的阶段。
    ///
    /// - Parameter state: 启动阶段的时间记录。
    /// - Returns: 当前日志语言对应的阶段名称。
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

    /// 将两个纳秒时间点的间隔格式化为毫秒。
    ///
    /// - Parameters:
    ///   - start: 阶段开始时间。
    ///   - end: 阶段结束时间。
    /// - Returns: 保留一位小数的毫秒文本；时间缺失或结束早于开始时返回 `—`。
    static func duration(_ start: UInt64?, _ end: UInt64?) -> String {
        guard let start, let end, end >= start else { return "—" }
        return String(format: "%.1f ms", Double(end - start) / 1000000)
    }
}
