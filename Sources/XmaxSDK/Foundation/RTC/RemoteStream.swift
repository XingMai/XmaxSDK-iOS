//
//  RemoteStream.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A remote main stream in an RTC room.
struct RemoteStream: Equatable, Hashable, Sendable {

    /// The stream's RTC room identifier.
    let roomID: String

    /// The stream owner's RTC user identifier.
    let userID: String

    /// The remote stream key, unique across rooms.
    var key: String {
        "\(roomID):\(userID)"
    }
}
