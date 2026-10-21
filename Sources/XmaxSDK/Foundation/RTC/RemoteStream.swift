//
//  RemoteStream.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 标识 RTC 房间中的一条远端主流。
struct RemoteStream: Equatable, Hashable, Sendable {

    /// 远端流所属的 RTC 房间标识。
    let roomID: String

    /// 远端流所属的 RTC 用户标识。
    let userID: String

    /// 生成跨房间唯一的远端流键。
    var key: String {
        "\(roomID):\(userID)"
    }
}
