import Foundation
import CoreGraphics

/// SDK 当前支持的实时生成模型。
public enum RealtimeModel: String, CaseIterable, Sendable {

    /// 国内声网实时生成模型。
    case x2_1_1_preview_cn = "x2.1.1-preview-cn"

    /// 海外声网实时生成模型。
    case x2_1_1_preview_us = "x2.1.1-preview-us"

    /// 模型展示名称。
    public var displayName: String {
        switch self {
        case .x2_1_1_preview_cn: "X2.1.1-preview-cn"
        case .x2_1_1_preview_us: "X2.1.1-preview-us"
        }
    }

    /// 模型专用的会话 API 地址。
    var apiBaseURL: URL {
        switch self {
        case .x2_1_1_preview_cn: URL(string: "https://cloud.xmax.22duck.cn/open/api/v1")!
        case .x2_1_1_preview_us: URL(string: "https://api.xmax.ai/open/api/v1")!
        }
    }

    /// 模型支持的生成分辨率桶；摄像头输入须精确匹配。
    /// 图片和视频保留媒体比例，生成时选择比例最接近的画布。
    /// 空数组表示不限制固定尺寸，按像素面积上下限和对齐规则计算输入尺寸。
    public var resolutionBuckets: [CGSize] {
        [CGSize(width: 1024, height: 1920), CGSize(width: 1920, height: 1024)]
    }

    /// 输入分辨率的最小总像素面积；仅在分辨率桶为空时参与尺寸计算。
    public var minimumInputPixels: Int { 600000 }

    /// 输入分辨率的最大总像素面积；仅在分辨率桶为空时参与尺寸计算。
    public var maximumInputPixels: Int { 2100000 }

    /// 输入宽高需要对齐的像素倍数；仅在分辨率桶为空时参与尺寸计算。
    public var inputSizeAlignment: Int { 32 }

    /// 未指定视频规格时，各媒体来源使用的默认帧率。
    public var defaultFrameRate: Int { 30 }

    /// 摄像头采集使用的默认视频规格。
    public var defaultCameraVideoFormat: RealtimeVideoFormat {
        RealtimeVideoFormat(width: 1024, height: 1920, fps: defaultFrameRate)
    }
}
