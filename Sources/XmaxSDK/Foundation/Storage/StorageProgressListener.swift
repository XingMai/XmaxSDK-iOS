//
//  StorageProgressListener.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A handler for completed and total transfer byte counts.
///
/// The total is zero while a download's content length is unknown and is resolved on completion.
typealias StorageProgressListener =
    @Sendable (
        _ completedBytes: Int64,
        _ totalBytes: Int64
    ) -> Void
