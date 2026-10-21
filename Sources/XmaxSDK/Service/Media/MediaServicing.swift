//
//  MediaServicing.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics

/// 定义本地媒体、生成画布、回传尺寸和平台媒体能力的业务规则。
public protocol MediaServicing: Sendable {

    /// 当前媒体规则使用的实时生成模型。
    var model: RealtimeModel { get }

    /// 计算本地媒体帧尺寸，并校验摄像头的模型分辨率桶。
    ///
    /// - Parameters:
    ///   - sourceMediaSize: 摄像头请求尺寸或图片、视频按显示方向解析后的原始整数像素尺寸。
    ///   - source: 媒体来源；摄像头须精确匹配模型已配置的分辨率桶。
    /// - Returns: 不放大、不超过模型最大像素面积的 4 对齐尺寸，优先保持精确比例。
    /// - Throws: 尺寸无效、摄像头不匹配分辨率桶或无法形成有效输出尺寸时抛出错误。
    func resolveMediaSize(
        _ sourceMediaSize: CGSize,
        source: RealtimeMediaSource
    ) throws -> CGSize

    /// 综合档位尺寸上限和可选插帧限制，计算最终回传尺寸。
    ///
    /// - Parameters:
    ///   - resolvedMediaSize: 处理后的本地媒体尺寸，用于确定比例和不放大的边界。
    ///   - maximumSize: 下行档位允许的宽高上限，可包含小数像素。
    ///   - frameInterpolationEnabled: 是否额外限制总像素不超过 900000；不检查设备能力。
    /// - Returns: 不超过上限、宽高均为 4 的倍数的尺寸；优先精确等比，无法等比时分别向下对齐。
    /// - Throws: 尺寸无效，或约束内无法容纳至少 4 × 4 像素时抛出 `XmaxError`。
    func resolveTargetSize(
        _ resolvedMediaSize: CGSize,
        maximumSize: CGSize,
        frameInterpolationEnabled: Bool
    ) throws -> CGSize

    /// 判断当前设备是否支持对指定分辨率的视频进行插帧。
    ///
    /// - Parameter size: 客户端收到的、用于插帧处理的视频分辨率。
    /// - Returns: 当前系统、设备和视频规格均支持插帧时返回 `true`。
    func supportsFrameInterpolation(
        for size: CGSize
    ) -> Bool
}
