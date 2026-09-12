import Foundation

/// 统一管理实时操作准入、状态提交和分级资源清理。
actor RealtimeCoordinator {

    enum OperationKind: Sendable {
        case media
        case connection
        case generation
        case cameraSwitch

        /// 更新生成条件或回传尺寸，不改变生成生命周期。
        case configuration
    }

    enum TerminationScope: Int, Sendable {
        case connection
        case all

        func affects(_ kind: OperationKind) -> Bool {
            switch self {
            case .connection:
                kind != .media
            case .all:
                true
            }
        }
    }

    struct CleanupResult: Sendable {
        let sessionID: String?
        let hasLocalMedia: Bool

        init(sessionID: String? = nil, hasLocalMedia: Bool = false) {
            self.sessionID = sessionID
            self.hasLocalMedia = hasLocalMedia
        }
    }

    struct Token: Sendable {
        fileprivate let lease: OperationLease

        /// 更新当前操作失败或被调用方取消时需要释放的资源范围。
        func setFailureScope(_ scope: TerminationScope) {
            lease.setFailureScope(scope)
        }

        /// 在异步边界后校验当前操作仍拥有实时生命周期。
        func ensureCurrent() throws {
            try lease.ensureCurrent()
        }

        /// 供必须同步返回的底层有效性回调读取操作状态。
        var isCurrent: Bool {
            lease.isCurrent
        }
    }

    typealias CleanupHandler = @Sendable (
        _ scope: TerminationScope,
        _ taskID: String
    ) async -> CleanupResult

    // 业务组件
    private let errorHandler: RealtimeErrorHandler
    private let cleanup: CleanupHandler

    // 状态管理
    private var state = RealtimeState(connectionState: .idle)
    private var stateListener: RealtimeStateListener?

    // 操作管理
    private var activeOperation: Operation?
    private var termination: Termination?

    init(
        errorHandler: RealtimeErrorHandler,
        cleanup: @escaping CleanupHandler
    ) {
        self.errorHandler = errorHandler
        self.cleanup = cleanup
    }

    var currentState: RealtimeState {
        state
    }

    func setStateListener(_ listener: RealtimeStateListener?) async {
        stateListener = listener
        if let listener {
            await listener(state)
        }
    }

    /**
     * 接纳并执行一个实时操作，同一时刻只允许一个。生命周期操作取消时先完成
     * 对应范围的资源清理；仅取消参数更新不会停止当前生成。
     */
    func run<Value: Sendable>(
        kind: OperationKind,
        failureScope: TerminationScope? = nil,
        operation body: @escaping @Sendable (Token) async throws -> Value
    ) async throws -> Value {
        guard termination == nil, activeOperation == nil else {
            let error = XmaxError(
                code: .invalidConfiguration,
                message: "Another realtime operation is in progress; " +
                    "wait for it to finish"
            )
            await errorHandler.report(error)
            throw error
        }

        // 已在生成时，startGeneration 只更新条件，与回传尺寸调整共用配置操作。
        let operationKind: OperationKind =
            kind == .generation && state.connectionState == .generating
                ? .configuration : kind
        let operation = Operation(
            kind: operationKind,
            failureScope: failureScope
        )
        let token = Token(lease: operation.lease)
        let task = Task {
            try await body(token)
        }
        operation.cancel = {
            task.cancel()
        }
        operation.waitForCompletion = {
            _ = try? await task.value
        }
        activeOperation = operation

        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                operation.lease.invalidate()
                task.cancel()
            }
            try Task.checkCancellation()
            try token.ensureCurrent()
            finish(operation)
            return value
        } catch {
            return try await handleFailure(
                error,
                operation: operation
            )
        }
    }

    /// 仅当前操作可以提交新的公开状态。
    func commit(
        _ nextState: RealtimeState,
        token: Token
    ) async throws {
        try token.ensureCurrent()
        await setState(nextState)
    }

    /// 当前本地预览满足就绪条件后，结束媒体准备状态。
    func localPreviewDidBecomeReady(isCurrent: @Sendable () -> Bool) async {
        guard state.connectionState == .preparing, isCurrent() else { return }
        await setState(RealtimeState(connectionState: .ready))
    }

    /// 断开实时连接；尚未提交连接状态的活跃操作也会被取消。
    func disconnect(reason: RealtimeReason = .normal) async {
        let task = await beginDisconnect(reason: reason)
        await task?.value
    }

    /// 发起断开并返回收尾任务，使本地媒体调整不必等待网络资源释放。
    func beginDisconnect(reason: RealtimeReason) async -> Task<Void, Never>? {
        let hasConnectionOperation = activeOperation.map {
            TerminationScope.connection.affects($0.kind)
        } ?? false
        guard hasConnectionOperation || termination != nil ||
                (state.connectionState != .idle &&
                    state.connectionState != .preparing &&
                    state.connectionState != .ready) else {
            return nil
        }
        return await requestTermination(.connection, reason: reason)
    }

    /// 终止指定范围并等待资源清理完成；并发终止请求会合并为最大范围。
    func terminate(
        _ target: TerminationScope,
        reason: RealtimeReason = .normal
    ) async {
        let task = await requestTermination(
            target,
            reason: reason
        )
        await task.value
    }

    /// 清理仍属于当前生命周期的后台故障，并通过最终状态提供原因。
    func terminate(
        with error: XmaxError,
        target: TerminationScope,
        isCurrent: @Sendable () -> Bool = { true }
    ) async {
        guard isCurrent() else { return }
        // 清理期间的远端迟到错误不覆盖主动结束；本地媒体终止仍需扩大释放范围。
        if termination != nil, target != .all { return }
        let task = await requestTermination(
            target,
            error: error,
            reason: .failure(error)
        )
        await task.value
    }
}

