//
//  VideoContentMode.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 视频内容在渲染容器中的显示模式。
public enum VideoContentMode: String, CaseIterable, Sendable {

    /// 等比完整显示，允许容器留空。
    case fit

    /// 等比铺满容器，允许裁剪画面。
    case fill
}
