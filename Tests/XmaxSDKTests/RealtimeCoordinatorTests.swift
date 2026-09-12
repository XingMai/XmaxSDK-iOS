import XCTest
@testable import XmaxSDK

@MainActor
final class RealtimeCoordinatorTests: XCTestCase {
    func testPreviewReadyOnlyAdvancesCurrentPreparation() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        try await coordinator.run(kind: .media) { token in
            try await coordinator.commit(RealtimeState(connectionState: .preparing), token: token)
        }

        await coordinator.localPreviewDidBecomeReady(isCurrent: { false })
        let staleState = await coordinator.currentState
        XCTAssertEqual(staleState.connectionState, .preparing)

        await coordinator.localPreviewDidBecomeReady(isCurrent: { true })
        let readyState = await coordinator.currentState
        XCTAssertEqual(readyState.connectionState, .ready)

        try await coordinator.run(kind: .connection) { token in
            try await coordinator.commit(RealtimeState(connectionState: .connecting), token: token)
        }
        await coordinator.localPreviewDidBecomeReady(isCurrent: { true })
        let connectingState = await coordinator.currentState
        XCTAssertEqual(connectingState.connectionState, .connecting)

        await coordinator.terminate(.all)
        await coordinator.localPreviewDidBecomeReady(isCurrent: { false })
        let closedState = await coordinator.currentState
        XCTAssertEqual(closedState.connectionState, .idle)
    }

    func testNewGenerationWaitsForCancelledDisconnectTaskToFinishCleanup() async throws {
        let gate = LifecycleFailureGate()
        let events = RealtimeCoordinatorEventRecorder()
        let coordinator = RealtimeCoordinator(
            errorHandler: RealtimeErrorHandler(),
            cleanup: { _, _ in
                await gate.wait()
                events.append("cleanup-finished")
                return .init(hasLocalMedia: true)
            }
        )
        try await coordinator.run(kind: .generation) { token in
            try await coordinator.commit(RealtimeState(connectionState: .generating), token: token)
        }

        let disconnecting = Task { await coordinator.disconnect() }
        await waitUntil { await gate.isWaiting }
        disconnecting.cancel()
        let nextGeneration = Task {
            await disconnecting.value
            try await coordinator.run(kind: .generation) { token in
                events.append("next-generation-started")
                try await coordinator.commit(RealtimeState(connectionState: .generating), token: token)
            }
        }

        let closingState = await coordinator.currentState
        XCTAssertEqual(closingState.connectionState, .disconnecting)
        XCTAssertTrue(events.values.isEmpty)
        await gate.release()
        try await nextGeneration.value

        let finalState = await coordinator.currentState
        XCTAssertEqual(finalState, RealtimeState(connectionState: .generating))
        XCTAssertEqual(events.values, ["cleanup-finished", "next-generation-started"])
    }

    func testMediaPreparationFailureReturnsToIdleWithoutFailureReason() async {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        var states: [RealtimeState] = []
        await coordinator.setStateListener { states.append($0) }

        do {
            try await coordinator.run(kind: .media) { token in
                try await coordinator.commit(RealtimeState(connectionState: .preparing), token: token)
                throw XmaxError(code: .invalidConfiguration, message: "Invalid media")
            }
            XCTFail("Expected creation failure")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
        }

        XCTAssertEqual(states.map(\.connectionState), [.idle, .preparing, .idle])
        XCTAssertTrue(states.allSatisfy { $0.reason == nil })
        let cleanup = await probe.cleanupScopes
        XCTAssertTrue(cleanup.isEmpty)
    }

    func testMediaPreparationCancellationAndCloseReturnToIdle() async {
        for closes in [false, true] {
            let probe = RealtimeCoordinatorProbe()
            let coordinator = makeCoordinator(probe: probe)
            let preparing = Task {
                try await coordinator.run(kind: .media) { token in
                    try await coordinator.commit(RealtimeState(connectionState: .preparing), token: token)
                    await probe.markOperationStarted()
                    try await Task.sleep(nanoseconds: 30000000000)
                    try await coordinator.commit(RealtimeState(connectionState: .ready), token: token)
                }
            }
            await waitUntil { await probe.operationStarted }

            if closes {
                await coordinator.terminate(.all)
            } else {
                preparing.cancel()
            }
            do {
                try await preparing.value
                XCTFail("Expected preparation cancellation")
            } catch {
                XCTAssertEqual((error as? XmaxError)?.code, .cancelled)
            }

            let state = await coordinator.currentState
            let cleanup = await probe.cleanupScopes
            XCTAssertEqual(state.connectionState, .idle)
            XCTAssertEqual(state.reason, closes ? .normal : nil)
            XCTAssertEqual(cleanup, closes ? [.all] : [])
        }
    }

    func testConnectionCleanupKeepsQueuedMediaFailureValidButCloseInvalidatesIt() async {
        for target: RealtimeCoordinator.TerminationScope in [.connection, .all] {
            let handler = RealtimeErrorHandler()
            let gate = LifecycleFailureGate()
            let delivered = expectation(description: "Queued failure processed")
            let result = RealtimeCoordinatorEventRecorder()
            handler.setFailureHandler { _, _, isCurrent in
                await gate.wait()
                result.append(isCurrent() ? "valid" : "stale")
                delivered.fulfill()
            }
            handler.forward(XmaxError(code: .mediaError, message: "Capture stopped"), target: .all)
            await waitUntil { await gate.isWaiting }
            handler.invalidatePendingFailures(target: target)
            await gate.release()
            await fulfillment(of: [delivered], timeout: 2)
            XCTAssertEqual(result.values, [target == .all ? "stale" : "valid"])
        }
    }


    func testPreflightFailureDoesNotChangeReadyStateOrCleanUp() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        try await coordinator.run(kind: .media) { token in
            try await coordinator.commit(RealtimeState(connectionState: .ready), token: token)
        }
        do {
            try await coordinator.run(kind: .generation) { _ in
                throw XmaxError(code: .invalidConfiguration, message: "Missing context")
            }
            XCTFail("Expected preflight failure")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
        }
        let state = await coordinator.currentState
        let scopes = await probe.cleanupScopes
        XCTAssertEqual(state, RealtimeState(connectionState: .ready))
        XCTAssertTrue(scopes.isEmpty)
    }

    func testStartupFailureClosesConnectionAndPreservesReadyMedia() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = RealtimeCoordinator(
            errorHandler: RealtimeErrorHandler(),
            cleanup: { scope, _ in
                await probe.recordCleanup(scope)
                return .init(sessionID: "session", hasLocalMedia: true)
            }
        )
        let failure = XmaxError(code: .timeout, message: "First frame timed out")
        do {
            try await coordinator.run(kind: .generation) { token in
                token.setFailureScope(.connection)
                try await coordinator.commit(
                    RealtimeState(connectionState: .connected, sessionID: "session"), token: token
                )
                throw failure
            }
        } catch {
            XCTAssertEqual(error as? XmaxError, failure)
        }
        let state = await coordinator.currentState
        let scopes = await probe.cleanupScopes
        XCTAssertEqual(state.connectionState, .ready)
        XCTAssertEqual(state.reason, .failure(failure))
        XCTAssertEqual(scopes, [.connection])
    }

    func testMediaTerminationWithoutConnectionReportsIdleFailure() async {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        let failure = XmaxError(code: .mediaError, message: "Decoder stopped")
        await coordinator.terminate(with: failure, target: .all)
        let state = await coordinator.currentState
        let scopes = await probe.cleanupScopes
        XCTAssertEqual(state.connectionState, .idle)
        XCTAssertEqual(state.reason, .failure(failure))
        XCTAssertEqual(scopes, [.all])
    }

    func testConfigurationFailurePreservesGeneratingEvenWithFatalErrorCode() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        let original = RealtimeState(connectionState: .generating, sessionID: "session", taskID: "task")
        try await coordinator.run(kind: .generation) { token in
            try await coordinator.commit(original, token: token)
        }
        do {
            try await coordinator.run(kind: .generation, failureScope: .connection) { _ in
                throw XmaxError(code: .rtcError, message: "Condition send failed")
            }
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .rtcError)
        }
        let state = await coordinator.currentState
        let scopes = await probe.cleanupScopes
        XCTAssertEqual(state, original)
        XCTAssertTrue(scopes.isEmpty)
    }

    func testStaleBackgroundFailureDoesNotCloseCurrentConnection() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        let original = RealtimeState(connectionState: .connected, sessionID: "new")
        try await coordinator.run(kind: .connection) { token in
            try await coordinator.commit(original, token: token)
        }
        await coordinator.terminate(
            with: XmaxError(code: .mediaError, message: "Old source failed"),
            target: .all,
            isCurrent: { false }
        )
        let state = await coordinator.currentState
        let scopes = await probe.cleanupScopes
        XCTAssertEqual(state, original)
        XCTAssertTrue(scopes.isEmpty)
    }

    func testOrientationDisconnectReturnsReadyAndNextConnectClearsReason() async throws {
        let coordinator = RealtimeCoordinator(
            errorHandler: RealtimeErrorHandler(), cleanup: { _, _ in .init(hasLocalMedia: true) }
        )
        try await coordinator.run(kind: .connection) { token in
            try await coordinator.commit(RealtimeState(connectionState: .connected), token: token)
        }
        await coordinator.disconnect(reason: .orientationChanged)
        let ready = await coordinator.currentState
        XCTAssertEqual(ready.connectionState, .ready)
        XCTAssertEqual(ready.reason, .orientationChanged)
        try await coordinator.run(kind: .connection) { token in
            try await coordinator.commit(RealtimeState(connectionState: .connecting), token: token)
        }
        let connecting = await coordinator.currentState
        XCTAssertNil(connecting.reason)
    }

    func testNormalTerminationReportsReasonAndReconnectClearsIt() async throws {
        for scope: RealtimeCoordinator.TerminationScope in [.connection, .all] {
            let coordinator = makeCoordinator(probe: RealtimeCoordinatorProbe())
            var states: [RealtimeState] = []
            await coordinator.setStateListener { states.append($0) }
            try await coordinator.run(kind: .connection, failureScope: .connection) { token in
                try await coordinator.commit(
                    RealtimeState(connectionState: .connected, sessionID: "session"),
                    token: token
                )
            }

            if scope == .connection {
                await coordinator.disconnect()
            } else {
                await coordinator.terminate(.all)
            }

            XCTAssertEqual(states.map(\.connectionState), [.idle, .connected, .disconnecting, .idle])
            XCTAssertEqual(states.map(\.reason), [nil, nil, nil, .normal])
            XCTAssertEqual(states.last?.reason, .normal)

            try await coordinator.run(kind: .connection, failureScope: .connection) { token in
                try await coordinator.commit(RealtimeState(connectionState: .connecting), token: token)
            }
            let state = await coordinator.currentState
            XCTAssertNil(state.reason)
        }
    }

    func testConnectionFailureDoesNotReportNormalDisconnection() async {
        let coordinator = makeCoordinator(probe: RealtimeCoordinatorProbe())
        var states: [RealtimeState] = []
        await coordinator.setStateListener { states.append($0) }
        do {
            try await coordinator.run(kind: .connection, failureScope: .connection) { _ in
                throw XmaxError(code: .rtcError, message: "Connection failed")
            }
            XCTFail("Expected connection failure")
        } catch {
            XCTAssertEqual((error as? XmaxError)?.code, .rtcError)
        }
        XCTAssertEqual(states.map(\.connectionState), [.idle, .disconnecting, .idle])
        XCTAssertEqual(states.last?.reason, .failure(XmaxError(code: .rtcError, message: "Connection failed")))
    }

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
        try await coordinator.run(kind: .generation, failureScope: .connection) { token in
            try await coordinator.commit(state, token: token)
        }
        let changing = Task {
            try await coordinator.run(kind: kind, failureScope: .connection) { _ in
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
        try await coordinator.run(kind: .configuration, failureScope: .connection) { _ in }
    }

    func testDisconnectWaitsForConfigurationBeforeCleaningConnection() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        let events = RealtimeCoordinatorEventRecorder()
        let changing = Task {
            try await coordinator.run(kind: .configuration, failureScope: .connection) { _ in
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
            guard state.connectionState == .idle else { return }
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
        for initialState: RealtimeConnectionState in [.idle, .ready] {
            for kind: RealtimeCoordinator.OperationKind in [.connection, .generation] {
                let probe = RealtimeCoordinatorProbe()
                let coordinator = makeCoordinator(probe: probe)
                if initialState == .ready {
                    try await coordinator.run(kind: .media) { token in
                        try await coordinator.commit(RealtimeState(connectionState: .ready), token: token)
                    }
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
                XCTAssertEqual(state.connectionState, .idle)
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

        await coordinator.terminate(.connection)
        await coordinator.disconnect()
        let disconnectedState = await coordinator.currentState
        let cleanupScopes = await probe.cleanupScopes
        XCTAssertEqual(disconnectedState.connectionState, .idle)
        XCTAssertEqual(cleanupScopes, [.connection])
    }

    func testDisconnectDoesNotCancelLocalMediaPreparation() async throws {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)
        try await coordinator.run(kind: .media, failureScope: .all) { token in
            try await coordinator.commit(RealtimeState(connectionState: .preparing), token: token)
            await coordinator.disconnect()
            try token.ensureCurrent()
            let state = await coordinator.currentState
            XCTAssertEqual(state.connectionState, .preparing)
            try await coordinator.commit(RealtimeState(connectionState: .ready), token: token)
        }
        let state = await coordinator.currentState
        let cleanupScopes = await probe.cleanupScopes
        XCTAssertEqual(state.connectionState, .ready)
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
            guard state.connectionState == .idle,
                  closeTask == nil else {
                return
            }

            // 固定交错顺序：状态通知返回前，确保另一个关闭请求已经进入。
            let callbackGate = DispatchSemaphore(value: 0)
            closeTask = Task.detached {
                let task = Task {
                    await coordinator.terminate(.all)
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
        XCTAssertEqual(state.connectionState, .idle)
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
                failureScope: .connection
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
            reason: .normal
        )
        _ = try? await runningTask.value

        let cleanupScopes = await probe.cleanupScopes
        let state = await coordinator.currentState
        XCTAssertEqual(cleanupScopes, [.connection])
        XCTAssertEqual(
            state.connectionState,
            .idle
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
            reason: .normal
        )
        _ = try? await runningTask.value

        let state = await coordinator.currentState
        XCTAssertEqual(
            state.connectionState,
            .idle
        )
    }

    func testFatalErrorIsReportedAfterCleanup() async {
        let events = RealtimeCoordinatorEventRecorder()
        let errorHandler = RealtimeErrorHandler()
        let coordinator = RealtimeCoordinator(
            errorHandler: errorHandler,
            cleanup: { scope, _ in
                events.append("cleanup:\(scope.rawValue)")
                return RealtimeCoordinator.CleanupResult()
            }
        )

        await coordinator.setStateListener { state in
            if case .failure(let error) = state.reason { events.append("callback:\(error.code.rawValue)") }
        }
        do {
            let _: Void = try await coordinator.run(
                kind: .generation,
                failureScope: .connection
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
            .idle
        )
    }

    func testOperationCanArmFailureCleanupScope() async {
        let probe = RealtimeCoordinatorProbe()
        let coordinator = makeCoordinator(probe: probe)

        do {
            let _: Void = try await coordinator.run(
                kind: .generation
            ) { token in
                token.setFailureScope(.connection)
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
        XCTAssertEqual(cleanupScopes, [.connection])
    }

    func testBackgroundFatalErrorInterruptsActiveOperation() async {
        let probe = RealtimeCoordinatorProbe()
        let receivedError = RealtimeCoordinatorErrorRecorder()
        let errorHandler = RealtimeErrorHandler()
        let coordinator = RealtimeCoordinator(
            errorHandler: errorHandler,
            cleanup: { scope, _ in
                await probe.recordCleanup(scope)
                return RealtimeCoordinator.CleanupResult()
            }
        )
        await coordinator.setStateListener { state in
            if case .failure(let error) = state.reason { receivedError.record(error) }
        }
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

private actor LifecycleFailureGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
