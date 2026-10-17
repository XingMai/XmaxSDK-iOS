//
//  RoomJoinConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// RTC 房间加入参数。
struct RoomJoinConfiguration: Equatable, Sendable {
    let roomID: String
    let userID: String
    let token: String
}
