/// SDK 当前支持的实时生成模型。
public enum RealtimeModel: String, CaseIterable, Sendable {

    /// Xmax X2.0 实时生成模型。
    case x2_0 = "x2.0"

    /// 模型支持的本地媒体来源。
    public var supportedMediaSources: Set<RealtimeMediaSource> {
        switch self {
        case .x2_0: [.camera, .video, .image]
        }
    }

    /// 输入分辨率的最小总像素面积。
    public var minimumInputPixels: Int { 600000 }

    /// 输入分辨率的最大总像素面积。
    public var maximumInputPixels: Int {
        switch self {
        case .x2_0: 1280000
        }
    }

    /// 输入宽度和高度分别需要对齐的像素倍数。
    public var inputSizeAlignment: Int { 32 }

    /// 未指定视频规格时，各媒体来源使用的默认帧率。
    public var defaultFrameRate: Int {
        switch self {
        case .x2_0: 24
        }
    }

    /// 摄像头采集使用的默认视频规格。
    public var defaultCameraVideoFormat: RealtimeVideoFormat {
        switch self {
        case .x2_0:
            RealtimeVideoFormat(width: 832, height: 1472, fps: defaultFrameRate)
        }
    }
}
