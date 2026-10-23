//
//  StreamID.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The internal local and remote media stream identifiers.
enum StreamID: String, Sendable {

    /// The local input stream identifier.
    case local = "stream-local"

    /// The remote result stream identifier.
    case remote = "stream-remote"
}
