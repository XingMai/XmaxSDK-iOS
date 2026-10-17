@preconcurrency import AgoraRtcKit

/// 在声网质量事件与中性质量模型之间转换。
enum RtcQualityConverter {
    static func convertLevel(_ quality: AgoraNetworkQuality) -> RtcQualityLevel {
        RtcQualityLevel(rawValue: Int(quality.rawValue)) ?? .unknown
    }
}
