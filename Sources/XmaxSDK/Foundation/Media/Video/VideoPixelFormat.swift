//
//  VideoPixelFormat.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 中性视频帧支持的像素格式。
enum VideoPixelFormat: String, CaseIterable, Sendable {

    /// Y、U、V 分别存放的 4:2:0 格式。
    case i420

    /// Y 平面与交错 UV 平面组成的 4:2:0 格式。
    case nv12

    /// Y 平面与交错 VU 平面组成的 4:2:0 格式。
    case nv21

    /// 按红、绿、蓝、透明度排列的像素格式。
    case rgba

    /// 按蓝、绿、红、透明度排列的像素格式。
    case bgra

    /// 按透明度、红、绿、蓝排列的像素格式。
    case argb
}
