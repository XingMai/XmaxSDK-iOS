//
//  InteractionFrame.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics

/// 一次从渲染视口采集到的交互输入。
struct InteractionFrame: Sendable {
    let points: [CGPoint]
    let viewportSize: CGSize
    let contentMode: VideoContentMode
    var displayedVideoSize: CGSize? = nil
}

extension RealtimeVideoFormat {
    var size: CGSize {
        CGSize(width: width, height: height)
    }
}
