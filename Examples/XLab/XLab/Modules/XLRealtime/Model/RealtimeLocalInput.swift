import Foundation

enum RealtimeLocalInput: Sendable {
    case image(URL)
    case video(URL)
}
