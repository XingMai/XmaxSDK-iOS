#if canImport(UIKit)
import UIKit

public extension XmaxRealtimeManaging {

    /// 根据 UIKit 图片原始尺寸创建本地图片流并开始预览。
    func createLocalImageStream(
        image: UIImage
    ) async throws -> RealtimeMediaStream {
        try await createLocalImageStream(
            image: image,
            videoFormat: nil
        )
    }

    /// 根据 UIKit 图片原始尺寸替换当前本地媒体流。
    func replaceLocalImageStream(
        image: UIImage
    ) async throws -> RealtimeMediaStream {
        try await replaceLocalImageStream(
            image: image,
            videoFormat: nil
        )
    }
}

extension XmaxRealtimeManager {
    func createLocalImageStream(
        image: UIImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        let decodedImage = try ImageManager().decode(image)
        return try await createLocalImageStream(
            decodedImage: decodedImage,
            videoFormat: videoFormat
        )
    }

    func replaceLocalImageStream(
        image: UIImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        let decodedImage = try ImageManager().decode(image)
        return try await replaceLocalImageStream(
            decodedImage: decodedImage,
            videoFormat: videoFormat
        )
    }
}
#endif
