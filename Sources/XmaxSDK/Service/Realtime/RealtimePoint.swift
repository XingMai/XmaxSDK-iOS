//
//  RealtimePoint.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 相对于处理后媒体尺寸的二维归一化交互点，左上角为原点，右下角为 `(1, 1)`。
struct RealtimePoint: Equatable, Sendable {

    /// 归一化坐标，取值范围为 [0, 1]
    let x: Double
    let y: Double
}
