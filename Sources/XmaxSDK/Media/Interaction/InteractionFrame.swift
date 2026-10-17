//
//  InteractionFrame.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics

/// 一次从渲染视口采集到的交互输入。
struct InteractionFrame: Sendable {

    // 触控采样
    let points: [CGPoint]

    // 显示映射
    let viewportSize: CGSize
    let contentMode: VideoContentMode
    var displayedVideoSize: CGSize? = nil
}

extension RealtimeVideoFormat {

    // 像素尺寸
    var size: CGSize {
        CGSize(width: width, height: height)
    }
}
