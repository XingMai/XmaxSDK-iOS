/// Xmax 实时生成会话。
struct RealtimeSession: Equatable, Sendable {
    let id: String
    let userID: String?
    let status: String?
    let connection: RealtimeSessionConnection?
    let closeReason: String?
}
