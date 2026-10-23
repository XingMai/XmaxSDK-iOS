//
//  XmaxDownloadedFile.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A file downloaded to local storage.
public struct XmaxDownloadedFile: Equatable, Sendable {

    /// The local URL of the downloaded file.
    public let fileURL: URL

    /// The size of the downloaded file, in bytes.
    public let byteCount: Int64

    /// Creates a download result.
    init(
        fileURL: URL,
        byteCount: Int64
    ) {
        self.fileURL = fileURL
        self.byteCount = byteCount
    }
}
