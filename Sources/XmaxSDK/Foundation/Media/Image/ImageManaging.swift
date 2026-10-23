//
//  ImageManaging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An interface for image decoding.
protocol ImageManaging: Sendable {

    /// Decodes image data and applies its orientation.
    ///
    /// - Parameter data: Encoded image data, such as JPEG or PNG.
    ///
    /// - Returns: The orientation-corrected decoded image.
    ///
    /// - Throws: An error if data is empty, unsupported, or cannot be decoded.
    func decode(
        _ data: Data
    ) throws -> any DecodedImage
}
