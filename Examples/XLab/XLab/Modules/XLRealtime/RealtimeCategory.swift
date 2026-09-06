/// 实时页面共用的生成分类。
struct RealtimeCategory: Identifiable, Sendable {
    enum Content: Sendable {
        case references(categoryID: String)
        case instruction
        case prompt
    }

    let id: String
    let name: String
    let content: Content

    /// 分类默认提示词，自由模式使用用户输入。
    let defaultPrompt: String

    static let all = [
        RealtimeCategory(
            id: "charx",
            name: "换形象",
            content: .references(categoryID: "charx"),
            defaultPrompt: "视频中角色替换成参考图中角色"
        ),
        RealtimeCategory(
            id: "clothx",
            name: "换装",
            content: .references(categoryID: "clothx"),
            defaultPrompt: "视频中人物衣服替换成参考图中衣服"
        ),
        RealtimeCategory(
            id: "vibex",
            name: "换风格",
            content: .references(categoryID: "vibex"),
            defaultPrompt: "视频风格变为参考图指定的风格"
        ),
        RealtimeCategory(
            id: "dimx",
            name: "虚拟召唤",
            content: .references(categoryID: "dimx"),
            defaultPrompt: "指定角色在场景中互动"
        ),
        RealtimeCategory(
            id: "mox",
            name: "触控动图",
            content: .instruction,
            defaultPrompt: "让画面自然动起来"
        ),
        RealtimeCategory(
            id: "free",
            name: "自由",
            content: .prompt,
            defaultPrompt: ""
        ),
    ]

    /// 获取分类的默认提示词。
    ///
    /// - Parameter categoryID: 分类标识。
    /// - Returns: 分类默认提示词，分类不存在时返回空字符串。
    static func defaultPrompt(for categoryID: String) -> String {
        all.first { $0.id == categoryID }?.defaultPrompt ?? ""
    }
}
