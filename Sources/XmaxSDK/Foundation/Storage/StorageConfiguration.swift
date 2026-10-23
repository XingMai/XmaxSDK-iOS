//
//  StorageConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The endpoint, bucket, and temporary credentials for object storage.
struct StorageConfiguration: Equatable, Sendable {

    /// The COS bucket name.
    let bucket: String

    /// The COS bucket region.
    let region: String

    /// The object storage endpoint.
    let endpoint: String

    /// The request's temporary credentials.
    let credential: StorageCredential
}
