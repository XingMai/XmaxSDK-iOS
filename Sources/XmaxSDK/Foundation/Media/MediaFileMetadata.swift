//
//  MediaFileMetadata.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 本地媒体文件中视频、音频和时间线所需的元数据。
struct MediaFileMetadata: Equatable, Sendable {

    /// 视频轨道的原始宽度，单位为像素。
    let width: Int

    /// 视频轨道的原始高度，单位为像素。
    let height: Int

    /// 将原始视频帧转换为显示方向所需的旋转角度。
    let rotation: VideoRotation

    /// 媒体文件时长，单位为秒。
    let durationSeconds: Double

    /// 文件是否包含音轨。
    let hasAudio: Bool
}
