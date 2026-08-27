import Foundation

/// 汇聚各业务组件上报的错误，并统一通知实时错误监听器。
final class RealtimeErrorHandler: @unchecked Sendable {

    // 并发控制
    private let lock = NSLock()

    // 事件监听
    private var listener: RealtimeErrorListener?

    func setListener(_ listener: RealtimeErrorListener?) {
        lock.withLock {
            self.listener = listener
        }
    }

    func forward(_ error: XmaxError) {
        Task {
            await report(error)
        }
    }

    func report(_ error: XmaxError) async {
        let listener = lock.withLock { listener }
        if let listener {
            await listener(error)
        }
    }
}
