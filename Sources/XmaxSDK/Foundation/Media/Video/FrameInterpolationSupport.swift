//
//  FrameInterpolationSupport.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics
#if !targetEnvironment(simulator)
import VideoToolbox
#endif

/// Checks low-latency frame interpolation support.
enum FrameInterpolationSupport {

    /// Whether the system and device support frame interpolation.
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

    /// Checks interpolation support for the requested dimensions.
    ///
    /// - Parameter size: The video dimensions, in pixels.
    ///
    /// - Returns: `true` if the system, device, and dimensions support interpolation.
    static func supports(
        size: CGSize
    ) -> Bool {
        guard isSupported,
            let width = integralDimension(size.width),
            let height = integralDimension(size.height)
        else {
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

    /// Converts a valid dimension to a positive integer.
    ///
    /// - Parameter value: The dimension to convert.
    ///
    /// - Returns: The positive integer, or `nil` if the dimension is invalid.
    static func integralDimension(
        _ value: CGFloat
    ) -> Int? {
        guard value.isFinite,
            value > 0,
            value <= CGFloat(Int.max)
        else {
            return nil
        }
        let roundedValue = value.rounded()
        guard roundedValue == value else {
            return nil
        }
        return Int(roundedValue)
    }
}
