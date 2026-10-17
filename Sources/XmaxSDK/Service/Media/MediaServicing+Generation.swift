import Foundation

extension MediaServicing {
    /// 选择最接近媒体比例的生成画布，不改变本地媒体规格。
    ///
    /// - Parameter size: 媒体显示尺寸。
    /// - Returns: 比例最接近的模型分辨率桶，或满足模型面积与对齐约束的尺寸。
    /// - Throws: 媒体尺寸无效时抛出错误。
    func resolveGenerationSize(_ size: CGSize) throws -> CGSize {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else {
            throw XmaxError(code: .invalidConfiguration, message: "Media dimensions must be positive")
        }

        let aspect = size.width / size.height
        return try model.resolutionBuckets.min {
            abs(log(aspect / ($0.width / $0.height))) < abs(log(aspect / ($1.width / $1.height)))
        } ?? resolveModelInputSize(size)
    }
}
