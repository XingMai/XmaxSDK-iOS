//
//  XmaxUploadedFile.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A remote file produced by a successful upload.
public struct XmaxUploadedFile: Equatable, Sendable {

    /// The URL used to access the remote file.
    public let url: URL

    /// The file's object storage key.
    public let objectKey: String

    /// The entity tag returned by object storage, if available.
    public let etag: String?

    /// Creates an upload result.
    init(
        url: URL,
        objectKey: String,
        etag: String?
    ) {
        self.url = url
        self.objectKey = objectKey
        self.etag = etag
    }
}
