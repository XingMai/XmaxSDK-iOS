//
//  StorageCredential.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 对象存储单次请求使用的临时凭证。
struct StorageCredential: Equatable, Sendable {
    let accessKeyID: String
    let secretAccessKey: String
    let sessionToken: String
}
