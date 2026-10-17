//
//  QualityConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 当前连接的媒体基准与两个方向的传输档位。
struct QualityConfiguration: Sendable {
    let baseline: RealtimeVideoFormat
    let uplinkLevel: Int
    let downlinkLevel: Int

    var uplink: RealtimeVideoFormat {
        QualityVideoFormat.resolve(baseline, level: uplinkLevel, downlink: false)
    }

    var downlink: RealtimeVideoFormat {
        QualityVideoFormat.resolve(baseline, level: downlinkLevel, downlink: true)
    }
}

/// 同一采样产生的上下行候选档位；nil 表示该方向保持不变。
struct QualityChange: Sendable {
    let uplink: Int?
    let downlink: Int?
}
