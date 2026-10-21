//
//  RealtimeConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 创建实时 Manager 所需的业务配置。
public struct RealtimeConfiguration: Equatable, Sendable {

    /// 实时生成业务使用的模型。
    public let model: RealtimeModel

    /// 是否默认开启远端生成画面的插帧。
    public let isFrameInterpolationEnabled: Bool

    /// 创建实时业务配置。
    public init(
        model: RealtimeModel,
        isFrameInterpolationEnabled: Bool = true
    ) {
        self.model = model
        self.isFrameInterpolationEnabled = isFrameInterpolationEnabled
    }
}
