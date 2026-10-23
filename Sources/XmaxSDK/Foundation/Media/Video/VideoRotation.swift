//
//  VideoRotation.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The clockwise rotation applied to a video frame.
enum VideoRotation: Int, CaseIterable, Sendable {

    /// No rotation.
    case rotation0 = 0

    /// A 90-degree rotation.
    case rotation90 = 90

    /// A 180-degree rotation.
    case rotation180 = 180

    /// A 270-degree rotation.
    case rotation270 = 270
}
