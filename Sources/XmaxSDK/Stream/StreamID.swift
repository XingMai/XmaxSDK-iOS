//
//  StreamID.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// SDK 内部使用的本地与远端媒体流标识。
enum StreamID: String, Sendable {

    /// 本地输入流标识。
    case local = "stream-local"

    /// 远端生成结果流标识。
    case remote = "stream-remote"
}