private extension RealtimeCoordinator {
    final class OperationLease: @unchecked Sendable {

        // 并发状态
        private let lock = NSLock()
        private var valid = true
        private var terminalError: XmaxError?
        private var storedFailureScope: TerminationScope?

        init(failureScope: TerminationScope?) {
            storedFailureScope = failureScope
        }

        var isCurrent: Bool {
            lock.withLock { valid }
        }

        var failure: XmaxError? {
            lock.withLock { terminalError }
        }

        var failureScope: TerminationScope? {
            lock.withLock { storedFailureScope }
        }

        func setFailureScope(_ scope: TerminationScope) {
            lock.withLock {
                storedFailureScope = scope
            }
        }

        func invalidate(error: XmaxError? = nil) {
            lock.withLock {
                valid = false
                if terminalError == nil {
                    terminalError = error
                }
            }
        }

        func ensureCurrent() throws {
            let result = lock.withLock { (valid, terminalError) }
            guard result.0 else {
                if let error = result.1 {
                    throw error
                }
                throw Self.cancelledError()
            }
            try Task.checkCancellation()
        }

        private static func cancelledError() -> XmaxError {
            XmaxError(
                code: .cancelled,
                message: "Realtime operation was cancelled"
            )
        }
    }

    final class Operation: @unchecked Sendable {
        let id = UUID()
        let kind: OperationKind
        let lease: OperationLease
        var cancel: @Sendable () -> Void = {}
        var waitForCompletion: @Sendable () async -> Void = {}
        var terminationTask: Task<Void, Never>?

        init(
            kind: OperationKind,
            failureScope: TerminationScope?
        ) {
            self.kind = kind
            lease = OperationLease(failureScope: failureScope)
        }
    }

    final class Termination: @unchecked Sendable {
        let id = UUID()
        var target: TerminationScope
        var reason: RealtimeReason
        var error: XmaxError?
        var sessionID: String?
        var waitForOperations: [@Sendable () async -> Void] = []
        var task: Task<Void, Never>!

        init(
            target: TerminationScope,
            reason: RealtimeReason,
            error: XmaxError?
        ) {
            self.target = target
            self.reason = reason
            self.error = error
        }
    }

