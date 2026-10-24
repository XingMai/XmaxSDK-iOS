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

/// A camera resolution preset whose availability depends on the selected model.
public enum RealtimeCameraPreset: CaseIterable, Sendable {

    /// A landscape 16:9 frame.
    case resolution1920x1080

    /// A portrait 9:16 frame.
    case resolution1080x1920

    /// A square frame.
    case resolution1408x1408

    /// A portrait 3:4 frame.
    case resolution1152x1536

    /// A landscape 4:3 frame.
    case resolution1536x1152

    /// The frame dimensions, in pixels.
    public var size: CGSize {
        switch self {
        case .resolution1920x1080:
            CGSize(
                width: 1920,
                height: 1080
            )
        case .resolution1080x1920:
            CGSize(
                width: 1080,
                height: 1920
            )
        case .resolution1408x1408:
            CGSize(
                width: 1408,
                height: 1408
            )
        case .resolution1152x1536:
            CGSize(
                width: 1152,
                height: 1536
            )
        case .resolution1536x1152:
            CGSize(
                width: 1536,
                height: 1152
            )
        }
    }
}
