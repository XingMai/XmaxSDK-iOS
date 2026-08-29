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

    static let all = [
        RealtimeCategory(
            id: "charx",
            name: "换形象",
            content: .references(categoryID: "charx")
        ),
        RealtimeCategory(
            id: "clothx",
            name: "换装",
            content: .references(categoryID: "clothx")
        ),
        RealtimeCategory(
            id: "vibex",
            name: "换风格",
            content: .references(categoryID: "vibex")
        ),
        RealtimeCategory(
            id: "dimx",
            name: "虚拟召唤",
            content: .references(categoryID: "dimx")
        ),
        RealtimeCategory(
            id: "mox",
            name: "触控动图",
            content: .instruction
        ),
        RealtimeCategory(
            id: "free",
            name: "自由",
            content: .prompt
        ),
    ]
}