    func handleFailure<Value: Sendable>(
        _ error: any Error,
        operation: Operation
    ) async throws -> Value {
        let operationWasCancelled = Self.isCancellation(error) ||
            !operation.lease.isCurrent || Task.isCancelled

        if operationWasCancelled {
            // 取消配置请求本身不停止生成；外部断开或关闭仍按已有终止流程等待收尾。
            if (operation.kind == .configuration || operation.lease.failureScope == nil),
               operation.terminationTask == nil,
               termination == nil {
                finish(operation)
                if operation.kind == .media, state.connectionState == .preparing {
                    await setState(RealtimeState(connectionState: .idle))
                }
                throw Self.cancelledError()
            }
            let terminationTask: Task<Void, Never>
            if let assignedTask = operation.terminationTask {
                terminationTask = assignedTask
            } else if let termination {
                terminationTask = termination.task
            } else {
                terminationTask = await requestTermination(
                    operation.lease.failureScope ?? .connection,
                    origin: operation
                )
            }
            await terminationTask.value
            finish(operation)
            if let failure = operation.lease.failure {
                throw failure
            }
            throw Self.cancelledError()
        }

        let resolvedError = XmaxError.from(error)
        if operation.kind != .configuration, let scope = operation.lease.failureScope {
            let terminationTask = await requestTermination(
                scope,
                error: resolvedError,
                reason: .failure(resolvedError),
                origin: operation
            )
            await terminationTask.value
        } else {
            finish(operation)
            if operation.kind == .media, state.connectionState == .preparing {
                await setState(RealtimeState(connectionState: .idle))
            }
            await errorHandler.report(resolvedError)
            throw resolvedError
        }
        finish(operation)
        throw resolvedError
    }

    func requestTermination(
        _ target: TerminationScope,
        error: XmaxError? = nil,
        reason: RealtimeReason = .normal,
        origin: Operation? = nil
    ) async -> Task<Void, Never> {
        let pending: Termination
        if let termination {
            pending = termination
            if target.rawValue > pending.target.rawValue {
                pending.target = target
            }
            if pending.error == nil {
                pending.error = error
            }
            if let error, pending.error == error {
                pending.reason = .failure(error)
            }
        } else {
            pending = Termination(
                target: target,
                reason: reason,
                error: error
            )
            termination = pending
            pending.task = Task { [weak self] in
                await self?.performTermination(id: pending.id)
            }
        }

        if let activeOperation,
           activeOperation !== origin,
           pending.target.affects(activeOperation.kind) {
            activeOperation.lease.invalidate(error: pending.error)
            activeOperation.terminationTask = pending.task
            activeOperation.cancel()
            pending.waitForOperations.append(
                activeOperation.waitForCompletion
            )
        } else if let origin {
            origin.lease.invalidate(error: error)
            origin.terminationTask = pending.task
            pending.waitForOperations.append(origin.waitForCompletion)
        }

        await setState(
            RealtimeState(
                connectionState: .disconnecting,
                sessionID: state.sessionID,
                reason: nil
            )
        )
        return pending.task
    }

    func performTermination(id: UUID) async {
        guard let pending = termination, pending.id == id else {
            return
        }

        while true {
            let waiters = pending.waitForOperations
            pending.waitForOperations.removeAll()
            for waiter in waiters {
                await waiter()
            }

            let requestedTarget = pending.target
            let taskID = state.taskID ?? ""
            let result = await cleanup(requestedTarget, taskID)
            if let sessionID = result.sessionID {
                pending.sessionID = sessionID
            }

            guard pending.target == requestedTarget,
                  pending.waitForOperations.isEmpty else {
                continue
            }

            let connectionState: RealtimeConnectionState
            if requestedTarget == .all {
                connectionState = .idle
            } else {
                connectionState = result.hasLocalMedia ? .ready : .idle
            }
            let finalState = RealtimeState(
                connectionState: connectionState,
                sessionID: pending.sessionID ?? state.sessionID,
                reason: pending.reason
            )
            // 先完成内部收尾，再通知监听器，避免旧任务覆盖重入的关闭请求。
            if let activeOperation,
               requestedTarget.affects(activeOperation.kind) {
                finish(activeOperation)
            }
            let listener = state != finalState ? stateListener : nil
            state = finalState
            termination = nil
            errorHandler.invalidatePendingFailures(target: requestedTarget)
            if let listener {
                await listener(finalState)
            }
            if let error = pending.error {
                await errorHandler.report(error)
            }
            return
        }
    }

    func finish(_ operation: Operation) {
        if activeOperation?.id == operation.id {
            activeOperation = nil
        }
    }

    func setState(_ nextState: RealtimeState) async {
        guard state != nextState else {
            return
        }
        state = nextState
        if let stateListener {
            await stateListener(nextState)
        }
    }

    static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError ||
            (error as? XmaxError)?.code == .cancelled
    }

    static func cancelledError() -> XmaxError {
        XmaxError(
            code: .cancelled,
            message: "Realtime operation was cancelled"
        )
    }
}
