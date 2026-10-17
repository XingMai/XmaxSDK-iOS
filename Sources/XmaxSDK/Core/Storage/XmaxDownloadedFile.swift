//
//  XmaxDownloadedFile.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 表示下载到本地的文件。
public struct XmaxDownloadedFile: Equatable, Sendable {

    // 本地文件信息
    /// 下载后的本地文件地址。
    public let fileURL: URL

    /// 下载文件的字节数。
    public let byteCount: Int64

    /// 创建下载结果。
    ///
    /// - Parameters:
    ///   - fileURL: 下载完成后的本地文件地址。
    ///   - byteCount: 本地文件的字节数。
    init(fileURL: URL, byteCount: Int64) {
        self.fileURL = fileURL
        self.byteCount = byteCount
    }
}
