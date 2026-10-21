//
//  XmaxStorageProgressHandler.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 接收文件上传或下载进度。
///
/// - Parameter progress: 包含已完成字节数与总字节数的进度信息。
public typealias XmaxStorageProgressHandler = @Sendable (Progress) -> Void
