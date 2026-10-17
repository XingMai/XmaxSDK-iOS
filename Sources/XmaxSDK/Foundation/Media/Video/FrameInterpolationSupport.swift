//
//  FrameInterpolationSupport.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics
#if !targetEnvironment(simulator)
import VideoToolbox
#endif

/// 集中判断当前运行环境和视频规格是否支持低延迟插帧。
enum FrameInterpolationSupport {

    // 平台能力
    static var isSupported: Bool {
#if targetEnvironment(simulator)
        false
#else
        if #available(iOS 26.0, *) {
            VTLowLatencyFrameInterpolationConfiguration.isSupported
        } else {
            false
        }
#endif
    }

    /// 判断当前设备是否支持指定尺寸的低延迟插帧。
    ///
    /// - Parameter size: 待插帧视频的像素尺寸。
    /// - Returns: 系统、设备及尺寸均满足插帧要求时返回 `true`。
    static func supports(size: CGSize) -> Bool {
        guard isSupported,
              let width = integralDimension(size.width),
              let height = integralDimension(size.height) else {
            return false
        }

#if targetEnvironment(simulator)
        return false
#else
        if #available(iOS 26.0, *) {
            return VTLowLatencyFrameInterpolationConfiguration(
                frameWidth: width,
                frameHeight: height,
                numberOfInterpolatedFrames: 1
            ) != nil
        }
        return false
#endif
    }
}

private extension FrameInterpolationSupport {
    /// 将有效的正整数尺寸转换为整数。
    ///
    /// - Parameter value: 待转换的尺寸分量。
    /// - Returns: 可表示的正整数；尺寸无效时返回 `nil`。
    static func integralDimension(_ value: CGFloat) -> Int? {
        guard value.isFinite,
              value > 0,
              value <= CGFloat(Int.max) else {
            return nil
        }
        let roundedValue = value.rounded()
        guard roundedValue == value else { return nil }
        return Int(roundedValue)
    }
}
