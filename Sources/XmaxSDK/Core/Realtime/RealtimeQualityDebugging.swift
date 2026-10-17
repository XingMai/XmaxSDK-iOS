//
//  RealtimeQualityDebugging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 仅供示例和内部调试使用的传输档位快照。
@_spi(QualityDebug)
public struct RealtimeQualityDebugState: Sendable {

    // 传输档位
    /// 上行逻辑档位，取值为 1...5。
    public let uplinkLevel: Int

    /// 下行逻辑档位，取值为 1...5。
    public let downlinkLevel: Int


    // 请求规格
    /// 请求的上行编码规格，不代表 RTC 实际发送规格。
    public let uplink: RealtimeVideoFormat

    /// 请求的回传规格，不代表服务端已经切换完成。
    public let downlink: RealtimeVideoFormat


    // 渲染配置
    /// 当前插帧开关。
    public let interpolationEnabled: Bool
}

/// SDK 内部调试能力，不属于正式集成接口。
@_spi(QualityDebug)
public protocol RealtimeQualityDebugging: Actor {

    // 传输状态
    /// 当前生成的传输规格；没有活动生成时返回 nil。
    var qualityDebugState: RealtimeQualityDebugState? { get async }

    /// 手动选择一次档位，之后继续自动调档。
    ///
    /// - Parameters:
    ///   - level: 目标档位，取值为 1...5。
    ///   - downlink: true 调整下行，false 调整上行。
    /// - Throws: 档位无效、没有活动生成、操作冲突或配置失败时抛出错误。
    func selectQualityLevel(_ level: Int, downlink: Bool) async throws
}
