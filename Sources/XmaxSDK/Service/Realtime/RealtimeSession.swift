//
//  RealtimeSession.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// Xmax 实时生成会话。
struct RealtimeSession: Equatable, Sendable {

    /// 服务端会话标识。
    let id: String

    /// 服务端关联的用户标识。
    let userID: String?

    /// 服务端返回的会话状态。
    let status: String?

    /// 该会话对应的 RTC 连接信息。
    let connection: RealtimeSessionConnection?

    /// 服务端报告的会话关闭原因。
    let closeReason: String?
}
