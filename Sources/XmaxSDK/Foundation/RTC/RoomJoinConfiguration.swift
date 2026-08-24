/// RTC 房间加入参数。
struct RoomJoinConfiguration: Equatable, Sendable {
    let roomID: String
    let userID: String
    let token: String
}
