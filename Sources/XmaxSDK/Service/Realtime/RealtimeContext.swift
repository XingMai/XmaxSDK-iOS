import Foundation

/// 单次实时生成任务的文本和参考资源上下文。
struct RealtimeContext: Equatable, Sendable {
    let prompt: String
    let referencePath: String?

    init(
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
