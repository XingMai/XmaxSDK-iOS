//
//  EncodingController.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 根据实时视频格式配置 RTC 视频编码参数。
final class EncodingController: EncodingControlling, Sendable {

    /// 基础层组件
    private let rtcManager: any RtcManaging

    /// 创建负责应用 RTC 视频编码配置的控制器。
    ///
    /// - Parameter rtcManager: 接收编码配置的 RTC 管理器。
    init(rtcManager: any RtcManaging) {
        self.rtcManager = rtcManager
    }

    /// 校验视频规格并应用解析后的 RTC 编码参数。
    ///
    /// - Parameter videoFormat: 包含尺寸、帧率、可选码率及编码偏好的视频规格。
    /// - Throws: 视频规格无效、默认码率解析或 RTC 配置失败时抛出错误。
    func configure(_ videoFormat: RealtimeVideoFormat) throws {
        try videoFormat.validate()

        let (minimum, maximum) = try EncodingBitratePolicy.resolve(videoFormat)

        let encoderPreference: VideoEncodingConfiguration.EncoderPreference = switch videoFormat.encoderPreference {
            case .auto: .auto
            case .maintainFramerate: .maintainFramerate
            case .maintainQuality: .maintainQuality
        }

        try rtcManager.configureVideoEncoding(
            VideoEncodingConfiguration(
                width: videoFormat.width,
                height: videoFormat.height,
                frameRate: videoFormat.fps,
                minimumBitrate: minimum,
                maximumBitrate: maximum,
                encoderPreference: encoderPreference
            )
        )
    }
}
