//
//  VideoContentMode.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The layout of video content within a rendering view.
public enum VideoContentMode: String, CaseIterable, Sendable {

    /// Preserves the full frame, allowing empty space.
    case fit

    /// Fills the view, cropping the frame when necessary.
    case fill
}
