//
//  MediaFileMetadata.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 本地媒体文件中视频、音频和时间线所需的元数据。
struct MediaFileMetadata: Equatable, Sendable {

    // 视频显示规格
    let width: Int
    let height: Int
    let rotation: VideoRotation


    // 播放信息
    let durationSeconds: Double
    let hasAudio: Bool
}
