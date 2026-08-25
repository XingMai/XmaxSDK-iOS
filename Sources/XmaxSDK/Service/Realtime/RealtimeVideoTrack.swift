import Foundation

/// 实时视频轨道及其动态元数据。
final class RealtimeVideoTrack: @unchecked Sendable {

    // 轨道信息
    let id: String

    // 动态元数据
    private let metadataLock = NSLock()
    private var metadata: Metadata

    init(
        id: String,
        videoFormat: RealtimeVideoFormat? = nil,
        position: CameraPosition? = nil
    ) {
        self.id = id
        metadata = Metadata(
            videoFormat: videoFormat,
            position: position
        )
    }

    var videoFormat: RealtimeVideoFormat? {
        metadataLock.withLock { metadata.videoFormat }
    }

    var position: CameraPosition? {
        metadataLock.withLock { metadata.position }
    }

    func updateVideoFormat(_ videoFormat: RealtimeVideoFormat) {
        metadataLock.withLock {
            metadata.videoFormat = videoFormat
        }
    }

    func updatePosition(_ position: CameraPosition) {
        metadataLock.withLock {
            metadata.position = position
        }
    }
}

private extension RealtimeVideoTrack {
    struct Metadata {
        var videoFormat: RealtimeVideoFormat?
        var position: CameraPosition?
    }
}
