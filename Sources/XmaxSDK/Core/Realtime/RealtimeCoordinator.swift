import Foundation

/// 统一管理实时操作准入、状态提交和分级资源清理。
actor RealtimeCoordinator {

    enum OperationKind: Sendable {
        case media
        case connection
        case generation
        case cameraSwitch
    }

    enum TerminationScope: Int, Sendable {
        case generation
        case connection
        case all

        func includes(_ scope: TerminationScope) -> Bool {
            rawValue >= scope.rawValue
        }

        func affects(_ kind: OperationKind) -> Bool {
            switch self {
            case .generation:
                kind == .generation || kind == .cameraSwitch
            case .connection:
                kind != .media
            case .all:
                true
            }
        }
    }

    struct CleanupResult: Sendable {
        let sessionID: String?

        init(sessionID: String? = nil) {
            self.sessionID = sessionID
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
     * 接纳并执行一个实时操作。主要操作同一时刻只允许一个；异步操作失效或
     * 调用方取消时，会先完成对应范围的资源清理再结束取消流程。
     */
    func run<Value: Sendable>(
        kind: OperationKind,
        failureScope: TerminationScope,
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

        let operation = Operation(
            kind: kind,
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

    /// 终止指定范围并等待资源清理完成；并发终止请求会合并为最大范围。
    func terminate(
        _ target: TerminationScope,
        finalState: RealtimeConnectionState? = nil
    ) async {
        let task = await requestTermination(
            target,
            finalState: finalState
        )
        await task.value
    }

    /// 登记后台致命故障，并在资源清理后提交错误状态和错误回调。
    func terminate(
        with error: XmaxError,
        target: TerminationScope
    ) async {
        let task = await requestTermination(
            target,
            error: error.withSeverity(.fatal),
            finalState: .error
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
        private var storedFailureScope: TerminationScope

        init(failureScope: TerminationScope) {
            storedFailureScope = failureScope
        }

        var isCurrent: Bool {
            lock.withLock { valid }
        }

        var failure: XmaxError? {
            lock.withLock { terminalError }
        }

        var failureScope: TerminationScope {
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
            failureScope: TerminationScope
        ) {
            self.kind = kind
            lease = OperationLease(failureScope: failureScope)
        }
    }

    final class Termination: @unchecked Sendable {
        let id = UUID()
        var target: TerminationScope
        var finalState: RealtimeConnectionState?
        var error: XmaxError?
        var sessionID: String?
        var waitForOperations: [@Sendable () async -> Void] = []
        var task: Task<Void, Never>!

        init(
            target: TerminationScope,
            finalState: RealtimeConnectionState?,
            error: XmaxError?
        ) {
            self.target = target
            self.finalState = finalState
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
            let terminationTask: Task<Void, Never>
            if let assignedTask = operation.terminationTask {
                terminationTask = assignedTask
            } else if let termination {
                terminationTask = termination.task
            } else {
                terminationTask = await requestTermination(
                    operation.lease.failureScope,
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
        if resolvedError.severity == .fatal {
            let terminationTask = await requestTermination(
                operation.lease.failureScope,
                error: resolvedError,
                finalState: .error,
                origin: operation
            )
            await terminationTask.value
        } else {
            await errorHandler.report(resolvedError)
        }
        finish(operation)
        throw resolvedError
    }

    func requestTermination(
        _ target: TerminationScope,
        error: XmaxError? = nil,
        finalState: RealtimeConnectionState? = nil,
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
            pending.finalState = Self.mergeFinalState(
                pending.finalState,
                finalState
            )
        } else {
            pending = Termination(
                target: target,
                finalState: finalState,
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

        if pending.target.includes(.connection) {
            await setState(
                RealtimeState(
                    connectionState: .disconnecting,
                    sessionID: state.sessionID
                )
            )
        }
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

            let finalState = Self.resolveFinalState(
                requested: pending.finalState,
                error: pending.error,
                target: requestedTarget,
                current: state,
                sessionID: pending.sessionID
            )
            await setState(finalState)
            if let error = pending.error {
                await errorHandler.report(error.withSeverity(.fatal))
            }
            termination = nil
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

    static func resolveFinalState(
        requested: RealtimeConnectionState?,
        error: XmaxError?,
        target: TerminationScope,
        current: RealtimeState,
        sessionID: String?
    ) -> RealtimeState {
        let connectionState: RealtimeConnectionState
        if let requested {
            connectionState = requested
        } else if error != nil {
            connectionState = .error
        } else if target.includes(.connection) {
            connectionState = .disconnected
        } else if current.connectionState == .generating {
            connectionState = .connected
        } else {
            connectionState = current.connectionState
        }

        return RealtimeState(
            connectionState: connectionState,
            sessionID: sessionID ?? current.sessionID,
            taskID: connectionState == .generating ? current.taskID : nil
        )
    }

    static func mergeFinalState(
        _ current: RealtimeConnectionState?,
        _ requested: RealtimeConnectionState?
    ) -> RealtimeConnectionState? {
        if current == .disconnected || requested == .disconnected {
            return .disconnected
        }
        return requested ?? current
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
