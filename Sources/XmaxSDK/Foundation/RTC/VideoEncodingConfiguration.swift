//
//  VideoEncodingConfiguration.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// RTC 主视频流编码参数。
struct VideoEncodingConfiguration: Equatable, Sendable {

    /// 指定网络受限时的视频编码退化偏好。
    enum EncoderPreference: Equatable, Sendable {

        /// 由 RTC 引擎选择编码降级策略。
        case auto

        /// 带宽不足时优先保持帧率。
        case maintainFramerate

        /// 带宽不足时优先保持画质。
        case maintainQuality
    }

    /// 编码宽度，单位为像素。
    let width: Int

    /// 目标编码高度，单位为像素。
    let height: Int

    /// 目标编码帧率，单位为 fps。
    let frameRate: Int

    /// 编码码率下限，单位为 kbps；0 表示不设最低码率。
    let minimumBitrate: Int

    /// 编码码率上限，单位为 kbps；负值使用平台默认值。
    let maximumBitrate: Int

    /// 网络或性能受限时的编码降级偏好。
    let encoderPreference: EncoderPreference

    /// 创建 RTC 视频编码配置。
    init(
        width: Int,
        height: Int,
        frameRate: Int,
        minimumBitrate: Int = 0,
        maximumBitrate: Int = -1,
        encoderPreference: EncoderPreference = .maintainFramerate
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.minimumBitrate = minimumBitrate
        self.maximumBitrate = maximumBitrate
        self.encoderPreference = encoderPreference
    }
}
