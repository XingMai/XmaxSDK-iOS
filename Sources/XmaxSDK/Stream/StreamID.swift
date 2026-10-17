//
//  StreamID.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// SDK 内部使用的本地与远端媒体流标识。
enum StreamID: String, Sendable {
    case local = "stream-local"
    case remote = "stream-remote"
}
