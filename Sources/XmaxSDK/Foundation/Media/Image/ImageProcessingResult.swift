import Foundation

/// Foundation 图片处理完成后的中性结果。
struct ImageProcessingResult: Equatable, Sendable {
    let data: Data
    let width: Int
    let height: Int
    let contentType: String
}
