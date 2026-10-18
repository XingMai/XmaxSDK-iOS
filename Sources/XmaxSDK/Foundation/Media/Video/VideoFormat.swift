//
//  VideoFormat.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 表示视频帧的固定尺寸和像素格式。
struct VideoFormat: Equatable, Sendable {

    /// 帧规格
    let width: Int
    let height: Int
    let pixelFormat: VideoPixelFormat

    /// 创建具有有效尺寸的像素格式。
    ///
    /// - Parameters:
    ///   - width: 帧宽度，单位为像素，必须大于零。
    ///   - height: 帧高度，单位为像素，必须大于零。
    ///   - pixelFormat: 帧数据使用的像素格式。
    /// - Throws: 宽度或高度非正数时抛出配置错误。
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
