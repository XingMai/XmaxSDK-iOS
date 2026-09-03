import Foundation

/// 提供可从同步有效性回调读取的连接生命周期版本。
final class RealtimeOperationVersion: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var value: UInt64 = 0

    var current: UInt64 {
        lock.withLock { value }
    }

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
