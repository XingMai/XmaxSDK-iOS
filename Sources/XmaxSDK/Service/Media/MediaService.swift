//
//  MediaService.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics

/// 提供本地媒体、回传尺寸和平台媒体能力相关的业务规则。
final class MediaService: MediaServicing, Sendable {

    // 模型约束
    let model: RealtimeModel

    // 插帧约束
    private static let maximumFrameInterpolationPixels = 900000

    /// 创建采用指定模型尺寸规则的媒体服务。
    ///
    /// - Parameter model: 用于解析输入尺寸的生成模型。
    init(model: RealtimeModel = .x2_1_1_preview_cn) {
        self.model = model
    }

    /// 计算本地媒体帧尺寸，并校验摄像头的模型分辨率桶。
    ///
    /// - Parameters:
    ///   - size: 摄像头请求尺寸或图片、视频按显示方向解析后的整数像素尺寸。
    ///   - source: 媒体来源；摄像头须精确匹配模型已配置的分辨率桶。
    /// - Returns: 不放大、不超过模型最大像素面积的 4 对齐尺寸，优先保持精确比例。
    /// - Throws: 尺寸无效、摄像头不匹配分辨率桶或无法形成有效输出尺寸时抛出错误。
    func resolveMediaSize(_ size: CGSize, source: RealtimeMediaSource) throws -> CGSize {
        guard let width = Self.integralDimension(size.width),
              let height = Self.integralDimension(size.height) else {
            throw XmaxError(code: .invalidConfiguration, message: "Media dimensions must be positive integers")
        }

        let buckets = model.resolutionBuckets
        if source == .camera, !buckets.isEmpty, !buckets.contains(size) {
            let supportedSizes = buckets.map { "\(Int($0.width))×\(Int($0.height))" }.joined(separator: ", ")
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Model \(model.rawValue) does not support camera resolution " +
                    "\(width)×\(height). Supported resolutions: \(supportedSizes)"
            )
        }

        let pixels = Double(width) * Double(height)
        let scale = min(1, sqrt(Double(model.maximumInputPixels) / pixels))
        return try alignedSize(width: width, height: height, scale: scale, alignment: 4)
    }

    /// 综合档位尺寸上限和可选插帧限制，计算最终回传尺寸。
    ///
    /// - Parameters:
    ///   - sourceSize: 原始媒体的整数像素尺寸，用于确定比例和不放大的边界。
    ///   - maximumSize: 下行档位允许的宽高上限，可包含小数像素。
    ///   - frameInterpolationEnabled: 是否额外限制总像素不超过 900000；不检查设备能力。
    /// - Returns: 不超过上限、宽高均为 4 的倍数的尺寸；优先精确等比，无法等比时分别向下对齐。
    /// - Throws: 尺寸无效，或约束内无法容纳至少 4 × 4 像素时抛出 `XmaxError`。
    func resolveTargetSize(
        _ sourceSize: CGSize,
        maximumSize: CGSize,
        frameInterpolationEnabled: Bool
    ) throws -> CGSize {
        guard let width = Self.integralDimension(sourceSize.width),
              let height = Self.integralDimension(sourceSize.height),
              maximumSize.width.isFinite, maximumSize.width > 0,
              maximumSize.height.isFinite, maximumSize.height > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Source dimensions must be positive integers and target bounds must be positive and finite"
            )
        }

        var scale = min(1, min(Double(maximumSize.width) / Double(width), Double(maximumSize.height) / Double(height)))
        let targetPixels = (Double(width) * scale) * (Double(height) * scale)
        if frameInterpolationEnabled, targetPixels > Double(Self.maximumFrameInterpolationPixels) {
            scale *= sqrt(Double(Self.maximumFrameInterpolationPixels) / targetPixels)
        }

        return try alignedSize(width: width, height: height, scale: scale, alignment: 4)
    }

    /// 判断当前设备是否支持对指定分辨率的视频进行插帧。
    ///
    /// - Parameter size: 客户端收到的、用于插帧处理的视频分辨率。
    /// - Returns: 当前系统、设备和视频规格均支持插帧时返回 `true`。
    func supportsFrameInterpolation(for size: CGSize) -> Bool {
        guard Self.supportsFrameInterpolationSize(size) else {
            return false
        }
        return FrameInterpolationSupport.supports(size: size)
    }

    /// 检查尺寸是否为正整数且满足插帧像素面积限制。
    ///
    /// - Parameter size: 待检查的视频尺寸，单位为像素。
    /// - Returns: 尺寸合法且总像素不超过插帧上限时返回 `true`；不检查设备能力。
    static func supportsFrameInterpolationSize(_ size: CGSize) -> Bool {
        guard let width = integralDimension(size.width),
              let height = integralDimension(size.height) else {
            return false
        }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(
            by: height
        )
        return !overflow && pixelCount <= maximumFrameInterpolationPixels
    }
}

private extension MediaService {
    /// 在指定缩放范围内计算对齐尺寸，优先使用最简宽高比的整数倍。
    ///
    /// - Parameters:
    ///   - width: 原始整数像素宽度。
    ///   - height: 原始整数像素高度。
    ///   - scale: 不超过 1 的等比缩放比例。
    ///   - alignment: 宽高需要对齐的像素倍数。
    /// - Returns: 不超过缩放边界的对齐尺寸，无法精确等比时分别向下对齐。
    /// - Throws: 缩放边界内无法容纳一个对齐单位时抛出错误。
    func alignedSize(width: Int, height: Int, scale: Double, alignment: Int) throws -> CGSize {
        // 使用最简宽高比的整数倍，避免分别取整导致比例发生变化。
        var divisor = width
        var remainder = height
        while remainder != 0 {
            (divisor, remainder) = (remainder, divisor % remainder)
        }
        let ratioWidth = width / divisor
        let ratioHeight = height / divisor
        let alignedScale = Int(floor(Double(divisor) * scale / Double(alignment))) * alignment
        if alignedScale >= alignment {
            return CGSize(
                width: ratioWidth * alignedScale,
                height: ratioHeight * alignedScale
            )
        }

        let alignedWidth = Int(floor(Double(width) * scale / Double(alignment))) * alignment
        let alignedHeight = Int(floor(Double(height) * scale / Double(alignment))) * alignment
        guard alignedWidth >= alignment, alignedHeight >= alignment else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "No aligned video size is available within the size limits"
            )
        }
        return CGSize(width: alignedWidth, height: alignedHeight)
    }

    /// 将有效的正整数像素边长转换为整数。
    ///
    /// - Parameter value: 待校验的像素边长。
    /// - Returns: 可安全转换的正整数；非有限值、非整数或越界时返回 `nil`。
    static func integralDimension(_ value: CGFloat) -> Int? {
        guard value.isFinite,
              value > 0,
              value < CGFloat(Int.max) else {
            return nil
        }
        let roundedValue = value.rounded()
        guard roundedValue == value else { return nil }
        return Int(roundedValue)
    }
}
