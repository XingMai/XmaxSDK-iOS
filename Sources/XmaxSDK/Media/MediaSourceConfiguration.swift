//
//  MediaSourceConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 本地视频文件准备完成后的输出配置。
struct MediaSourceConfiguration: Equatable, Sendable {
    let videoFormat: RealtimeVideoFormat
    let hasAudio: Bool
}
