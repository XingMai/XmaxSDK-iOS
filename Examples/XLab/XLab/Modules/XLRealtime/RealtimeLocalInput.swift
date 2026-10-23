import UIKit

enum RealtimeLocalInput: Sendable {
    enum Kind: Sendable {
        case image
        case video
    }

    case image(UIImage)
    case video(URL)
    case externalVideo(URL)

    var usesExternalSource: Bool {
        if case .externalVideo = self { return true }
        return false
    }

    var kind: Kind {
        switch self {
        case .image:
            .image
        case .video, .externalVideo:
            .video
        }
    }
}
