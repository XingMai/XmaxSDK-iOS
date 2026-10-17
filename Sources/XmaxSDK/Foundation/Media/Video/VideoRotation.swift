//
//  VideoRotation.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 视频帧需要顺时针旋转的角度。
enum VideoRotation: Int, CaseIterable, Sendable {
    case rotation0 = 0
    case rotation90 = 90
    case rotation180 = 180
    case rotation270 = 270
}
