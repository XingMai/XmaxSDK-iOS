//
//  ImageManager+UIKit.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

#if canImport(UIKit)
import UIKit

extension ImageManager {
    /// 直接生成已应用显示方向的解码图像，不进行文件格式编码。
    ///
    /// - Parameter image: 需要解码和规范方向的 UIKit 图片。
    /// - Returns: 可直接生成视频帧的解码图像。
    /// - Throws: 图片尺寸无效或无法生成像素图像时抛出错误。
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
