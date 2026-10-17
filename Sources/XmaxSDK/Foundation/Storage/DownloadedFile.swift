//
//  DownloadedFile.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 远端文件下载完成后的中性结果。
struct DownloadedFile: Equatable, Sendable {

    // 本地文件信息
    let fileURL: URL
    let byteCount: Int64
}
