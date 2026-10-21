//
//  StorageUploadSource.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 对象存储上传支持的二进制数据或本地文件。
enum StorageUploadSource: Equatable, Sendable {

    /// 上传内存中的数据。
    case data(Data)

    /// 上传本地文件。
    case file(URL)
}
