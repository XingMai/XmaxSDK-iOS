//
//  QualityConfiguration.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 当前连接的媒体基准与两个方向的传输档位。
struct QualityConfiguration: Sendable {

    // 媒体基准
    let baseline: RealtimeVideoFormat

    // 传输档位
    let uplinkLevel: Int
    let downlinkLevel: Int

    // 实际传输规格
    var uplink: RealtimeVideoFormat {
        QualityVideoFormat.resolve(baseline, level: uplinkLevel, downlink: false)
    }

    var downlink: RealtimeVideoFormat {
        QualityVideoFormat.resolve(baseline, level: downlinkLevel, downlink: true)
    }
}

/// 同一采样产生的上下行候选档位；nil 表示该方向保持不变。
struct QualityChange: Sendable {

    // 候选档位
    let uplink: Int?
    let downlink: Int?
}
