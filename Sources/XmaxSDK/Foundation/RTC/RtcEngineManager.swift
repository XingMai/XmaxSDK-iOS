//
//  RtcEngineManager.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 表示对进程级 RTC 引擎的独占使用权。
final class RtcEngineLease: @unchecked Sendable {

    // RTC 资源
    let engine: any RtcPlatform


    // 运行标识
    let id = UUID()

    /// 创建持有指定引擎的独占租约。
    ///
    /// - Parameter engine: 租约持有的平台引擎。
    fileprivate init(engine: any RtcPlatform) {
        self.engine = engine
    }
}

/// 管理进程级 RTC 引擎的独占创建、排队租用和销毁。
actor RtcEngineManager {
    /// 根据 RTC 应用标识创建平台引擎，失败时返回空值。
    typealias EngineFactory = @Sendable (String) -> (any RtcPlatform)?
    /// 销毁当前进程级 RTC 平台引擎。
    typealias EngineDestructor = @Sendable () -> Void


    // 共享实例
    static let shared = RtcEngineManager()


    // RTC 配置
    static let defaultAppID = "5588dfe2e7874bd08ea28f4968ec2d40"


    // 依赖
    private let appID: String
    private let makeEngine: EngineFactory
    private let destroyEngine: EngineDestructor


    // RTC 资源
    private var activeLease: RtcEngineLease?


    // 运行状态
    private var requests: [Request] = []

    /// 配置引擎创建、销毁及租约排队管理。
    ///
    /// - Parameters:
    ///   - appID: RTC 应用标识。
    ///   - makeEngine: 根据应用标识创建引擎的工厂。
    ///   - destroyEngine: 销毁当前平台引擎的操作。
    init(
        appID: String = RtcEngineManager.defaultAppID,
        makeEngine: @escaping EngineFactory = AgoraRtcPlatform.create,
        destroyEngine: @escaping EngineDestructor = AgoraRtcPlatform.destroyEngine
    ) {
        self.appID = appID
        self.makeEngine = makeEngine
        self.destroyEngine = destroyEngine
    }

    /// 等待并获取一份独占 RTC 引擎租约。
    ///
    /// - Returns: 当前调用持有的独占租约。
    /// - Throws: 等待取消、应用标识无效或引擎创建失败时抛出错误。
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

    /// 释放有效租约并将引擎独占权交给下一个等待者。
    ///
    /// - Parameter lease: 需要归还的租约；失效租约不影响当前引擎。
    func release(_ lease: RtcEngineLease) {
        guard activeLease?.id == lease.id else {
            return
        }

        releaseActiveLease(lease)
    }

    /// 创建平台引擎并包装为独占租约。
    ///
    /// - Returns: 新创建的引擎租约。
    /// - Throws: 应用标识为空或引擎创建失败时抛出错误。
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

    /// 销毁指定有效租约的引擎，并继续处理等待队列。
    ///
    /// - Parameter lease: 需要释放的租约。
    private func releaseActiveLease(_ lease: RtcEngineLease) {
        guard activeLease == nil || activeLease?.id == lease.id else {
            return
        }

        activeLease = nil
        destroyEngine()
        fulfillNextRequest()
    }

    /// 按入队顺序向等待者交付引擎租约。
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

    /// 将租约请求加入等待队列。
    ///
    /// - Parameter id: 用于定位及取消请求的唯一标识。
    /// - Returns: 后续交付的独占引擎租约。
    /// - Throws: 请求取消或引擎创建失败时抛出错误。
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

    /// 取消仍在队列中的租约请求。
    ///
    /// - Parameter id: 待取消的请求标识。
    private func cancelRequest(id: UUID) {
        guard let index = requests.firstIndex(where: { $0.id == id }) else {
            return
        }

        let request = requests.remove(at: index)
        request.continuation.resume(throwing: CancellationError())
    }

}

private extension RtcEngineManager {

    /// 保存一项等待 RTC Engine 独占权的请求。
    struct Request {

        // 请求标识
        let id: UUID


        // 租约交付
        let continuation: CheckedContinuation<RtcEngineLease, any Error>
    }
}
