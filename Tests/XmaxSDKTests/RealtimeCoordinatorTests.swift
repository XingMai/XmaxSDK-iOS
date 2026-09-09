import XCTest
@testable import XmaxSDK

@MainActor
final class RealtimeCoordinatorTests: XCTestCase {
    func testCancellingConfigurationDoesNotStopGeneration() async throws {
        for kind: RealtimeCoordinator.OperationKind in [.configuration, .generation] {
            try await assertCancellingUpdatePreservesGeneration(kind: kind)
        }
    }

    private func assertCancellingUpdatePreservesGeneration(
        kind: RealtimeCoordinator.OperationKind
    ) async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        let state = RealtimeState(connectionState: .generating, sessionID: "session", taskID: "task")
        try await coordinator.run(kind: .generation, failureScope: .generation) { token in
            try await coordinator.commit(state, token: token)
        }
        let changing = Task {
            try await coordinator.run(kind: kind, failureScope: .generation) { _ in
                await probe.markOperationStarted()
                try await Task.sleep(nanoseconds: 30000000000)
            }
        }
        await waitUntil { await probe.operationStarted }
        changing.cancel()
        do {
            try await changing.value
            XCTFail("Expected configuration cancellation")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
        }
        let current = await coordinator.currentState
        let cleanup = await probe.cleanupScopes
        XCTAssertEqual(current, state)
        XCTAssertTrue(cleanup.isEmpty)
        try await coordinator.run(kind: .configuration, failureScope: .generation) { _ in }
    }

    func testDisconnectWaitsForConfigurationBeforeCleaningConnection() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        let events = RealtimeCoordinatorEventRecorder()
        let changing = Task {
            try await coordinator.run(kind: .configuration, failureScope: .generation) { _ in
                await probe.markOperationStarted()
                do {
                    try await Task.sleep(nanoseconds: 30000000000)
                } catch {
                    events.append("configuration-finished")
                    throw error
                }
            }
        }
        await waitUntil { await probe.operationStarted }
        await coordinator.disconnect()
        XCTAssertEqual(events.values, ["configuration-finished"])
        let cleanup = await probe.cleanupScopes
        XCTAssertEqual(cleanup, [.connection])
        _ = try? await changing.value
    }

    func testTerminationUnregistersOperationBeforeDisconnectedNotification() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        let running = Task {
            try await coordinator.run(kind: .generation, failureScope: .connection) { _ in
                await probe.markOperationStarted()
                try await Task.sleep(nanoseconds: 30000000000)
            }
        }
        await waitUntil { await probe.operationStarted }
        var restarted: Task<Bool, Never>?
        await coordinator.setStateListener { state in
            guard state.connectionState == .disconnected else { return }
            let gate = DispatchSemaphore(value: 0)
            restarted = Task.detached {
                defer { gate.signal() }
                do {
                    try await coordinator.run(kind: .connection, failureScope: .connection) { _ in }
                    return true
                } catch {
                    return false
                }
            }
            XCTAssertEqual(gate.wait(timeout: .now() + 3), .success)
        }

        await coordinator.disconnect()
        let succeeded = await restarted?.value ?? false
        XCTAssertTrue(succeeded)
        _ = try? await running.value
    }

    func testDisconnectCancelsOperationBeforeConnectingStateIsCommitted()
        async throws {
        for initialState: RealtimeConnectionState in [.idle, .disconnected] {
            for kind: RealtimeCoordinator.OperationKind in [.connection, .generation] {
                let probe = RealtimeCoordinatorProbe()
                let coordinator = makeCoordinator(probe: probe)
                if initialState == .disconnected {
                    await coordinator.terminate(.connection, finalState: .disconnected)
                }
                let initialCleanupCount = await probe.cleanupScopes.count
                let runningTask = Task {
                    try await coordinator.run(
                        kind: kind,
                        failureScope: .connection
                    ) { token in
                        await probe.markOperationStarted()
                        try await Task.sleep(nanoseconds: 30_000_000_000)
                        try await coordinator.commit(
                            RealtimeState(connectionState: .connecting),
                            token: token
                        )
                    }
                }
                await waitUntil { await probe.operationStarted }
                let beforeDisconnect = await coordinator.currentState
                XCTAssertEqual(beforeDisconnect.connectionState, initialState)

                await coordinator.disconnect()

                do {
                    try await runningTask.value
                    XCTFail("Expected pending connection or generation to be cancelled")
                } catch {
                    XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
                }
                let state = await coordinator.currentState
                let cleanupScopes = await probe.cleanupScopes
                XCTAssertEqual(state.connectionState, .disconnected)
                XCTAssertEqual(
                    Array(cleanupScopes.dropFirst(initialCleanupCount)),
                    [.connection]
                )
            }
        }
    }

    func testDisconnectWithoutConnectionDoesNotCleanUpAgain() async {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)

        await coordinator.disconnect()
        let idleState = await coordinator.currentState
        let idleCleanupScopes = await probe.cleanupScopes
        XCTAssertEqual(idleState.connectionState, .idle)
        XCTAssertTrue(idleCleanupScopes.isEmpty)

        await coordinator.terminate(.connection, finalState: .disconnected)
        await coordinator.disconnect()
        let disconnectedState = await coordinator.currentState
        let cleanupScopes = await probe.cleanupScopes
        XCTAssertEqual(disconnectedState.connectionState, .disconnected)
        XCTAssertEqual(cleanupScopes, [.connection])
    }

    func testDisconnectDoesNotCancelLocalMediaPreparation() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        try await coordinator.run(kind: .media, failureScope: .all) { token in
            await coordinator.disconnect()
            try token.ensureCurrent()
        }
        let state = await coordinator.currentState
        let cleanupScopes = await probe.cleanupScopes
        XCTAssertEqual(state.connectionState, .idle)
        XCTAssertTrue(cleanupScopes.isEmpty)
    }

    func testCloseDuringDisconnectedNotificationCompletesFullCleanup()
        async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        try await coordinator.run(kind: .connection, failureScope: .connection) { token in
            try await coordinator.commit(
                RealtimeState(connectionState: .connected),
                token: token
            )
        }

        var closeTask: Task<Bool, Never>?
        await coordinator.setStateListener { state in
            guard state.connectionState == .disconnected,
                  closeTask == nil else {
                return
            }

            // 固定交错顺序：状态通知返回前，确保另一个关闭请求已经进入。
            let callbackGate = DispatchSemaphore(value: 0)
            closeTask = Task.detached {
                let task = Task {
                    await coordinator.terminate(.all, finalState: .disconnected)
                }
                let deadline = DispatchTime.now() + 2
                var closeStarted = false
                while DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds {
                    let current = await coordinator.currentState
                    let scopes = await probe.cleanupScopes
                    if current.connectionState == .disconnecting || scopes.contains(.all) {
                        closeStarted = true
                        break
                    }
                    await Task.yield()
                }
                callbackGate.signal()
                await task.value
                return closeStarted
            }
            XCTAssertEqual(callbackGate.wait(timeout: .now() + 3), .success)
        }

        await coordinator.disconnect()
        let closeStarted = await closeTask?.value ?? false
        let scopes = await probe.cleanupScopes
        let state = await coordinator.currentState
        XCTAssertTrue(closeStarted)
        XCTAssertEqual(scopes, [.connection, .all])
        XCTAssertEqual(state.connectionState, .disconnected)
    }

    func testRejectsOverlappingOperations() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        let runningTask = Task {
            try await coordinator.run(
                kind: .connection,
                failureScope: .connection
            ) { _ in
                await probe.markOperationStarted()
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return 1
            }
        }
        await waitUntil { await probe.operationStarted }

        do {
            _ = try await coordinator.run(
                kind: .generation,
                failureScope: .generation
            ) { _ in
                2
            }
            XCTFail("Expected overlapping operation to be rejected")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Another realtime operation is in progress; " +
                        "wait for it to finish"
                )
            )
        }

        await coordinator.terminate(
            .connection,
            finalState: .disconnected
        )
        _ = try? await runningTask.value

        let cleanupScopes = await probe.cleanupScopes
        let state = await coordinator.currentState
        XCTAssertEqual(cleanupScopes, [.connection])
        XCTAssertEqual(
            state.connectionState,
            .disconnected
        )
    }

    func testTerminationInvalidatesPendingStateCommit() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        let runningTask = Task {
            try await coordinator.run(
                kind: .connection,
                failureScope: .connection
            ) { token in
                try await coordinator.commit(
                    RealtimeState(connectionState: .connecting),
                    token: token
                )
                await probe.markOperationStarted()
                try await Task.sleep(nanoseconds: 30_000_000_000)
                try await coordinator.commit(
                    RealtimeState(connectionState: .connected),
                    token: token
                )
            }
        }
        await waitUntil { await probe.operationStarted }

        await coordinator.terminate(
            .connection,
            finalState: .disconnected
        )
        _ = try? await runningTask.value

        let state = await coordinator.currentState
        XCTAssertEqual(
            state.connectionState,
            .disconnected
        )
    }

    func testFatalErrorIsReportedAfterCleanup() async {
        let events = RealtimeCoordinatorEventRecorder()
        let errorHandler = RealtimeErrorHandler()
        errorHandler.setListener { error in
            events.append("callback:\(error.code.rawValue)")
        }
        let coordinator = RealtimeCoordinator(
            errorHandler: errorHandler,
            cleanup: { scope, _ in
                events.append("cleanup:\(scope.rawValue)")
                return RealtimeCoordinator.CleanupResult()
            }
        )

        do {
            let _: Void = try await coordinator.run(
                kind: .generation,
                failureScope: .generation
            ) { _ in
                throw XmaxError(
                    code: .rtcError,
                    message: "fatal"
                )
            }
            XCTFail("Expected fatal operation to fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .rtcError)
        }

        XCTAssertEqual(
            events.values,
            ["cleanup:0", "callback:RTC_ERROR"]
        )
        let state = await coordinator.currentState
        XCTAssertEqual(
            state.connectionState,
            .error
        )
    }

    func testOperationCanNarrowFailureCleanupScope() async {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)

        do {
            let _: Void = try await coordinator.run(
                kind: .generation,
                failureScope: .connection
            ) { token in
                token.setFailureScope(.generation)
                throw XmaxError(
                    code: .rtcError,
                    message: "generation failed"
                )
            }
            XCTFail("Expected generation to fail")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .rtcError)
        }

        let cleanupScopes = await probe.cleanupScopes
        XCTAssertEqual(cleanupScopes, [.generation])
    }

    func testBackgroundFatalErrorInterruptsActiveOperation() async {
        let probe = RealtimeCoordinatorProbe()
        let receivedError = RealtimeCoordinatorErrorRecorder()
        let errorHandler = RealtimeErrorHandler()
        errorHandler.setListener { error in
            receivedError.record(error)
        }
        let coordinator = RealtimeCoordinator(
            errorHandler: errorHandler,
            cleanup: { scope, _ in
                await probe.recordCleanup(scope)
                return RealtimeCoordinator.CleanupResult()
            }
        )
        let runningTask = Task {
            try await coordinator.run(
                kind: .connection,
                failureScope: .connection
            ) { _ in
                await probe.markOperationStarted()
                try await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        await waitUntil { await probe.operationStarted }
        let expectedError = XmaxError(
            code: .sessionError,
            message: "session closed",
            severity: .fatal
        )

        await coordinator.terminate(
            with: expectedError,
            target: .connection
        )

        do {
            try await runningTask.value
            XCTFail("Expected active operation to fail")
        } catch {
            XCTAssertEqual(error as? XmaxError, expectedError)
        }
        let cleanupScopes = await probe.cleanupScopes
        XCTAssertEqual(cleanupScopes, [.connection])
        XCTAssertEqual(receivedError.value, expectedError)
    }
}

private extension RealtimeCoordinatorTests {
    func makeCoordinator(
        probe: RealtimeCoordinatorProbe
    ) -> RealtimeCoordinator {
        RealtimeCoordinator(
            errorHandler: RealtimeErrorHandler(),
            cleanup: { scope, _ in
                await probe.recordCleanup(scope)
                return RealtimeCoordinator.CleanupResult()
            }
        )
    }

    func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<1_000 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for asynchronous condition")
    }
}

private actor RealtimeCoordinatorProbe {

    // 操作状态
    private(set) var operationStarted = false

    // 清理记录
    private(set) var cleanupScopes: [
        RealtimeCoordinator.TerminationScope
    ] = []

    func markOperationStarted() {
        operationStarted = true
    }

    func recordCleanup(
        _ scope: RealtimeCoordinator.TerminationScope
    ) {
        cleanupScopes.append(scope)
    }
}

private final class RealtimeCoordinatorEventRecorder: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var events: [String] = []

    var values: [String] {
        lock.withLock { events }
    }

    func append(_ event: String) {
        lock.withLock {
            events.append(event)
        }
    }
}

private final class RealtimeCoordinatorErrorRecorder: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var error: XmaxError?

    var value: XmaxError? {
        lock.withLock { error }
    }

    func record(_ error: XmaxError) {
        lock.withLock {
            self.error = error
        }
    }
}
