//
//  RealtimeModel.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
import CoreGraphics

/// SDK 当前支持的实时生成模型。
public enum RealtimeModel: String, CaseIterable, Sendable {

    /// X2.1 实时生成模型。
    case x2_1 = "x2.1"

    /// 模型展示名称。
    public var displayName: String {
        switch self {
        case .x2_1: "X2.1"
        }
    }

    /// 模型支持的生成分辨率桶；摄像头输入须精确匹配。
    /// 图片和视频保留媒体比例，生成时选择比例最接近的画布。
    /// 空数组表示不限制固定尺寸，生成画布按像素面积上下限和对齐规则计算。
    public var resolutionBuckets: [CGSize] {
        switch self {
        case .x2_1:
            [
                CGSize(width: 1920, height: 1080),
                CGSize(width: 1080, height: 1920),
                CGSize(width: 1408, height: 1408),
                CGSize(width: 1152, height: 1536),
                CGSize(width: 1536, height: 1152)
            ]
        }
    }

    /// 生成画布的最小总像素面积；仅在分辨率桶为空时参与计算，不放大小尺寸媒体帧。
    public var minimumInputPixels: Int { 600000 }

    /// 本地媒体帧的最大总像素面积；分辨率桶为空时也用于限制生成画布。
    public var maximumInputPixels: Int {
        switch self {
        case .x2_1: 2100000
        }
    }

    /// 输入宽高需要对齐的像素倍数；仅在分辨率桶为空时参与尺寸计算。
    public var inputSizeAlignment: Int { 32 }

    /// 图片和视频输出以及默认摄像头配置使用的帧率。
    public var defaultFrameRate: Int { 30 }

    /// 摄像头采集使用的默认视频规格。
    public var defaultCameraVideoFormat: RealtimeVideoFormat {
        switch self {
        case .x2_1:
            RealtimeVideoFormat(width: 1080, height: 1920, fps: defaultFrameRate)
        }
    }
}
