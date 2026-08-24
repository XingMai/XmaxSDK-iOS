@preconcurrency import VolcEngineRTC

/// 在火山 RTC 质量事件和中性质量模型之间转换。
enum RtcQualityConverter {

    /// 转换单个网络质量等级。
    static func convertLevel(
        _ quality: ByteRTCNetworkQuality
    ) -> RtcQualityLevel {
        switch quality {
        case .excellent:
            .excellent
        case .good:
            .good
        case .poor:
            .poor
        case .bad:
            .bad
        case .veryBad:
            .veryBad
        case .down:
            .down
        default:
            .unknown
        }
    }

    /// 取所有远端接收质量中的最差等级。
    static func resolveDownlinkLevel(
        _ remoteQualities: [ByteRTCNetworkQualityStats]
    ) -> RtcQualityLevel {
        let worstQuality = remoteQualities
            .map(\.rxQuality)
            .filter { quality in
                quality.rawValue >= ByteRTCNetworkQuality.unknown.rawValue &&
                    quality.rawValue <= ByteRTCNetworkQuality.down.rawValue
            }
            .max { lhs, rhs in
                lhs.rawValue < rhs.rawValue
            } ?? .unknown

        return convertLevel(worstQuality)
    }

    /// 将性能告警原因解析为受限、恢复或不可识别状态。
    static func resolvePerformanceLimited(
        _ reason: ByteRTCPerformanceAlarmReason
    ) -> Bool? {
        switch reason {
        case .bandwidthFallback, .fallback:
            true
        case .bandwidthResumed, .resumed:
            false
        default:
            nil
        }
    }
}
