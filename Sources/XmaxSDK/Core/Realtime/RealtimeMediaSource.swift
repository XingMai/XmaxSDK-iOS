//
//  RealtimeMediaSource.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A local media source for realtime generation.
public enum RealtimeMediaSource: String, CaseIterable, Sendable {

    /// Camera input.
    case camera

    /// Video file input.
    case video

    /// Image input.
    case image

    /// Video frames supplied by your app.
    case external
}
