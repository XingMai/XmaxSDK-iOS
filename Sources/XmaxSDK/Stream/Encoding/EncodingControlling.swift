//
//  EncodingControlling.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 定义实时视频编码参数的配置能力。
protocol EncodingControlling: Sendable {

    /// 校验并应用实时视频编码格式。
    func configure(_ videoFormat: RealtimeVideoFormat) throws
}
