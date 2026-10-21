//
//  RoomHeartbeat.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 周期发送 RTC 房间心跳并隔离已经停止的旧周期。
final class RoomHeartbeat: @unchecked Sendable {

    /// 提交房间信令的 RTC 管理器。
    private let rtcManager: any RtcManaging

    /// 控制房间心跳发送间隔。
    private let sleeper: RoomHeartbeatSleeper

    /// 区分每次启动和停止后的心跳周期。
    private let cycle = RoomHeartbeatCycle()

    /// 保护心跳任务的替换与取消。
    private let taskLock = NSLock()

    /// 当前房间心跳的执行任务。
    private var heartbeatTask: Task<Void, Never>?

    /// 创建使用指定等待策略的房间心跳组件。
    init(
        rtcManager: any RtcManaging,
        sleeper: RoomHeartbeatSleeper = .live
    ) {
        self.rtcManager = rtcManager
        self.sleeper = sleeper
    }

    /// 使当前心跳周期失效并取消后台任务。
    deinit {
        cycle.advance()
        heartbeatTask?.cancel()
    }

    /// 替换旧周期并启动指定用户的房间心跳。
    ///
    /// - Parameter userID: 发送心跳使用的本地用户账号。
    func start(
        userID: String
    ) {
        taskLock.withLock {
            let version = cycle.advance()
            heartbeatTask?.cancel()
            let context = Context(
                rtcManager: rtcManager,
                sleeper: sleeper,
                cycle: cycle,
                version: version,
                userID: userID
            )
            heartbeatTask = Task {
                await Self.run(context)
            }
        }
    }

    /// 使当前周期失效并取消心跳任务。
    func stop() {
        taskLock.withLock {
            cycle.advance()
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
    }
}

private extension RoomHeartbeat {

    /// 保存一个房间心跳周期的发送依赖和有效期。
    struct Context: Sendable {

        /// 发送房间心跳的 RTC 管理器。
        let rtcManager: any RtcManaging

        /// 等待下一个房间心跳周期。
        let sleeper: RoomHeartbeatSleeper

        /// 检查当前房间心跳周期是否有效。
        let cycle: RoomHeartbeatCycle

        /// 该任务所属心跳周期的有效期标识。
        let version: UInt64

        /// 发送房间心跳的业务用户标识。
        let userID: String
    }

    /// 按等待策略发送心跳，忽略已停止周期的迟到结果。
    ///
    /// - Parameter context: 当前心跳周期的依赖和身份信息。
    static func run(
        _ context: Context
    ) async {
        while context.cycle.isCurrent(context.version) {
            do {
                try await context.sleeper.sleep()
                try Task.checkCancellation()
                guard context.cycle.isCurrent(context.version) else {
                    return
                }
                try context.rtcManager.sendRoomMessage(
                    RoomEvent.heartbeat(userID: context.userID)
                )
            } catch is CancellationError {
                return
            } catch {
                guard context.cycle.isCurrent(context.version) else {
                    return
                }
                XmaxLogger.room.error(
                    message: "发送 RTC 房间心跳失败 (Failed to Send RTC Room Heartbeat)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))" +
                        (error as NSError).localizedDescription
                )
            }
        }
    }
}

/// 提供可替换的房间心跳等待行为。
struct RoomHeartbeatSleeper: Sendable {

    /// 等待下一次房间心跳的异步操作，支持取消。
    let sleep: @Sendable () async throws -> Void

    /// 采用 10 秒间隔的房间心跳等待器。
    static let live = RoomHeartbeatSleeper {
        try await Task.sleep(nanoseconds: 10_000_000_000)
    }
}

/// 使用版本隔离停止或重启后的旧房间心跳任务。
private final class RoomHeartbeatCycle: @unchecked Sendable {

    /// 保护房间心跳版本的读取与递增。
    private let lock = NSLock()

    /// 当前房间心跳周期的递增版本。
    private var value: UInt64 = 0

    /// 更新心跳有效期，使先前周期失效。
    ///
    /// - Returns: 更新后的周期版本。
    @discardableResult
    func advance() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }

    /// 检查心跳版本是否仍为当前周期。
    ///
    /// - Parameter version: 需要检查的周期版本。
    /// - Returns: 版本仍有效时返回 `true`。
    func isCurrent(
        _ version: UInt64
    ) -> Bool {
        lock.withLock { value == version }
    }
}
