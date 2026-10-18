//
//  MediaServicing.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics

/// 定义模型输入尺寸和平台媒体能力相关的业务规则。
public protocol MediaServicing: Sendable {

    // 模型规则
    /// 当前媒体规则使用的实时生成模型。
    var model: RealtimeModel { get }

    /// 计算满足模型输入约束的尺寸。
    ///
    /// - Parameter size: 指定的视频格式尺寸；未指定格式时为原始媒体的显示尺寸。
    /// - Returns: 模型分辨率桶非空时，精确匹配后原样返回；为空时按像素面积上下限及对齐要求计算。
    /// - Throws: 尺寸无效或未匹配模型支持的分辨率桶时抛出 `XmaxError`。
    func resolveModelInputSize(_ size: CGSize) throws -> CGSize

    /// 综合档位尺寸上限和可选插帧限制，计算最终回传尺寸。
    ///
    /// - Parameters:
    ///   - sourceSize: 原始媒体的整数像素尺寸，用于确定比例和不放大的边界。
    ///   - maximumSize: 下行档位允许的宽高上限，可包含小数像素。
    ///   - frameInterpolationEnabled: 是否额外限制总像素不超过 900000；不检查设备能力。
    /// - Returns: 不超过上限、宽高均为 4 的倍数的尺寸；优先精确等比，无法等比时分别向下对齐。
    /// - Throws: 尺寸无效，或约束内无法容纳至少 4 × 4 像素时抛出 `XmaxError`。
    func resolveTargetSize(
        _ sourceSize: CGSize,
        maximumSize: CGSize,
        frameInterpolationEnabled: Bool
    ) throws -> CGSize

    /// 判断当前设备是否支持对指定分辨率的视频进行插帧。
    ///
    /// - Parameter size: 客户端收到的、用于插帧处理的视频分辨率。
    /// - Returns: 当前系统、设备和视频规格均支持插帧时返回 `true`。
    func supportsFrameInterpolation(for size: CGSize) -> Bool
}
