//
//  MediaFileMetadataManaging.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 定义读取本地媒体文件元数据的能力。
protocol MediaFileMetadataManaging: Sendable {

    /// 读取视频的原始尺寸、显示旋转、时长和音频轨道信息。
    ///
    /// - Parameter fileURL: 可读取的本地视频文件 URL。
    /// - Returns: 用于准备本地视频流的媒体元数据。
    /// - Throws: 文件不可读、无视频轨道或媒体元数据无效时抛出错误。
    func readMetadata(fileURL: URL) async throws -> MediaFileMetadata
}
