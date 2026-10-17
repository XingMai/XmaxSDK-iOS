//
//  MediaFileMetadata.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 本地媒体文件中视频、音频和时间线所需的元数据。
struct MediaFileMetadata: Equatable, Sendable {
    let width: Int
    let height: Int
    let rotation: VideoRotation
    let durationSeconds: Double
    let hasAudio: Bool
}
