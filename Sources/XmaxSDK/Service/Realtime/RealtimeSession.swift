//
//  RealtimeSession.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// Xmax 实时生成会话。
struct RealtimeSession: Equatable, Sendable {

    // 会话信息
    let id: String
    let userID: String?
    let status: String?

    // RTC 连接
    let connection: RealtimeSessionConnection?

    // 关闭原因
    let closeReason: String?
}
