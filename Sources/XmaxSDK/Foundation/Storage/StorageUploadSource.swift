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

/// The data or local file used for an object upload.
enum StorageUploadSource: Equatable, Sendable {

    /// Uploads in-memory data.
    case data(Data)

    /// Uploads a local file.
    case file(URL)
}
