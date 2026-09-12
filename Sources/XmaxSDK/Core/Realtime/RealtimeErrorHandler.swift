import Foundation

/// 记录实时错误，并将后台故障交给 Coordinator 统一结束生命周期。
final class RealtimeErrorHandler: @unchecked Sendable {

    typealias FailureHandler = @Sendable (
        XmaxError, RealtimeCoordinator.TerminationScope, @escaping @Sendable () -> Bool
    ) async -> Void

    // 并发控制
    private let lock = NSLock()
    private var mediaRevision = UUID()
    private var connectionRevision = UUID()

    // 内部故障处理
    private var failureHandler: FailureHandler?

    func setFailureHandler(_ handler: @escaping FailureHandler) {
        lock.withLock { failureHandler = handler }
    }

    /// 使已结束生命周期中排队等待处理的故障失效。
    func invalidatePendingFailures(target: RealtimeCoordinator.TerminationScope = .all) {
        lock.withLock {
            connectionRevision = UUID()
            if target == .all { mediaRevision = UUID() }
        }
    }

    func forward(
        _ error: XmaxError,
        target: RealtimeCoordinator.TerminationScope? = nil
    ) {
        let (revision, handler) = lock.withLock {
            (target == .all ? mediaRevision : connectionRevision, failureHandler)
        }
        Task { [self] in
            guard let target, let handler else {
                await report(error)
                return
            }
            await handler(error, target, { [weak self] in
                guard let self else { return false }
                return lock.withLock {
                    (target == .all ? mediaRevision : connectionRevision) == revision
                }
            })
        }
    }

    func report(_ error: XmaxError) async {
        XmaxLogger.realtime.error(
            message: "实时服务错误 (Realtime Service Error)\n" +
                "├─ \(XmaxLogger.localized("错误码：", "Error Code: "))\(error.code.rawValue)\n" +
                "└─ \(XmaxLogger.localized("信息：", "Message: "))\(error.message)"
        )
    }
}
