//
//  StorageCredential.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 对象存储单次请求使用的临时凭证。
struct StorageCredential: Equatable, Sendable {

    // 临时访问凭证
    let accessKeyID: String
    let secretAccessKey: String
    let sessionToken: String
}
