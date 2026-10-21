//
//  InteractionFrame.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics

/// 一次从渲染视口采集到的交互输入。
struct InteractionFrame: Sendable {

    /// 本次采样得到的触点，坐标相对于视口。
    let points: [CGPoint]

    /// 采样视口的宽高，单位为点。
    let viewportSize: CGSize

    /// 视图显示媒体时采用的填充方式。
    let contentMode: VideoContentMode
}

extension RealtimeVideoFormat {

    /// 视频规格对应的像素宽高。
    var size: CGSize {
        CGSize(width: width, height: height)
    }
}
