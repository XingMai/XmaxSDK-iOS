import CoreGraphics

/// SDK 当前支持的实时生成模型。
public enum RealtimeModel: String, CaseIterable, Sendable {

    /// Xmax X2.0 实时生成模型。
    case x2_0 = "x2.0"

    /// Xmax X2.0 Pro 实时生成模型。
    case x2_0_pro = "x2.0-pro"

    /// 模型支持的输入分辨率桶；非空时宽高必须精确匹配，不进行自动缩放。
    /// 空数组表示不限制固定尺寸，按像素面积上下限和对齐规则计算输入尺寸。
    public var resolutionBuckets: [CGSize] {
        switch self {
        case .x2_0: []
        case .x2_0_pro: [
            CGSize(width: 1024, height: 1920),
            CGSize(width: 1920, height: 1024)
        ]
        }
    }

    /// 输入分辨率的最小总像素面积；仅在分辨率桶为空时参与尺寸计算。
    public var minimumInputPixels: Int { 600000 }

    /// 输入分辨率的最大总像素面积；仅在分辨率桶为空时参与尺寸计算。
    public var maximumInputPixels: Int {
        switch self {
        case .x2_0: 1280000
        case .x2_0_pro: 2100000
        }
    }

    /// 输入宽度和高度分别需要对齐的像素倍数；仅在分辨率桶为空时参与尺寸计算。
    public var inputSizeAlignment: Int { 32 }

    /// 未指定视频规格时，各媒体来源使用的默认帧率。
    public var defaultFrameRate: Int {
        switch self {
        case .x2_0: 24
        case .x2_0_pro: 30
        }
    }

    /// 摄像头采集使用的默认视频规格。
    public var defaultCameraVideoFormat: RealtimeVideoFormat {
        switch self {
        case .x2_0:
            RealtimeVideoFormat(width: 832, height: 1472, fps: defaultFrameRate)
        case .x2_0_pro:
            RealtimeVideoFormat(width: 1024, height: 1920, fps: defaultFrameRate)
        }
    }
}
