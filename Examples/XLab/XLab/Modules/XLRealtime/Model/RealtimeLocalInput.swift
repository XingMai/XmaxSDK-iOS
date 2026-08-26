import UIKit

enum RealtimeLocalInput: Sendable {
    enum Kind: Sendable {
        case image
        case video
    }

    case image(UIImage)
    case video(URL)

    var kind: Kind {
        switch self {
        case .image:
            .image
        case .video:
            .video
        }
    }
}
