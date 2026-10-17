//
//  RealtimeMediaStream.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 实时生成输出的媒体流。
public struct RealtimeMediaStream: Sendable {

    /// 媒体流标识。
    public let id: String

    /// 媒体流包含的视频轨道。
    public let videoTrack: RealtimeVideoTrack?
}
