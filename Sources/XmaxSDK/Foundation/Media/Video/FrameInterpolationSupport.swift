import CoreGraphics
#if !targetEnvironment(simulator)
import VideoToolbox
#endif

/// 集中判断当前运行环境和视频规格是否支持低延迟插帧。
enum FrameInterpolationSupport {

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
