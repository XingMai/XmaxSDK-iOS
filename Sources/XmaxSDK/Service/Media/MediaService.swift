import CoreGraphics

/// 提供模型输入尺寸和平台媒体能力相关的业务规则。
final class MediaService: MediaServicing, Sendable {

    // 模型约束
    let model: RealtimeModel

    // 插帧约束
    private static let maximumFrameInterpolationPixels = 900000

    init(model: RealtimeModel = .x2_0) {
        self.model = model
    }

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

    func resolveFrameInterpolationSize(_ size: CGSize) throws -> CGSize {
        guard let width = Self.integralDimension(size.width),
              let height = Self.integralDimension(size.height) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video dimensions must be positive integers"
            )
        }

        // 使用最简宽高比的整数倍，避免分别取整导致比例发生变化。
        var divisor = width
        var remainder = height
        while remainder != 0 {
            (divisor, remainder) = (remainder, divisor % remainder)
        }
        let ratioWidth = width / divisor
        let ratioHeight = height / divisor
        let maximumSquaredScale = Self.maximumFrameInterpolationPixels
            / ratioWidth / ratioHeight
        let scale = min(divisor, Int(sqrt(Double(maximumSquaredScale))))
        let evenScale = scale - scale % 2
        guard evenScale >= 2 else {
            throw XmaxError(
                code: .frameInterpolationUnsupported,
                message: "No proportional frame interpolation size is available",
                severity: .recoverable
            )
        }
        return CGSize(
            width: ratioWidth * evenScale,
            height: ratioHeight * evenScale
        )
    }

    func supportsFrameInterpolation(for size: CGSize) -> Bool {
        guard Self.supportsFrameInterpolationSize(size) else {
            return false
        }
        return FrameInterpolationSupport.supports(size: size)
    }

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
