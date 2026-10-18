//
//  RealtimeErrorHandler.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 记录实时错误，并将后台故障交给 Coordinator 统一结束生命周期。
final class RealtimeErrorHandler: @unchecked Sendable {

    /// 接收运行中错误、清理范围及有效性检查回调，完成相应生命周期的终止。
    typealias FailureHandler = @Sendable (
        XmaxError, RealtimeCoordinator.TerminationScope, @escaping @Sendable () -> Bool
    ) async -> Void

    /// 并发控制
    private let lock = NSLock()

    /// 故障生命周期
    private var mediaRevision = UUID()
    private var connectionRevision = UUID()

    /// 内部故障处理
    private var failureHandler: FailureHandler?

    /// 设置运行中故障的终止处理回调。
    ///
    /// - Parameter handler: 接收错误、清理范围和生命周期有效性检查的回调。
    func setFailureHandler(_ handler: @escaping FailureHandler) {
        lock.withLock { failureHandler = handler }
    }

    /// 使已结束生命周期内尚未处理的故障失效。
    ///
    /// - Parameter target: 已清理的资源范围；连接清理仅使连接故障失效，完整清理同时使媒体故障失效。
    func invalidatePendingFailures(target: RealtimeCoordinator.TerminationScope = .all) {
        lock.withLock {
            connectionRevision = UUID()
            if target == .all { mediaRevision = UUID() }
        }
    }

    /// 异步转交运行中故障；未指定清理范围或处理器时仅记录错误日志。
    ///
    /// - Parameters:
    ///   - error: 需要处理的运行中错误。
    ///   - target: 错误影响的资源范围；传入 `nil` 时不终止生命周期。
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

    /// 输出实时错误的错误码和错误信息日志。
    ///
    /// - Parameter error: 需要记录的 SDK 错误。
    func report(_ error: XmaxError) async {
        XmaxLogger.realtime.error(
            message: "实时服务错误 (Realtime Service Error)\n" +
                "├─ \(XmaxLogger.localized("错误码：", "Error Code: "))\(error.code.rawValue)\n" +
                "└─ \(XmaxLogger.localized("信息：", "Message: "))\(error.message)"
        )
    }
}
