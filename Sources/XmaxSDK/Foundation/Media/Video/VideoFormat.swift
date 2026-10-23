//
//  VideoFormat.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The fixed dimensions and pixel format of a video frame.
struct VideoFormat: Equatable, Sendable {

    /// The frame width, in pixels.
    let width: Int

    /// The frame height, in pixels.
    let height: Int

    /// The pixel layout.
    let pixelFormat: VideoPixelFormat

    /// Creates a video format.
    ///
    /// - Parameters:
    ///   - width: The positive frame width, in pixels.
    ///   - height: The positive frame height, in pixels.
    ///   - pixelFormat: The frame's pixel format.
    ///
    /// - Throws: A configuration error if either dimension is not positive.
    init(
        width: Int,
        height: Int,
        pixelFormat: VideoPixelFormat
    ) throws {
        guard width > 0, height > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video width and height must be positive integers"
            )
        }

        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
    }
}
