//
//  RealtimeCameraPreset.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics

/// 摄像头输出分辨率的快捷选项；实际支持范围由模型决定。
public enum RealtimeCameraPreset: CaseIterable, Sendable {

    /// 16:9 横向画面。
    case resolution1920x1080

    /// 9:16 竖向画面。
    case resolution1080x1920

    /// 1:1 正方形画面。
    case resolution1408x1408

    /// 3:4 竖向画面。
    case resolution1152x1536

    /// 4:3 横向画面。
    case resolution1536x1152

    /// 输出宽高，单位为像素；不包含帧率或码率配置。
    public var size: CGSize {
        switch self {
        case .resolution1920x1080: CGSize(width: 1920, height: 1080)
        case .resolution1080x1920: CGSize(width: 1080, height: 1920)
        case .resolution1408x1408: CGSize(width: 1408, height: 1408)
        case .resolution1152x1536: CGSize(width: 1152, height: 1536)
        case .resolution1536x1152: CGSize(width: 1536, height: 1152)
        }
    }
}
