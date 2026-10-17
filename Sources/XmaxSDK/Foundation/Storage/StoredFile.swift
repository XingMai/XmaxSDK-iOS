//
//  StoredFile.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 对象存储上传完成后的中性结果。
struct StoredFile: Equatable, Sendable {
    let url: URL
    let objectKey: String
    let etag: String?
}
