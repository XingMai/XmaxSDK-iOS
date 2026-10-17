//
//  StorageConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 对象存储请求使用的服务地址、存储桶和临时凭证。
struct StorageConfiguration: Equatable, Sendable {
    let bucket: String
    let region: String
    let endpoint: String
    let credential: StorageCredential
}
