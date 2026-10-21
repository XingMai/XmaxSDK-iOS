//
//  RoomJoinConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// RTC 房间加入参数。
struct RoomJoinConfiguration: Equatable, Sendable {

    /// 准备加入的 RTC 房间标识。
    let roomID: String

    /// 本地 RTC 用户标识。
    let userID: String

    /// 加入房间使用的认证令牌。
    let token: String
}
