//
//  VideoPixelFormat.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 中性视频帧支持的像素格式。
enum VideoPixelFormat: String, CaseIterable, Sendable {
    case i420
    case nv12
    case nv21
    case rgba
    case bgra
    case argb
}
