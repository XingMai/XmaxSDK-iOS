//
//  QualityConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 当前连接的媒体基准与两个方向的传输档位。
struct QualityConfiguration: Sendable {

    /// 不随网络档位变化的处理后媒体规格。
    let baseline: RealtimeVideoFormat

    /// 当前上行档位，范围为 1...5。
    let uplinkLevel: RealtimeQualityLevel

    /// 下行目标档位，范围为 1...5。
    let downlinkLevel: RealtimeQualityLevel

    /// 当前上行档位使用的编码规格。
    var uplink: RealtimeVideoFormat {
        QualityVideoFormat.resolve(baseline, level: uplinkLevel, downlink: false)
    }

    /// 当前下行档位允许的回传规格。
    var downlink: RealtimeVideoFormat {
        QualityVideoFormat.resolve(baseline, level: downlinkLevel, downlink: true)
    }
}

/// 同一采样产生的上下行候选档位；nil 表示该方向保持不变。
struct QualityChange: Sendable {

    /// 本次采样提出的上行候选档位。
    let uplink: RealtimeQualityLevel?

    /// 本次采样提出的下行候选档位。
    let downlink: RealtimeQualityLevel?
}
