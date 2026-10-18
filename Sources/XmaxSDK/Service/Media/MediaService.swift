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

/// 提供模型输入尺寸和平台媒体能力相关的业务规则。
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

    /// 计算满足模型输入约束的尺寸。
    ///
    /// - Parameter size: 指定的视频格式尺寸；未指定格式时为原始媒体的显示尺寸。
    /// - Returns: 模型分辨率桶非空时，精确匹配后原样返回；为空时按像素面积上下限及对齐要求计算。
    /// - Throws: 尺寸无效或未匹配模型支持的分辨率桶时抛出 `XmaxError`。
    func resolveModelInputSize(_ size: CGSize) throws -> CGSize {
        let buckets = model.resolutionBuckets
        if !buckets.isEmpty {
            guard buckets.contains(size) else {
                let supportedSizes = buckets.map { "\(Int($0.width))×\(Int($0.height))" }.joined(separator: ", ")
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Model \(model.rawValue) does not support input resolution " +
                        "\(size.width)×\(size.height). Supported resolutions: \(supportedSizes)"
                )
            }
            return size
        }

        let size = try validatedSize(size)
        let pixels = Double(size.width) * Double(size.height)
        let scale: Double
        let rounding: (Double) -> Double

        if pixels < Double(model.minimumInputPixels) {
            scale = sqrt(Double(model.minimumInputPixels) / pixels)
            rounding = ceil
        } else if pixels > Double(model.maximumInputPixels) {
            scale = sqrt(Double(model.maximumInputPixels) / pixels)
            rounding = floor
        } else {
            scale = 1
            rounding = round
        }

        let alignment = Double(model.inputSizeAlignment)
        let width = max(
            Int(rounding(Double(size.width) * scale / alignment)) *
                model.inputSizeAlignment,
            model.inputSizeAlignment
        )
        let height = max(
            Int(rounding(Double(size.height) * scale / alignment)) *
                model.inputSizeAlignment,
            model.inputSizeAlignment
        )
        let alignedPixels = width * height
        if (model.minimumInputPixels...model.maximumInputPixels).contains(alignedPixels) {
            return CGSize(width: width, height: height)
        }

        // 对齐可能使边界附近的尺寸越界，选择满足面积限制且最接近目标的尺寸。
        return boundedAlignedSize(
            width: Double(size.width) * scale,
            height: Double(size.height) * scale
        )
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

        // 使用最简宽高比的整数倍，避免分别取整导致比例发生变化。
        var divisor = width
        var remainder = height
        while remainder != 0 {
            (divisor, remainder) = (remainder, divisor % remainder)
        }
        let ratioWidth = width / divisor
        let ratioHeight = height / divisor
        let alignedScale = Int(floor(Double(divisor) * scale / 4)) * 4
        if alignedScale >= 4 {
            return CGSize(
                width: ratioWidth * alignedScale,
                height: ratioHeight * alignedScale
            )
        }

        let alignedWidth = Int(floor(Double(width) * scale / 4)) * 4
        let alignedHeight = Int(floor(Double(height) * scale / 4)) * 4
        guard alignedWidth >= 4, alignedHeight >= 4 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "No 4-aligned target size is available within the size limits"
            )
        }
        return CGSize(width: alignedWidth, height: alignedHeight)
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
    /// 选择满足模型面积与对齐约束、最接近目标宽高的尺寸。
    ///
    /// - Parameters:
    ///   - width: 缩放后的目标宽度，单位为像素。
    ///   - height: 缩放后的目标高度，单位为像素。
    /// - Returns: 在合法尺寸中相对宽高偏差最小的候选尺寸。
    func boundedAlignedSize(width: Double, height: Double) -> CGSize {
        let alignment = model.inputSizeAlignment
        let unitPixels = alignment * alignment
        let minimumUnits = (model.minimumInputPixels + unitPixels - 1) / unitPixels
        let maximumUnits = model.maximumInputPixels / unitPixels
        var bestSize = CGSize.zero
        var bestDistance = Double.infinity

        for widthUnits in 1...maximumUnits {
            let minimumHeight = (minimumUnits + widthUnits - 1) / widthUnits
            let maximumHeight = maximumUnits / widthUnits
            guard minimumHeight <= maximumHeight else { continue }
            let heightUnits = min(
                max(Int((height / Double(alignment)).rounded()), minimumHeight),
                maximumHeight
            )
            let candidateWidth = Double(widthUnits * alignment)
            let candidateHeight = Double(heightUnits * alignment)
            let distance = pow((candidateWidth - width) / width, 2)
                + pow((candidateHeight - height) / height, 2)
            if distance < bestDistance {
                bestDistance = distance
                bestSize = CGSize(width: candidateWidth, height: candidateHeight)
            }
        }
        return bestSize
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

    /// 校验媒体宽高并将其取整为至少一个像素。
    ///
    /// - Parameter size: 待校验的媒体尺寸。
    /// - Returns: 宽高均为正整数的媒体尺寸。
    /// - Throws: 宽高非有限、非正数或超出整数范围时抛出配置错误。
    func validatedSize(_ size: CGSize) throws -> CGSize {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              size.width < CGFloat(Int.max),
              size.height < CGFloat(Int.max) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image width and height must be finite numbers " +
                    "greater than zero"
            )
        }
        return CGSize(
            width: max(size.width.rounded(), 1),
            height: max(size.height.rounded(), 1)
        )
    }
}
