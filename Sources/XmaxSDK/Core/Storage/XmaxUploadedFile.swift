import Foundation

/// 表示上传成功后的远端文件。
public struct XmaxUploadedFile: Equatable, Sendable {

    /// 文件的远端访问地址。
    public let url: URL

    /// 文件在对象存储中的标识。
    public let objectKey: String

    /// 对象存储返回的可选实体标识。
    public let etag: String?

    init(url: URL, objectKey: String, etag: String?) {
        self.url = url
        self.objectKey = objectKey
        self.etag = etag
    }
}
