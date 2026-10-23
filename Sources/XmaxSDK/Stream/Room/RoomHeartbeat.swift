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

/// Sends RTC room heartbeats while rejecting stopped cycles.
final class RoomHeartbeat: @unchecked Sendable {

    /// Heartbeat dependencies.

    /// The room signaling RTC manager.
    private let rtcManager: any RtcManaging

    /// The room heartbeat interval provider.
    private let sleeper: RoomHeartbeatSleeper

    /// Heartbeat lifecycle.

    /// The revision separating heartbeat cycles.
    private let cycle = RoomHeartbeatCycle()

    /// The lock protecting heartbeat task replacement.
    private let taskLock = NSLock()

    /// The current room heartbeat task.
    private var heartbeatTask: Task<Void, Never>?

    /// Creates a room heartbeat with a wait strategy.
    init(
        rtcManager: any RtcManaging,
        sleeper: RoomHeartbeatSleeper = .live
    ) {
        self.rtcManager = rtcManager
        self.sleeper = sleeper
    }

    /// Invalidates and cancels the active heartbeat cycle.
    deinit {
        cycle.advance()
        heartbeatTask?.cancel()
    }

    /// Starts a user's room heartbeat, replacing the previous cycle.
    ///
    /// - Parameter userID: The local account sending heartbeats.
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

    /// Invalidates the current cycle and cancels its task.
    func stop() {
        taskLock.withLock {
            cycle.advance()
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
    }
}

private extension RoomHeartbeat {

    /// The dependencies and validity of a room heartbeat cycle.
    struct Context: Sendable {

        /// The RTC room heartbeat sender.
        let rtcManager: any RtcManaging

        /// The wait for the next room heartbeat.
        let sleeper: RoomHeartbeatSleeper

        /// The room heartbeat validity check.
        let cycle: RoomHeartbeatCycle

        /// The heartbeat loop revision.
        let version: UInt64

        /// The business user sending room heartbeats.
        let userID: String
    }

    /// Sends scheduled heartbeats while rejecting stopped cycles.
    ///
    /// - Parameter context: The heartbeat cycle dependencies and identity.
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
                    message:
                        "发送 RTC 房间心跳失败 (Failed to Send RTC Room Heartbeat)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))"
                        + (error as NSError).localizedDescription
                )
            }
        }
    }
}

/// A replaceable room heartbeat wait.
struct RoomHeartbeatSleeper: Sendable {

    /// The cancellable wait for a room heartbeat.
    let sleep: @Sendable () async throws -> Void

    /// A room heartbeat wait using a 10-second interval.
    static let live = RoomHeartbeatSleeper {
        try await Task.sleep(nanoseconds: 10_000_000_000)
    }
}

/// The revision separating restarted room heartbeats.
private final class RoomHeartbeatCycle: @unchecked Sendable {

    /// The lock protecting room heartbeat revisions.
    private let lock = NSLock()

    /// The current room heartbeat revision.
    private var value: UInt64 = 0

    /// Invalidates previous heartbeat cycles.
    ///
    /// - Returns: The new cycle revision.
    @discardableResult
    func advance() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }

    /// Checks whether a heartbeat revision remains current.
    ///
    /// - Parameter version: The cycle revision to check.
    ///
    /// - Returns: `true` if the revision remains valid.
    func isCurrent(
        _ version: UInt64
    ) -> Bool {
        lock.withLock {
            value == version
        }
    }
}
