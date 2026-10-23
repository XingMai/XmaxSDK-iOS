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

/// A handler for file upload or download progress.
///
/// Downloads with an unknown content length report a zero `totalUnitCount` until completion.
///
/// - Parameter progress: The completed and total transfer byte counts.
public typealias XmaxStorageProgressHandler = @Sendable (Progress) -> Void
