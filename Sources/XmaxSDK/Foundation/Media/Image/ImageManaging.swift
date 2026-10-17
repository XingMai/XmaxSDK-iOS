//
//  ImageManaging.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 定义 SDK 内部使用的平台图片解码能力。
protocol ImageManaging: Sendable {

    /// 解码图片数据并应用图片方向，返回可重复处理的像素图像。
    ///
    /// - Parameter data: JPEG、PNG 等受支持格式的编码图片数据。
    /// - Returns: 已应用原始方向的解码图像。
    /// - Throws: 数据为空、格式不支持或图片解码失败时抛出错误。
    func decode(_ data: Data) throws -> any DecodedImage
}
