import Foundation

/// 表示下载到本地的文件。
public struct XmaxDownloadedFile: Equatable, Sendable {

    /// 下载后的本地文件地址。
    public let fileURL: URL

    /// 下载文件的字节数。
    public let byteCount: Int64

    init(fileURL: URL, byteCount: Int64) {
        self.fileURL = fileURL
        self.byteCount = byteCount
    }
}
