//
//  RealtimeCoordinator.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 统一管理实时操作准入、状态提交和分级资源清理。
actor RealtimeCoordinator {

    /// 区分媒体准备、连接、生成和配置操作。
    enum OperationKind: Sendable {
        /// 创建、停止或调整本地媒体。
        case media

        /// 建立实时连接。
        case connection

        /// 启动生成。
        case generation

        /// 切换摄像头并按需恢复生成。
        case cameraSwitch

        /// 更新生成条件或回传尺寸，不改变生成生命周期。
        case configuration
    }

    /// 定义终止操作需要释放的资源范围。
    enum TerminationScope: Int, Sendable {
        /// 释放连接和生成资源，保留本地媒体。
        case connection

        /// 释放连接、生成和本地媒体资源。
        case all

        /// 判断指定操作是否属于当前清理范围。
        ///
        /// - Parameter kind: 待判断的操作类型。
        /// - Returns: 属于当前清理范围时返回 `true`。
        func affects(_ kind: OperationKind) -> Bool {
            switch self {
            case .connection:
                kind != .media
            case .all:
                true
            }
        }
    }

    /// 记录资源清理后的会话标识与本地媒体保留状态。
    struct CleanupResult: Sendable {

        /// 清理结果
        let sessionID: String?
        let hasLocalMedia: Bool

        /// 创建资源清理结果。
        ///
        /// - Parameters:
        ///   - sessionID: 此次清理涉及的会话标识；没有会话时传入 `nil`。
        ///   - hasLocalMedia: 清理后是否仍保留可用的本地媒体。
        init(sessionID: String? = nil, hasLocalMedia: Bool = false) {
            self.sessionID = sessionID
            self.hasLocalMedia = hasLocalMedia
        }
    }

    /// 提供当前操作的有效性校验与失败清理范围设置。
    struct Token: Sendable {

        /// 操作凭据
        fileprivate let lease: OperationLease

        /// 设置当前操作失败或取消时的资源清理范围。
        ///
        /// - Parameter scope: 需要释放的资源范围。
        func setFailureScope(_ scope: TerminationScope) {
            lease.setFailureScope(scope)
        }

        /// 确认当前操作仍有效且未被取消。
        ///
        /// - Throws: 操作已失效或被取消时抛出错误。
        func ensureCurrent() throws {
            try lease.ensureCurrent()
        }

        /// 当前操作是否仍有效。
        var isCurrent: Bool {
            lease.isCurrent
        }
    }

    /// 释放指定范围内的资源并返回清理结果。
    ///
    /// - Parameters:
    ///   - scope: 需要释放的资源范围。
    ///   - taskID: 待结束的生成任务标识；没有任务时为空字符串。
    /// - Returns: 清理涉及的会话标识与本地媒体保留状态。
    typealias CleanupHandler = @Sendable (
        _ scope: TerminationScope,
        _ taskID: String
    ) async -> CleanupResult

    /// 业务组件
    private let errorHandler: RealtimeErrorHandler
    private let cleanup: CleanupHandler

    /// 状态管理
    private var state = RealtimeState(connectionState: .idle)
    private var stateListener: RealtimeStateListener?

    /// 操作管理
    private var activeOperation: Operation?
    private var termination: Termination?
    private var foregroundRequests = 0

    /// 创建实时生命周期协调器。
    ///
    /// - Parameters:
    ///   - errorHandler: 负责记录错误并转交运行中故障的处理器。
    ///   - cleanup: 执行指定范围资源清理的回调。
    init(
        errorHandler: RealtimeErrorHandler,
        cleanup: @escaping CleanupHandler
    ) {
        self.errorHandler = errorHandler
        self.cleanup = cleanup
    }

    /// 当前对外发布的实时状态。
    var currentState: RealtimeState {
        state
    }

    /// 更新状态监听器，并立即通知当前状态。
    ///
    /// - Parameter listener: 接收状态变化的回调；传入 `nil` 移除监听。
    func setStateListener(_ listener: RealtimeStateListener?) async {
        stateListener = listener
        if let listener {
            await listener(state)
        }
    }

    /// 串行接纳实时操作，并在失败或取消时完成对应范围的资源清理。
    ///
    /// - Parameters:
    ///   - kind: 请求执行的操作类型。
    ///   - failureScope: 操作失败或取消时的清理范围；传入 `nil` 不主动发起清理。
    ///   - body: 实际执行的操作，使用传入的凭据检查异步执行期间的有效性。
    /// - Returns: 操作成功执行后的结果。
    /// - Throws: 已有操作或清理任务占用生命周期、操作失败或被取消时抛出错误。
    func run<Value: Sendable>(
        kind: OperationKind,
        failureScope: TerminationScope? = nil,
        operation body: @escaping @Sendable (Token) async throws -> Value
    ) async throws -> Value {
        foregroundRequests += 1
        defer { foregroundRequests -= 1 }
        if let background = activeOperation, background.background {
            // 已发出的回传配置先完成本地提交，前台设置再基于最新配置执行。
            await background.waitForCompletion()
            finish(background)
        }
        try Task.checkCancellation()
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

    /// 空闲时执行一次低优先级调档；忙碌时跳过，不影响公开状态。
    ///
    /// - Parameter body: 调整传输配置的操作，异步边界后须检查 token。
    /// - Returns: 是否接纳并成功完成此次调档。
    /// - Throws: 已接纳的配置操作失败或被终止时抛出错误。
    func runAdaptiveConfiguration(
        _ body: @escaping @Sendable (Token) async throws -> Void
    ) async throws -> Bool {
        guard termination == nil, activeOperation == nil, foregroundRequests == 0,
              state.connectionState == .generating else { return false }
        let operation = Operation(kind: .configuration, failureScope: nil, background: true)
        let token = Token(lease: operation.lease)
        let task = Task { try await body(token) }
        operation.cancel = { task.cancel() }
        operation.waitForCompletion = { _ = try? await task.value }
        activeOperation = operation
        defer { finish(operation) }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            operation.lease.invalidate()
            task.cancel()
        }
        try token.ensureCurrent()
        return true
    }

    /// 提交当前有效操作产生的新状态。
    ///
    /// - Parameters:
    ///   - nextState: 需要发布的新状态。
    ///   - token: 本次操作的有效性凭据。
    /// - Throws: 操作已失效或被取消时抛出错误。
    func commit(
        _ nextState: RealtimeState,
        token: Token
    ) async throws {
        try token.ensureCurrent()
        await setState(nextState)
    }

    /// 在当前本地预览就绪后，将媒体准备状态更新为就绪。
    ///
    /// - Parameter isCurrent: 判断预览通知是否仍属于当前本地媒体的回调。
    func localPreviewDidBecomeReady(isCurrent: @Sendable () -> Bool) async {
        guard state.connectionState == .preparing, isCurrent() else { return }
        await setState(RealtimeState(connectionState: .ready))
    }

    /// 断开实时连接，并等待连接相关操作和资源完成清理。
    ///
    /// - Parameter reason: 本次断开的原因，随最终状态通知。
    func disconnect(reason: RealtimeReason = .normal) async {
        let task = await beginDisconnect(reason: reason)
        await task?.value
    }

    /// 发起连接清理并返回收尾任务，保留本地媒体。
    ///
    /// - Parameter reason: 本次断开的原因，随最终状态通知。
    /// - Returns: 连接清理任务；没有连接或相关操作需要终止时返回 `nil`。
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

    /// 终止指定范围内的操作并等待清理完成；并发请求合并为最大清理范围。
    ///
    /// - Parameters:
    ///   - target: 需要终止的资源范围。
    ///   - reason: 终止原因，随最终状态通知。
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

    /// 终止当前生命周期内发生故障的资源，并通过最终状态提供错误原因。
    ///
    /// - Parameters:
    ///   - error: 触发终止的运行中错误。
    ///   - target: 需要终止的资源范围。
    ///   - isCurrent: 判断错误是否仍属于当前生命周期的回调。
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
    /// 通过线程安全的有效性凭据控制操作取消与失败清理。
    final class OperationLease: @unchecked Sendable {

        /// 并发控制
        private let lock = NSLock()

        /// 操作状态
        private var valid = true
        private var terminalError: XmaxError?

        /// 失败清理配置
        private var storedFailureScope: TerminationScope?

        /// 创建操作凭据。
        ///
        /// - Parameter failureScope: 操作失败或取消时的清理范围；`nil` 表示不主动清理。
        init(failureScope: TerminationScope?) {
            storedFailureScope = failureScope
        }

        /// 操作凭据是否仍有效。
        var isCurrent: Bool {
            lock.withLock { valid }
        }

        /// 使操作失效的首个错误；主动取消时可能为 `nil`。
        var failure: XmaxError? {
            lock.withLock { terminalError }
        }

        /// 操作失败或取消时的资源清理范围。
        var failureScope: TerminationScope? {
            lock.withLock { storedFailureScope }
        }

        /// 更新操作失败或取消时的资源清理范围。
        ///
        /// - Parameter scope: 需要释放的资源范围。
        func setFailureScope(_ scope: TerminationScope) {
            lock.withLock {
                storedFailureScope = scope
            }
        }

        /// 使操作失效，并保留首次收到的终止错误。
        ///
        /// - Parameter error: 使操作失效的错误；主动取消时可传入 `nil`。
        func invalidate(error: XmaxError? = nil) {
            lock.withLock {
                valid = false
                if terminalError == nil {
                    terminalError = error
                }
            }
        }

        /// 确认凭据有效且当前任务未被取消。
        ///
        /// - Throws: 凭据失效时抛出终止错误或取消错误；任务取消时抛出取消错误。
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

        /// 创建实时操作取消错误。
        ///
        /// - Returns: 表示实时操作已取消的 SDK 错误。
        private static func cancelledError() -> XmaxError {
            XmaxError(
                code: .cancelled,
                message: "Realtime operation was cancelled"
            )
        }
    }

    /// 保存单次实时操作的身份、取消能力与收尾任务。
    final class Operation: @unchecked Sendable {

        /// 操作标识与类型
        let id = UUID()
        let kind: OperationKind
        let background: Bool

        /// 操作执行控制
        let lease: OperationLease
        var cancel: @Sendable () -> Void = {}
        var waitForCompletion: @Sendable () async -> Void = {}

        /// 终止收尾
        var terminationTask: Task<Void, Never>?

        /// 创建实时操作记录。
        ///
        /// - Parameters:
        ///   - kind: 操作类型，用于确定取消和清理行为。
        ///   - failureScope: 失败或取消时的资源清理范围。
        ///   - background: 是否为低优先级后台配置操作。
        init(
            kind: OperationKind,
            failureScope: TerminationScope?,
            background: Bool = false
        ) {
            self.kind = kind
            self.background = background
            lease = OperationLease(failureScope: failureScope)
        }
    }

    /// 合并并发终止请求，并保存清理范围、结束原因与等待任务。
    final class Termination: @unchecked Sendable {

        /// 终止请求
        let id = UUID()
        var target: TerminationScope
        var reason: RealtimeReason
        var error: XmaxError?

        /// 会话清理结果
        var sessionID: String?

        /// 异步收尾
        var waitForOperations: [@Sendable () async -> Void] = []
        var task: Task<Void, Never>!

        /// 创建资源终止记录。
        ///
        /// - Parameters:
        ///   - target: 初始资源清理范围。
        ///   - reason: 结束原因。
        ///   - error: 触发清理的错误；主动结束时传入 `nil`。
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

    /// 完成失败操作的状态和资源收尾，并向调用方抛出对应错误。
    ///
    /// - Parameters:
    ///   - error: 操作执行期间产生的错误。
    ///   - operation: 产生错误的操作记录。
    /// - Returns: 不返回结果；完成错误处理后始终抛出错误。
    /// - Throws: 操作被取消时抛出终止错误或取消错误；其他情况抛出转换后的 SDK 错误。
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

    /// 创建或合并资源终止请求，并取消清理范围内的操作。
    ///
    /// - Parameters:
    ///   - target: 此次请求的资源清理范围。
    ///   - error: 触发清理的错误；主动结束时传入 `nil`。
    ///   - reason: 最终状态携带的结束原因。
    ///   - origin: 主动发起清理的失败操作；外部终止请求传入 `nil`。
    /// - Returns: 合并后的资源清理任务。
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

    /// 等待相关操作退出、释放资源，并发布清理完成后的状态。
    ///
    /// - Parameter id: 需要执行的终止记录标识；过期请求不执行清理。
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

    /// 移除与指定记录匹配的当前操作。
    ///
    /// - Parameter operation: 已完成的操作记录。
    func finish(_ operation: Operation) {
        if activeOperation?.id == operation.id {
            activeOperation = nil
        }
    }

    /// 更新实时状态，仅在状态变化时通知监听器。
    ///
    /// - Parameter nextState: 需要发布的新状态。
    func setState(_ nextState: RealtimeState) async {
        guard state != nextState else {
            return
        }
        state = nextState
        if let stateListener {
            await stateListener(nextState)
        }
    }

    /// 判断错误是否表示操作取消。
    ///
    /// - Parameter error: 需要判断的错误。
    /// - Returns: 任务取消错误或 SDK 取消错误返回 `true`。
    static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError ||
            (error as? XmaxError)?.code == .cancelled
    }

    /// 创建实时操作取消错误。
    ///
    /// - Returns: 表示实时操作已取消的 SDK 错误。
    static func cancelledError() -> XmaxError {
        XmaxError(
            code: .cancelled,
            message: "Realtime operation was cancelled"
        )
    }
}
