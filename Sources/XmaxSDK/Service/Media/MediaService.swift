import CoreGraphics

/// 提供与模型输入约束相关的媒体业务规则。
final class MediaService: MediaServicing, Sendable {

    // 模型约束
    private static let minimumModelPixels = 600_000
    private static let maximumModelPixels = 1_280_000
    private static let modelSizeAlignment = 32

    func resolveModelInputSize(_ size: CGSize) throws -> CGSize {
        let size = try validatedSize(size)
        let pixels = Double(size.width) * Double(size.height)
        let scale: Double
        let rounding: (Double) -> Double

        if pixels < Double(Self.minimumModelPixels) {
            scale = sqrt(Double(Self.minimumModelPixels) / pixels)
            rounding = ceil
        } else if pixels > Double(Self.maximumModelPixels) {
            scale = sqrt(Double(Self.maximumModelPixels) / pixels)
            rounding = floor
        } else {
            scale = 1
            rounding = round
        }

        let alignment = Double(Self.modelSizeAlignment)
        let width = max(
            Int(rounding(Double(size.width) * scale / alignment)) *
                Self.modelSizeAlignment,
            Self.modelSizeAlignment
        )
        let height = max(
            Int(rounding(Double(size.height) * scale / alignment)) *
                Self.modelSizeAlignment,
            Self.modelSizeAlignment
        )
        return CGSize(width: width, height: height)
    }
}

private extension MediaService {
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
