/// 标识 RTC 房间中的一条远端主流。
struct RemoteStream: Equatable, Hashable, Sendable {
    let roomID: String
    let userID: String

    /// 生成跨房间唯一的远端流键。
    var key: String {
        "\(roomID):\(userID)"
    }
}
