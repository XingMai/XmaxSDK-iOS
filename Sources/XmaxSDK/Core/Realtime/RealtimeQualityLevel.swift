//
//  RealtimeQualityLevel.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 实时传输档位；L1 质量最高，L5 最节省带宽，与网络质量评级无关。
public enum RealtimeQualityLevel: Int, CaseIterable, Sendable {

    /// 一级：保留媒体基准尺寸。
    case l1 = 1

    /// 二级：目标宽高为媒体基准的 80%。
    case l2 = 2

    /// 三级：目标宽高为媒体基准的 65%。
    case l3 = 3

    /// 四级：目标宽高为媒体基准的 50%。
    case l4 = 4

    /// 五级：与四级使用相同尺寸，并进一步降低上行帧率。
    case l5 = 5
}
