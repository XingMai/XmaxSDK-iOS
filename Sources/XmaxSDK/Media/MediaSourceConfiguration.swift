//
//  MediaSourceConfiguration.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 本地视频文件准备完成后的输出配置。
struct MediaSourceConfiguration: Equatable, Sendable {

    // 媒体输出配置
    let videoFormat: RealtimeVideoFormat
    let hasAudio: Bool
}
