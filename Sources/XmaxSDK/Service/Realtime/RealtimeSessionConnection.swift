//
//  RealtimeSessionConnection.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 实时会话对应的 RTC 连接参数。
struct RealtimeSessionConnection: Equatable, Sendable {

    // 房间连接参数
    let roomID: String
    let userID: String
    let token: String
    let botName: String?
}

/// 实时会话心跳失败回调。
typealias RealtimeSessionHeartbeatFailureHandler = @Sendable (
    _ sessionID: String,
    _ error: XmaxError
) async -> Void
