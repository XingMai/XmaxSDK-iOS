//
//  StorageUploadSource.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 对象存储上传支持的二进制数据或本地文件。
enum StorageUploadSource: Equatable, Sendable {
    case data(Data)
    case file(URL)
}
