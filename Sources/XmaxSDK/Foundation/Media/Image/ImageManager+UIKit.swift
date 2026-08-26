#if canImport(UIKit)
import UIKit

extension ImageManager {
    /// 将 UIKit 图片直接规范为已解码图片，不经过 PNG/JPEG 中转。
    func decode(_ image: UIImage) throws -> any DecodedImage {
        if image.imageOrientation == .up,
           let cgImage = image.cgImage {
            return CoreGraphicsDecodedImage(image: cgImage)
        }

        let pixelSize = CGSize(
            width: (image.size.width * image.scale).rounded(),
            height: (image.size.height * image.scale).rounded()
        )
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "UIKit image width and height must be greater than zero"
            )
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let normalizedImage = UIGraphicsImageRenderer(
            size: pixelSize,
            format: format
        ).image { _ in
            image.draw(
                in: CGRect(origin: .zero, size: pixelSize)
            )
        }
        guard let cgImage = normalizedImage.cgImage else {
            throw XmaxError(
                code: .mediaError,
                message: "Failed to decode the UIKit image"
            )
        }
        return CoreGraphicsDecodedImage(image: cgImage)
    }
}
#endif
