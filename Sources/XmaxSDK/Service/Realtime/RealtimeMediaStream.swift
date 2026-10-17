//
//  RealtimeMediaStream.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 包含本地输入或远端生成结果的实时媒体流。
public struct RealtimeMediaStream: Sendable {

    // 媒体流信息
    /// 媒体流标识。
    public let id: String

    /// 媒体流包含的视频轨道。
    public let videoTrack: RealtimeVideoTrack?
}
