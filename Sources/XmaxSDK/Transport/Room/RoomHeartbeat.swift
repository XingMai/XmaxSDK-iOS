import Foundation

/// 周期发送 RTC 房间心跳并隔离已经停止的旧周期。
final class RoomHeartbeat: @unchecked Sendable {

    // 基础层组件
    private let rtcManager: any RtcManaging
    private let sleeper: RoomHeartbeatSleeper

    // 并发控制
    private let cycle = RoomHeartbeatCycle()
    private let taskLock = NSLock()

    // 运行状态
    private var heartbeatTask: Task<Void, Never>?

    init(
        rtcManager: any RtcManaging,
        sleeper: RoomHeartbeatSleeper = .live
    ) {
        self.rtcManager = rtcManager
        self.sleeper = sleeper
    }

    deinit {
        cycle.advance()
        heartbeatTask?.cancel()
    }

    func start(userID: String) {
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

    func stop() {
        taskLock.withLock {
            cycle.advance()
            heartbeatTask?.cancel()
            heartbeatTask = nil
        }
    }
}

private extension RoomHeartbeat {
    struct Context: Sendable {
        let rtcManager: any RtcManaging
        let sleeper: RoomHeartbeatSleeper
        let cycle: RoomHeartbeatCycle
        let version: UInt64
        let userID: String
    }

    static func run(_ context: Context) async {
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
                XmaxLogger.error(
                    "发送 RTC 房间心跳失败\n└─ 原因：" +
                        (error as NSError).localizedDescription,
                    category: "Room"
                )
            }
        }
    }
}

/// 提供可替换的房间心跳等待行为。
struct RoomHeartbeatSleeper: Sendable {
    let sleep: @Sendable () async throws -> Void

    static let live = RoomHeartbeatSleeper {
        try await Task.sleep(nanoseconds: 10_000_000_000)
    }
}

/// 使用版本隔离停止或重启后的旧房间心跳任务。
private final class RoomHeartbeatCycle: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var value: UInt64 = 0

    @discardableResult
    func advance() -> UInt64 {
        lock.withLock {
            value &+= 1
            return value
        }
    }

    func isCurrent(_ version: UInt64) -> Bool {
        lock.withLock { value == version }
    }
}
