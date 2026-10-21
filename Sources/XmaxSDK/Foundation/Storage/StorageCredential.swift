//
//  StorageCredential.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 对象存储单次请求使用的临时凭证。
struct StorageCredential: Equatable, Sendable {

    /// 临时访问密钥标识。
    let accessKeyID: String

    /// 临时访问密钥。
    let secretAccessKey: String

    /// 临时访问凭证的会话令牌。
    let sessionToken: String
}
