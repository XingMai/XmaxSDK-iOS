//
//  VideoFrame.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 持有中性像素数据及时间信息的视频帧。
struct VideoFrame: Equatable, Sendable {

    // 缓冲区标识
    let bufferReuseID: UUID?

    // 帧元数据
    let format: VideoFormat
    let timestampUs: Int64
    let rotation: VideoRotation

    // 像素数据
    let planes: [VideoFramePlane]

    /// 创建持有像素平面、时间戳与显示方向的视频帧。
    ///
    /// - Parameters:
    ///   - format: 视频尺寸和像素格式。
    ///   - timestampUs: 帧时间戳，单位为微秒，不能为负数。
    ///   - planes: 至少包含一个元素的像素数据平面。
    ///   - rotation: 显示时需要应用的旋转方向。
    ///   - bufferReuseID: 允许复用底层缓冲区的标识；`nil` 表示不使用缓存标识。
    /// - Throws: 时间戳为负数或像素平面为空时抛出配置错误。
    init(
        format: VideoFormat,
        timestampUs: Int64,
        planes: [VideoFramePlane],
        rotation: VideoRotation = .rotation0,
        bufferReuseID: UUID? = nil
    ) throws {
        guard timestampUs >= 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame timestamp must be non-negative"
            )
        }
        guard !planes.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame must contain at least one plane"
            )
        }

        self.bufferReuseID = bufferReuseID
        self.format = format
        self.timestampUs = timestampUs
        self.rotation = rotation
        self.planes = planes
    }

    /// 复用像素数据，生成具有新时间戳和可选旋转方向的视频帧。
    ///
    /// - Parameters:
    ///   - timestampUs: 新的帧时间戳，单位为微秒。
    ///   - rotation: 新的旋转方向；`nil` 保留原方向。
    /// - Returns: 共享原像素平面和复用标识的新帧。
    /// - Throws: 新时间戳无效时抛出配置错误。
    func updating(
        timestampUs: Int64,
        rotation: VideoRotation? = nil
    ) throws -> VideoFrame {
        try VideoFrame(
            format: format,
            timestampUs: timestampUs,
            planes: planes,
            rotation: rotation ?? self.rotation,
            bufferReuseID: bufferReuseID
        )
    }
}
