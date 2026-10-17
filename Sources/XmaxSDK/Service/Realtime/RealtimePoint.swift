//
//  RealtimePoint.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 视频像素坐标系中的二维交互点。
struct RealtimePoint: Equatable, Sendable {

    // 像素坐标
    let x: Double
    let y: Double
}
