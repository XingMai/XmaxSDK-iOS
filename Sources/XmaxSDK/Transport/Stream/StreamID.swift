/// SDK 内部使用的本地与远端媒体流标识。
enum StreamID: String, Sendable {
    case local = "stream-local"
    case remote = "stream-remote"
}
