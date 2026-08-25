/// 图片处理会话读取到的基础信息。
struct ImageProcessingMetadata: Equatable, Sendable {
    let width: Int
    let height: Int
    let contentType: String
}
