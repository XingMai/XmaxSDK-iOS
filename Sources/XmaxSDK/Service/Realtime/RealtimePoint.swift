//
//  RealtimePoint.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 相对于处理后媒体尺寸的二维归一化交互点，左上角为原点，右下角为 `(1, 1)`。
struct RealtimePoint: Equatable, Sendable {

    /// 相对于完整媒体宽度的归一化横坐标，范围为 [0, 1]。
    let x: Double

    /// 相对于完整媒体高度的归一化纵坐标，范围为 [0, 1]。
    let y: Double
}
