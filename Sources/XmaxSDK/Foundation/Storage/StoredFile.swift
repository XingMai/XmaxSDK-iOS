//
//  StoredFile.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 对象存储上传完成后的中性结果。
struct StoredFile: Equatable, Sendable {

    /// 上传对象的远端访问地址。
    let url: URL

    /// 对象在存储桶中的路径。
    let objectKey: String

    /// 对象存储返回的 ETag 标识。
    let etag: String?
}
