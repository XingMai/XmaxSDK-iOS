//
//  RemoteStream.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 标识 RTC 房间中的一条远端主流。
struct RemoteStream: Equatable, Hashable, Sendable {

    // 流标识
    let roomID: String
    let userID: String


    // 唯一索引
    /// 生成跨房间唯一的远端流键。
    var key: String {
        "\(roomID):\(userID)"
    }
}
