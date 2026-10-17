//
//  XmaxUploadedFile.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 表示上传成功后的远端文件。
public struct XmaxUploadedFile: Equatable, Sendable {

    // 远端文件信息
    /// 文件的远端访问地址。
    public let url: URL

    /// 文件在对象存储中的标识。
    public let objectKey: String

    /// 对象存储返回的可选实体标识。
    public let etag: String?

    /// 创建上传结果。
    ///
    /// - Parameters:
    ///   - url: 上传文件的远端访问地址。
    ///   - objectKey: 文件在对象存储中的标识。
    ///   - etag: 对象存储返回的实体标识；未返回时为 nil。
    init(url: URL, objectKey: String, etag: String?) {
        self.url = url
        self.objectKey = objectKey
        self.etag = etag
    }
}
