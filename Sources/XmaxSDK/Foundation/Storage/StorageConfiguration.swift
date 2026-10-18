//
//  StorageConfiguration.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 对象存储请求使用的服务地址、存储桶和临时凭证。
struct StorageConfiguration: Equatable, Sendable {

    /// 存储位置
    let bucket: String
    let region: String
    let endpoint: String

    /// 访问凭证
    let credential: StorageCredential
}
