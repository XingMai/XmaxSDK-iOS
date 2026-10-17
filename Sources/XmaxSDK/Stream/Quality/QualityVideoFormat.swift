//
//  QualityVideoFormat.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 从媒体基准计算传输档位，不改变采集或模型生成规格。
enum QualityVideoFormat {

    // 档位配置
    static let scales: [Double] = [1, 0.8, 0.65, 0.5, 0.5]
    static let frameRates = [30, 24, 24, 20, 16]

    /// 综合下行档位和插帧尺寸限制计算实际回传规格。
    ///
    /// - Parameters:
    ///   - baseline: 不随调档变化的媒体原始规格。
    ///   - level: 下行传输档位。
    ///   - interpolationSize: 满足插帧上限的尺寸；`nil` 表示不施加该限制。
    /// - Returns: 同时满足下行档位和可选插帧限制的回传规格。
    static func resolveReturnFormat(_ baseline: RealtimeVideoFormat, level: Int, interpolationSize: CGSize?) -> RealtimeVideoFormat {
        let format = resolve(baseline, level: level, downlink: true)
        guard let interpolationSize, interpolationSize.width < format.size.width else { return format }
        return format.resized(width: Int(interpolationSize.width), height: Int(interpolationSize.height))
    }

    /// 按基准规格计算指定方向和档位的传输格式。
    ///
    /// - Parameters:
    ///   - baseline: 本地媒体原始规格。
    ///   - level: 目标档位，范围限制为 `1...5`。
    ///   - downlink: 是否为下行；下行固定使用 24 fps，上行不超过基准帧率。
    /// - Returns: 完成尺寸、帧率和编码选项映射的传输规格。
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

    /// 按比例缩小尺寸，优先保持精确比例和偶数对齐。
    ///
    /// - Parameters:
    ///   - size: 原始整数像素尺寸。
    ///   - scale: 目标尺寸缩放比例。
    /// - Returns: 偶数对齐的像素尺寸；无法保持精确比例时按像素精度向下对齐。
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

