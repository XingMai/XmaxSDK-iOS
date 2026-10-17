//
//  RealtimeSession.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// Xmax 实时生成会话。
struct RealtimeSession: Equatable, Sendable {
    let id: String
    let userID: String?
    let status: String?
    let connection: RealtimeSessionConnection?
    let closeReason: String?
}
