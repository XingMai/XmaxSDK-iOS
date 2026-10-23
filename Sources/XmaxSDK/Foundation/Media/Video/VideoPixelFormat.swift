//
//  VideoPixelFormat.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A pixel format supported by video frames.
enum VideoPixelFormat: String, CaseIterable, Sendable {

    /// Planar 4:2:0 with separate Y, U, and V planes.
    case i420

    /// Biplanar 4:2:0 with Y and interleaved UV planes.
    case nv12

    /// Biplanar 4:2:0 with Y and interleaved VU planes.
    case nv21

    /// Red, green, blue, and alpha pixels.
    case rgba

    /// Blue, green, red, and alpha pixels.
    case bgra

    /// Alpha, red, green, and blue pixels.
    case argb
}
