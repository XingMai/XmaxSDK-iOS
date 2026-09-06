/// 实时生成模型支持的本地媒体来源。
public enum RealtimeMediaSource: String, CaseIterable, Sendable {

    /// 摄像头
    case camera

    /// 视频
    case video

    /// 图片
    case image
}
