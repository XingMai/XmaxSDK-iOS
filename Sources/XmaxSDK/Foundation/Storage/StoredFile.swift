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

/// The result of a completed object upload.
struct StoredFile: Equatable, Sendable {

    /// The uploaded object's remote URL.
    let url: URL

    /// The object key within the bucket.
    let objectKey: String

    /// The ETag returned by object storage.
    let etag: String?
}
