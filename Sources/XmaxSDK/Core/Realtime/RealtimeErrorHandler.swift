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
        XmaxLogger.error(
            category: "Realtime",
            message: "实时服务错误 (Realtime Service Error)\n" +
                "├─ 错误码：\(error.code.rawValue)\n" +
                "├─ 级别：\(error.severity.rawValue)\n" +
                "└─ 信息：\(error.message)"
        )
        guard error.severity == .fatal else {
            return
        }

        let listener = lock.withLock { listener }
        if let listener {
            await listener(error)
        }
    }
}
