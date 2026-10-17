//
//  QualityVideoFormat.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 从媒体基准计算传输档位，不改变采集或模型生成规格。
enum QualityVideoFormat {
    static let scales: [Double] = [1, 0.8, 0.65, 0.5, 0.5]
    static let frameRates = [30, 24, 24, 20, 16]

    static func resolveReturnFormat(_ baseline: RealtimeVideoFormat, level: Int, interpolationSize: CGSize?) -> RealtimeVideoFormat {
        let format = resolve(baseline, level: level, downlink: true)
        guard let interpolationSize, interpolationSize.width < format.size.width else { return format }
        return format.resized(width: Int(interpolationSize.width), height: Int(interpolationSize.height))
    }

    static func resolve(_ baseline: RealtimeVideoFormat, level: Int, downlink: Bool) -> RealtimeVideoFormat {
        let index = min(5, max(1, level)) - 1
        let shortSide = min(baseline.width, baseline.height)
        let scale = max(scales[index], Double(min(shortSide, 240)) / Double(shortSide))
        let size = scaledSize(baseline.size, scale: scale)
        return RealtimeVideoFormat(
            width: Int(size.width), height: Int(size.height),
            fps: downlink ? 24 : min(baseline.fps, frameRates[index]),
            minimumBitrate: downlink ? nil : baseline.minimumBitrate,
            maximumBitrate: downlink ? nil : baseline.maximumBitrate,
            encoderPreference: baseline.encoderPreference
        )
    }

    /// 优先采用原比例的偶数尺寸；无法缩小时按像素精度向下对齐。
    static func scaledSize(_ size: CGSize, scale: Double) -> CGSize {
        let width = Int(size.width)
        let height = Int(size.height)
        var divisor = width
        var remainder = height
        while remainder != 0 { (divisor, remainder) = (remainder, divisor % remainder) }
        let units = Int(floor(Double(divisor) * scale + 0.0000001)) / 2 * 2
        if units >= 2 {
            return CGSize(width: width / divisor * units, height: height / divisor * units)
        }
        return CGSize(
            width: max(2, Int(floor(Double(width) * scale / 2)) * 2),
            height: max(2, Int(floor(Double(height) * scale / 2)) * 2)
        )
    }
}

