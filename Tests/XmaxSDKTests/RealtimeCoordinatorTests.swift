import XCTest
@testable import XmaxSDK

@MainActor
final class RealtimeCoordinatorTests: XCTestCase {
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
