//
//  StorageConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 对象存储请求使用的服务地址、存储桶和临时凭证。
struct StorageConfiguration: Equatable, Sendable {

    /// COS 存储桶名称。
    let bucket: String

    /// COS 存储桶所在地域。
    let region: String

    /// 对象存储服务地址。
    let endpoint: String

    /// 当前存储请求使用的临时凭证。
    let credential: StorageCredential
}
