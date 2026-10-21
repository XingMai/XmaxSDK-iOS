//
//  VideoFramePlane.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 表示视频帧中的一个像素数据平面。
struct VideoFramePlane: Equatable, Sendable {

    /// 承载像素平面的原始字节数据。
    let data: Data

    /// 相邻像素行的字节跨度。
    let stride: Int

    /// 该平面在数据缓冲区中的起始字节偏移。
    let byteOffset: Int

    /// 该平面占用的字节数。
    let byteLength: Int

    /// 创建指向有效字节范围的视频像素平面。
    ///
    /// - Parameters:
    ///   - data: 持有像素字节的非空数据。
    ///   - stride: 每行字节跨度，必须大于零。
    ///   - byteOffset: 平面数据在缓冲区中的起始字节偏移。
    ///   - byteLength: 平面的有效字节长度；`nil` 使用偏移后全部数据。
    /// - Throws: 数据为空、字节范围越界或行跨度无效时抛出配置错误。
    init(
        data: Data,
        stride: Int,
        byteOffset: Int = 0,
        byteLength: Int? = nil
    ) throws {
        guard !data.isEmpty,
              byteOffset >= 0,
              byteOffset < data.count else {
            throw Self.invalidRangeError
        }

        let resolvedByteLength = byteLength ?? data.count - byteOffset
        guard resolvedByteLength > 0,
              resolvedByteLength <= data.count - byteOffset else {
            throw Self.invalidRangeError
        }
        guard stride > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame plane stride must be a positive integer"
            )
        }

        self.data = data
        self.stride = stride
        self.byteOffset = byteOffset
        self.byteLength = resolvedByteLength
    }

    /// 像素平面的字节范围无效时返回的错误。
    private static var invalidRangeError: XmaxError {
        XmaxError(
            code: .invalidConfiguration,
            message: "Video frame plane range is invalid"
        )
    }
}
