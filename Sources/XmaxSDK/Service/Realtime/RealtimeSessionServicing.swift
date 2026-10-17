//
//  RealtimeSessionServicing.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 定义实时会话 API 与心跳生命周期能力。
protocol RealtimeSessionServicing: Sendable {

    /// 创建指定模型的实时会话，解析用于 RTC 进房的连接信息。
    ///
    /// - Parameter model: 本次实时生成使用的模型。
    /// - Returns: 服务端创建的会话及其 RTC 连接信息。
    /// - Throws: 会话请求失败、响应缺失必要字段或任务取消时抛出错误。
    func createSession(model: RealtimeModel) async throws -> RealtimeSession

    /// 启动指定会话的周期心跳，并替换之前的心跳任务。
    ///
    /// - Parameters:
    ///   - sessionID: 需要保活的会话标识。
    ///   - onFailure: 心跳失败时接收会话标识和错误的回调。
    func startHeartbeat(
        sessionID: String,
        onFailure: @escaping RealtimeSessionHeartbeatFailureHandler
    )

    /// 停止当前心跳，并使其尚未处理的失败通知失效。
    func stopHeartbeat()

    /// 关闭指定服务端会话。
    ///
    /// - Parameter sessionID: 需要关闭的会话标识。
    /// - Throws: 关闭请求失败或任务取消时抛出错误。
    func closeSession(sessionID: String) async throws
}
