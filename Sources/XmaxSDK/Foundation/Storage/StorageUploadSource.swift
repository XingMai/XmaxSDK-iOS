import Foundation

/// 对象存储上传支持的二进制数据或本地文件。
enum StorageUploadSource: Equatable, Sendable {
    case data(Data)
    case file(URL)
}
