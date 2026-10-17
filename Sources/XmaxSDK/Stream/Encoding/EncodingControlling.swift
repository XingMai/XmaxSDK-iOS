//
//  EncodingControlling.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 定义实时视频编码参数的配置能力。
protocol EncodingControlling: Sendable {

    /// 校验视频规格并应用解析后的 RTC 编码参数。
    ///
    /// - Parameter videoFormat: 包含尺寸、帧率、可选码率及编码偏好的视频规格。
    /// - Throws: 视频规格无效、默认码率解析或 RTC 配置失败时抛出错误。
    func configure(_ videoFormat: RealtimeVideoFormat) throws
}
