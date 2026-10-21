//
//  VideoRotation.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 视频帧需要顺时针旋转的角度。
enum VideoRotation: Int, CaseIterable, Sendable {

    /// 不旋转。
    case rotation0 = 0

    /// 旋转 90 度。
    case rotation90 = 90

    /// 旋转 180 度。
    case rotation180 = 180

    /// 旋转 270 度。
    case rotation270 = 270
}
