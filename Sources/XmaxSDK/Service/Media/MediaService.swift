import CoreGraphics
import Foundation
import UIKit

/// 提供图片选择、尺寸适配、缩放和压缩能力。
final class MediaService: MediaServicing, Sendable {

    // 模型约束
    private static let minimumModelPixels = 600_000
    private static let maximumModelPixels = 1_280_000
    private static let modelSizeAlignment = 32
    private static let defaultQuality = 90

    // 基础层组件
    private let imageProvider: any ImageProviding
    private let imagePicker: any ImagePicking

    init(
        imageProvider: any ImageProviding,
        imagePicker: any ImagePicking
    ) {
        self.imageProvider = imageProvider
        self.imagePicker = imagePicker
    }

    @MainActor
    convenience init() {
        self.init(
            imageProvider: ImageProvider(),
            imagePicker: ImagePickerProvider()
        )
    }

    @MainActor
    func pickImage(
        from presentingViewController: UIViewController
    ) async throws -> Data {
        do {
            return try await imagePicker.pickImage(
                from: presentingViewController
            )
        } catch {
            throw XmaxError.from(error)
        }
    }

    func resolveModelInputSize(_ size: CGSize) throws -> CGSize {
        let size = try validatedSize(size)
        let pixels = Double(size.width) * Double(size.height)
        let scale: Double
        let rounding: (Double) -> Double

        if pixels < Double(Self.minimumModelPixels) {
            scale = sqrt(Double(Self.minimumModelPixels) / pixels)
            rounding = ceil
        } else if pixels > Double(Self.maximumModelPixels) {
            scale = sqrt(Double(Self.maximumModelPixels) / pixels)
            rounding = floor
        } else {
            scale = 1
            rounding = round
        }

        let alignment = Double(Self.modelSizeAlignment)
        let width = max(
            Int(rounding(Double(size.width) * scale / alignment)) *
                Self.modelSizeAlignment,
            Self.modelSizeAlignment
        )
        let height = max(
            Int(rounding(Double(size.height) * scale / alignment)) *
                Self.modelSizeAlignment,
            Self.modelSizeAlignment
        )
        return CGSize(width: width, height: height)
    }

    func resizeToModelInput(
        _ data: Data
    ) async throws -> ProcessedImage {
        do {
            let session = try makeSession(data)
            let originalSize = CGSize(
                width: session.metadata.width,
                height: session.metadata.height
            )
            let targetSize = try resolveModelInputSize(originalSize)
            return makeProcessedImage(
                try session.resizeAndEncode(
                    width: Int(targetSize.width),
                    height: Int(targetSize.height),
                    requestedContentType: normalizedContentType(
                        session.metadata.contentType
                    ),
                    quality: Self.defaultQuality
                )
            )
        } catch {
            throw XmaxError.from(error)
        }
    }

    func resizeToFit(
        _ data: Data,
        maximumSize: CGSize
    ) async throws -> ProcessedImage {
        do {
            let session = try makeSession(data)
            let originalSize = CGSize(
                width: session.metadata.width,
                height: session.metadata.height
            )
            let targetSize = try fitSize(
                source: originalSize,
                maximum: maximumSize
            )
            return makeProcessedImage(
                try session.resizeAndEncode(
                    width: Int(targetSize.width),
                    height: Int(targetSize.height),
                    requestedContentType: normalizedContentType(
                        session.metadata.contentType
                    ),
                    quality: Self.defaultQuality
                )
            )
        } catch {
            throw XmaxError.from(error)
        }
    }

    func compressJPEG(
        _ data: Data,
        quality: Double
    ) async throws -> ProcessedImage {
        do {
            let normalizedQuality = try validateQuality(quality)
            return makeProcessedImage(
                try makeSession(data).encodeJPEG(quality: normalizedQuality)
            )
        } catch {
            throw XmaxError.from(error)
        }
    }
}

private extension MediaService {
    func makeSession(_ data: Data) throws -> any ImageProcessingSession {
        guard !data.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image source data must not be empty"
            )
        }
        return try imageProvider.makeProcessingSession(data: data)
    }

    func fitSize(
        source: CGSize,
        maximum: CGSize
    ) throws -> CGSize {
        let source = try validatedSize(source)
        let maximum = try validatedSize(maximum)
        let scale = min(
            1,
            Double(maximum.width) / Double(source.width),
            Double(maximum.height) / Double(source.height)
        )
        return CGSize(
            width: max((Double(source.width) * scale).rounded(), 1),
            height: max((Double(source.height) * scale).rounded(), 1)
        )
    }

    func makeProcessedImage(
        _ result: ImageProcessingResult
    ) -> ProcessedImage {
        ProcessedImage(
            data: result.data,
            size: CGSize(
                width: result.width,
                height: result.height
            ),
            contentType: result.contentType
        )
    }

    func normalizedContentType(_ contentType: String) -> String {
        let normalized = contentType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty ? "image/jpeg" : normalized
    }

    func validatedSize(_ size: CGSize) throws -> CGSize {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0,
              size.width < CGFloat(Int.max),
              size.height < CGFloat(Int.max) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image width and height must be finite numbers " +
                    "greater than zero"
            )
        }
        return CGSize(
            width: max(size.width.rounded(), 1),
            height: max(size.height.rounded(), 1)
        )
    }

    func validateQuality(_ quality: Double) throws -> Int {
        guard quality.isFinite, quality >= 0, quality <= 100 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "JPEG quality must be between 0 and 100"
            )
        }
        return Int(quality.rounded())
    }
}
