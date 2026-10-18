//
//  MediaServicing+Generation.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

public extension MediaServicing {
    /// 选择最接近媒体比例的生成画布，不改变本地媒体规格。
    ///
    /// - Parameter resolvedMediaSize: 处理后的本地媒体尺寸。
    /// - Returns: 比例最接近的模型分辨率桶，或满足模型面积与对齐约束的尺寸。
    /// - Throws: 媒体尺寸无效时抛出错误。
    func resolveGenerationSize(_ resolvedMediaSize: CGSize) throws -> CGSize {
        guard resolvedMediaSize.width.isFinite, resolvedMediaSize.height.isFinite,
              resolvedMediaSize.width > 0, resolvedMediaSize.height > 0 else {
            throw XmaxError(code: .invalidConfiguration, message: "Media dimensions must be positive")
        }

        let aspect = resolvedMediaSize.width / resolvedMediaSize.height
        if let bucket = model.resolutionBuckets.min(by: {
            abs(log(aspect / ($0.width / $0.height))) < abs(log(aspect / ($1.width / $1.height)))
        }) {
            return bucket
        }

        let size = try validatedSize(resolvedMediaSize)
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
}

private extension MediaServicing {
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
