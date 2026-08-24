import Foundation

/// 对象存储上传完成后的中性结果。
struct StoredFile: Equatable, Sendable {
    let url: URL
    let objectKey: String
    let etag: String?
}
