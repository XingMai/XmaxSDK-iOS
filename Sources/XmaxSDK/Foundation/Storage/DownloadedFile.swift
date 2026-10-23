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

/// The result of a completed file download.
struct DownloadedFile: Equatable, Sendable {

    /// The downloaded local file URL.
    let fileURL: URL

    /// The downloaded byte count.
    let byteCount: Int64
}
