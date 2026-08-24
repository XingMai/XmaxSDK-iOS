/// 对象存储请求使用的服务地址、存储桶和临时凭证。
struct StorageConfiguration: Equatable, Sendable {
    let bucket: String
    let region: String
    let endpoint: String
    let credential: StorageCredential
}
