//
//  MediaSourceConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 本地视频文件准备完成后的输出配置。
struct MediaSourceConfiguration: Equatable, Sendable {

    /// 本地媒体帧输出使用的视频规格。
    let videoFormat: RealtimeVideoFormat

    /// 本地媒体是否包含可发送的音频。
    let hasAudio: Bool
}
