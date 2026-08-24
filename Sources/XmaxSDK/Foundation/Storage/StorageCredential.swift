/// 对象存储单次请求使用的临时凭证。
struct StorageCredential: Equatable, Sendable {

    let accessKeyID: String
    let secretAccessKey: String
    let sessionToken: String
}
