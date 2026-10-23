//
//  StorageCredential.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// Temporary credentials for an object storage request.
struct StorageCredential: Equatable, Sendable {

    /// The temporary access key identifier.
    let accessKeyID: String

    /// The temporary secret access key.
    let secretAccessKey: String

    /// The temporary session token.
    let sessionToken: String
}
