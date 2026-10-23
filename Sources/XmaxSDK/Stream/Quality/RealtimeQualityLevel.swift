//
//  RealtimeQualityLevel.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A transport quality level, from highest quality at L1 to lowest bandwidth at L5.
///
/// Quality levels are independent of network quality ratings.
public enum RealtimeQualityLevel: Int, CaseIterable, Sendable {

    /// Level 1, retaining the media baseline dimensions.
    case l1 = 1

    /// Level 2, targeting 90% of the media baseline width and height.
    case l2 = 2

    /// Level 3, targeting 75% of the media baseline width and height.
    case l3 = 3

    /// Level 4, targeting 60% of the media baseline width and height.
    case l4 = 4

    /// Level 5, targeting 40% of the media baseline width and height.
    case l5 = 5
}
