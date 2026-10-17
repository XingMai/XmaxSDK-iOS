//
//  RoomJoinConfiguration.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// RTC 房间加入参数。
struct RoomJoinConfiguration: Equatable, Sendable {

    // 房间连接参数
    let roomID: String
    let userID: String
    let token: String
}
