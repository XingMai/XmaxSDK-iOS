//
//  DownloadedFile.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 远端文件下载完成后的中性结果。
struct DownloadedFile: Equatable, Sendable {

    /// 下载完成后的本地文件地址。
    let fileURL: URL

    /// 下载文件的字节数。
    let byteCount: Int64
}
