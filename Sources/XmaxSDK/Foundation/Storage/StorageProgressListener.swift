//
//  StorageProgressListener.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 接收存储任务已完成字节数和总字节数的进度回调。
typealias StorageProgressListener = @Sendable (
    _ completedBytes: Int64,
    _ totalBytes: Int64
) -> Void
