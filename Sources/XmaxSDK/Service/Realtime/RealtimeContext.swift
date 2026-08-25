import Foundation

/// 单次实时生成任务的文本和参考资源上下文。
public struct RealtimeContext: Equatable, Sendable {

    /// 实时生成使用的文本条件。
    public let prompt: String

    /// 已上传参考图片的可选远端路径。
    public let referencePath: String?

    /// 创建实时生成条件并规范化文本和参考路径。
    public init(
        prompt: String,
        referencePath: String? = nil
    ) {
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReferencePath = referencePath?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.referencePath = normalizedReferencePath?.isEmpty == false
            ? normalizedReferencePath
            : nil
    }
}
