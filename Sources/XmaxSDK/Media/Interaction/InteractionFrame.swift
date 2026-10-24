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

/// An interaction sampled from a video viewport.
struct InteractionFrame: Sendable {

    /// The sampled touch positions relative to the viewport.
    let points: [CGPoint]

    /// The viewport dimensions, in points.
    let viewportSize: CGSize

    /// The view's video content mode.
    let contentMode: VideoContentMode
}
