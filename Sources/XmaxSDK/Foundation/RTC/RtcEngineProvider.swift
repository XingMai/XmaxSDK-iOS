import Foundation
@preconcurrency import VolcEngineRTC

/// 表示对进程级火山 RTC Engine 的独占使用权。
final class RtcEngineLease: @unchecked Sendable {

    // RTC 资源
    let engine: ByteRTCEngine

    // 运行标识
    let id = UUID()

    fileprivate init(engine: ByteRTCEngine) {
        self.engine = engine
    }
}

/// 管理进程级火山 RTC Engine 的独占创建、排队租用和销毁。
actor RtcEngineProvider {
    typealias EngineFactory = @Sendable (String) -> ByteRTCEngine?
    typealias EngineDestructor = @Sendable () -> Void

    // 共享实例
    static let shared = RtcEngineProvider()

    // RTC 配置
    private static let defaultAppID = "69a177e226e9b90176a86b96"

    // 依赖
    private let appID: String
    private let makeEngine: EngineFactory
    private let destroyEngine: EngineDestructor

    // RTC 资源
    private var activeLease: RtcEngineLease?

    // 运行状态
    private var requests: [Request] = []

    init(
        appID: String = RtcEngineProvider.defaultAppID,
        makeEngine: @escaping EngineFactory = RtcEngineProvider.createEngine,
        destroyEngine: @escaping EngineDestructor = RtcEngineProvider.destroyEngine
    ) {
        self.appID = appID
        self.makeEngine = makeEngine
        self.destroyEngine = destroyEngine
    }

    /// 等待并获取一份独占 RTC Engine 租约。
    func acquire() async throws -> RtcEngineLease {
        try Task.checkCancellation()

        if activeLease == nil, requests.isEmpty {
            let lease = try createLease()
            if Task.isCancelled {
                releaseActiveLease(lease)
                throw CancellationError()
            }

            activeLease = lease
            return lease
        }

        let requestID = UUID()
        let lease: RtcEngineLease = try await withTaskCancellationHandler(
            operation: {
                try await self.enqueueRequest(id: requestID)
            },
            onCancel: {
                Task {
                    await self.cancelRequest(id: requestID)
                }
            }
        )

        if Task.isCancelled {
            releaseActiveLease(lease)
            throw CancellationError()
        }

        return lease
    }

    /// 释放有效租约、销毁 Engine，并把独占权交给下一个等待者。
    func release(_ lease: RtcEngineLease) {
        guard activeLease?.id == lease.id else {
            return
        }

        releaseActiveLease(lease)
    }

    private func createLease() throws -> RtcEngineLease {
        let normalizedAppID = appID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedAppID.isEmpty else {
            throw XmaxError(
                code: .rtcError,
                message: "RTC App ID cannot be empty"
            )
        }
        guard let engine = makeEngine(normalizedAppID) else {
            throw XmaxError(
                code: .rtcError,
                message: "Failed to create RTC Engine"
            )
        }

        return RtcEngineLease(engine: engine)
    }

    private func releaseActiveLease(_ lease: RtcEngineLease) {
        guard activeLease == nil || activeLease?.id == lease.id else {
            return
        }

        activeLease = nil
        destroyEngine()
        fulfillNextRequest()
    }

    private func fulfillNextRequest() {
        while activeLease == nil, !requests.isEmpty {
            let request = requests.removeFirst()

            do {
                let lease = try createLease()
                activeLease = lease
                request.continuation.resume(returning: lease)
            } catch {
                request.continuation.resume(throwing: error)
            }
        }
    }

    private func enqueueRequest(id: UUID) async throws -> RtcEngineLease {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<RtcEngineLease, any Error>) in
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
                return
            }

            requests.append(
                Request(
                    id: id,
                    continuation: continuation
                )
            )
        }
    }

    private func cancelRequest(id: UUID) {
        guard let index = requests.firstIndex(where: { $0.id == id }) else {
            return
        }

        let request = requests.remove(at: index)
        request.continuation.resume(throwing: CancellationError())
    }

    private static func createEngine(appID: String) -> ByteRTCEngine? {
        let configuration = ByteRTCEngineConfig()
        configuration.appID = appID
        configuration.isGameScene = false
        configuration.parameters = [:]

        return ByteRTCEngine.createRTCEngine(
            configuration,
            delegate: nil
        )
    }

    private static func destroyEngine() {
        ByteRTCEngine.destroyRTCEngine()
    }
}

private extension RtcEngineProvider {

    /// 保存一项等待 RTC Engine 独占权的请求。
    struct Request {
        let id: UUID
        let continuation: CheckedContinuation<RtcEngineLease, any Error>
    }
}
