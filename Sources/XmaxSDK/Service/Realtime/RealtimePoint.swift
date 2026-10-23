//
//  RealtimePoint.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A normalized media point, from top-left `(0, 0)` to bottom-right `(1, 1)`.
struct RealtimePoint: Equatable, Sendable {

    /// The normalized horizontal position within the full media width, in `[0, 1]`.
    let x: Double

    /// The normalized vertical position within the full media height, in `[0, 1]`.
    let y: Double
}
