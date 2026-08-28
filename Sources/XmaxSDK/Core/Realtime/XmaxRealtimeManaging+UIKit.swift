#if canImport(UIKit)
import UIKit

public extension XmaxRealtimeManaging {

    /// 根据 UIKit 图片原始尺寸创建本地图片流并开始预览。
    ///
    /// - Parameter image: 用作本地输入的 UIKit 图片。
    func createLocalImageStream(
        image: UIImage
    ) async throws -> RealtimeMediaStream {
        try await createLocalImageStream(
            image: image,
            videoFormat: nil
        )
    }
}


extension XmaxRealtimeManager {
    /// 从 UIKit 图片创建持续输出帧的媒体流。
    ///
    /// - Parameters:
    ///   - image: 用作本地输入的 UIKit 图片。
    ///   - videoFormat: 输出视频规格；传入 `nil` 时根据图片原始尺寸生成。
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
}
#endif
