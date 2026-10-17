//
//  VideoStatistics.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// RTC 视频上行统计；不可用的指标为 nil。
public struct UplinkVideoStatistics: Equatable, Sendable {

    /// 实际编码宽度，单位为像素。
    public let width: Int?

    /// 实际编码高度，单位为像素。
    public let height: Int?

    /// 实际采集帧率，单位为 fps。
    public let captureFrameRate: Int?

    /// 实际编码帧率，单位为 fps。
    public let encodeFrameRate: Int?

    /// 实际发送帧率，单位为 fps。
    public let sendFrameRate: Int?

    /// 发送码率，单位为 kbps。
    public let bitrateKbps: Int?

    /// 本地到 RTC 服务的丢包率，范围为 0...100。
    public let packetLossPercent: Int?

    /// 创建视频统计信息。
    ///
    /// - Parameters:
    ///   - width: 实际编码宽度，单位为像素。不可用时传入 nil。
    ///   - height: 实际编码高度，单位为像素。不可用时传入 nil。
    ///   - captureFrameRate: 实际采集帧率，单位为 fps。不可用时传入 nil。
    ///   - encodeFrameRate: 实际编码帧率，单位为 fps。不可用时传入 nil。
    ///   - sendFrameRate: 实际发送帧率，单位为 fps。不可用时传入 nil。
    ///   - bitrateKbps: 发送码率，单位为 kbps。不可用时传入 nil。
    ///   - packetLossPercent: 本地到 RTC 服务的丢包率，范围为 0...100。不可用时传入 nil。
    public init(
        width: Int? = nil,
        height: Int? = nil,
        captureFrameRate: Int? = nil,
        encodeFrameRate: Int? = nil,
        sendFrameRate: Int? = nil,
        bitrateKbps: Int? = nil,
        packetLossPercent: Int? = nil
    ) {
        self.width = width
        self.height = height
        self.captureFrameRate = captureFrameRate
        self.encodeFrameRate = encodeFrameRate
        self.sendFrameRate = sendFrameRate
        self.bitrateKbps = bitrateKbps
        self.packetLossPercent = packetLossPercent
    }
}

/// RTC 视频下行统计；不可用的指标为 nil。
public struct DownlinkVideoStatistics: Equatable, Sendable {

    /// 远端用户标识。
    public let userID: String

    /// 接收视频宽度，单位为像素。
    public let width: Int?

    /// 接收视频高度，单位为像素。
    public let height: Int?

    /// 解码帧率，单位为 fps。
    public let decodeFrameRate: Int?

    /// RTC 渲染帧率，单位为 fps；不包含 SDK 插帧后的帧率。
    public let renderFrameRate: Int?

    /// 接收码率，单位为 kbps。
    public let bitrateKbps: Int?

    /// 下行视频丢包率，范围为 0...100。
    public let packetLossPercent: Int?

    /// RTC 媒体端到端时延，单位为毫秒；不代表完整 AI 生成耗时。
    public let endToEndDelayMs: Int?

    /// 创建视频统计信息。
    ///
    /// - Parameters:
    ///   - userID: 远端用户标识。
    ///   - width: 接收视频宽度，单位为像素。不可用时传入 nil。
    ///   - height: 接收视频高度，单位为像素。不可用时传入 nil。
    ///   - decodeFrameRate: 解码帧率，单位为 fps。不可用时传入 nil。
    ///   - renderFrameRate: RTC 渲染帧率，单位为 fps；不包含 SDK 插帧后的帧率。不可用时传入 nil。
    ///   - bitrateKbps: 接收码率，单位为 kbps。不可用时传入 nil。
    ///   - packetLossPercent: 下行视频丢包率，范围为 0...100。不可用时传入 nil。
    ///   - endToEndDelayMs: RTC 媒体端到端时延，单位为毫秒；不代表完整 AI 生成耗时。不可用时传入 nil。
    public init(
        userID: String,
        width: Int? = nil,
        height: Int? = nil,
        decodeFrameRate: Int? = nil,
        renderFrameRate: Int? = nil,
        bitrateKbps: Int? = nil,
        packetLossPercent: Int? = nil,
        endToEndDelayMs: Int? = nil
    ) {
        self.userID = userID
        self.width = width
        self.height = height
        self.decodeFrameRate = decodeFrameRate
        self.renderFrameRate = renderFrameRate
        self.bitrateKbps = bitrateKbps
        self.packetLossPercent = packetLossPercent
        self.endToEndDelayMs = endToEndDelayMs
    }
}

/// 主线程视频上行统计回调；停止发布或断开连接时收到 nil。
public typealias UplinkVideoStatisticsListener = @MainActor @Sendable (UplinkVideoStatistics?) -> Void

/// 主线程视频下行统计回调；结果流清理或断开连接时收到 nil。
public typealias DownlinkVideoStatisticsListener = @MainActor @Sendable (DownlinkVideoStatistics?) -> Void
