import Foundation

/// 远端文件下载完成后的中性结果。
struct DownloadedFile: Equatable, Sendable {

    let fileURL: URL
    let byteCount: Int64
}
