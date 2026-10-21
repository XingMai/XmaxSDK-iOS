//
//  RealtimeSessionConnection.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 实时会话对应的 RTC 连接参数。
struct RealtimeSessionConnection: Equatable, Sendable {

    /// 服务端分配的 RTC 房间标识。
    let roomID: String

    /// 本地 RTC 用户标识。
    let userID: String

    /// RTC 房间认证令牌。
    let token: String

    /// 生成结果流对应的远端用户标识。
    let botName: String?
}

/// 实时会话心跳失败回调。
typealias RealtimeSessionHeartbeatFailureHandler = @Sendable (
    _ sessionID: String,
    _ error: XmaxError
) async -> Void
