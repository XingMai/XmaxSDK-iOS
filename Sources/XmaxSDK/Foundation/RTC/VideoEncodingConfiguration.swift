//
//  VideoEncodingConfiguration.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// RTC 主视频流编码参数。
struct VideoEncodingConfiguration: Equatable, Sendable {
    /// 指定网络受限时的视频编码退化偏好。
    enum EncoderPreference: Equatable, Sendable {
        case auto
        case maintainFramerate
        case maintainQuality
    }

    // 视频规格
    let width: Int
    let height: Int
    let frameRate: Int

    // 码率与编码策略
    let minimumBitrate: Int
    let maximumBitrate: Int
    let encoderPreference: EncoderPreference

    /// 创建 RTC 视频编码配置。
    ///
    /// - Parameters:
    ///   - width: 编码宽度，单位为像素。
    ///   - height: 编码高度，单位为像素。
    ///   - frameRate: 编码帧率，单位为 fps。
    ///   - minimumBitrate: 最小码率，单位为 kbps；默认值由平台处理。
    ///   - maximumBitrate: 最大码率，单位为 kbps；负值表示使用平台默认值。
    ///   - encoderPreference: 网络受限时的编码偏好。
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
