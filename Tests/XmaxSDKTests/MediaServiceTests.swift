import CoreGraphics
import Foundation
import UIKit
import XCTest
@testable import XmaxSDK

final class MediaServiceTests: XCTestCase {
    func testResolveModelInputSizeUpscalesAndAlignsSmallImage() throws {
        let service = makeService(
            session: MediaImageProcessingSessionStub(
                width: 640,
                height: 480
            )
        )

        let size = try service.resolveModelInputSize(
            CGSize(width: 640, height: 480)
        )

        XCTAssertEqual(size, CGSize(width: 896, height: 672))
    }

    func testResolveModelInputSizeDownscalesAndAlignsLargeImage() throws {
        let service = makeService(
            session: MediaImageProcessingSessionStub(
                width: 1_920,
                height: 1_080
            )
        )

        let size = try service.resolveModelInputSize(
            CGSize(width: 1_920, height: 1_080)
        )

        XCTAssertEqual(size, CGSize(width: 1_504, height: 832))
    }

    func testResolveModelInputSizeAlignsImageInsidePixelRange() throws {
        let service = makeService(
            session: MediaImageProcessingSessionStub(
                width: 1_010,
                height: 770
            )
        )

        let size = try service.resolveModelInputSize(
            CGSize(width: 1_010, height: 770)
        )

        XCTAssertEqual(size, CGSize(width: 1_024, height: 768))
    }

    func testResolveModelInputSizeRejectsInvalidCGSize() {
        XCTAssertThrowsError(
            try makeService(
                session: MediaImageProcessingSessionStub(width: 1, height: 1)
            ).resolveModelInputSize(
                CGSize(width: CGFloat.nan, height: 480)
            )
        ) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Image width and height must be finite numbers " +
                        "greater than zero"
                )
            )
        }
    }

    func testResizeToModelInputUsesResolvedSizeAndSourceContentType() async throws {
        let session = MediaImageProcessingSessionStub(
            width: 640,
            height: 480,
            contentType: " image/png "
        )
        let service = makeService(session: session)

        let result = try await service.resizeToModelInput(
            Data("image".utf8)
        )

        XCTAssertEqual(
            session.resizeRequests,
            [
                MediaResizeRequest(
                    width: 896,
                    height: 672,
                    contentType: "image/png",
                    quality: 90
                )
            ]
        )
        XCTAssertEqual(result.size, CGSize(width: 896, height: 672))
        XCTAssertEqual(result.contentType, "image/png")
    }

    func testResizeToFitPreservesAspectRatioWithoutUpscaling() async throws {
        let largeSession = MediaImageProcessingSessionStub(
            width: 1_600,
            height: 1_200
        )
        let largeService = makeService(session: largeSession)

        let largeResult = try await largeService.resizeToFit(
            Data("large".utf8),
            maximumSize: CGSize(width: 800, height: 800)
        )

        XCTAssertEqual(
            largeResult.size,
            CGSize(width: 800, height: 600)
        )

        let smallSession = MediaImageProcessingSessionStub(
            width: 400,
            height: 300
        )
        let smallService = makeService(session: smallSession)

        let smallResult = try await smallService.resizeToFit(
            Data("small".utf8),
            maximumSize: CGSize(width: 800, height: 800)
        )

        XCTAssertEqual(
            smallResult.size,
            CGSize(width: 400, height: 300)
        )
    }

    func testCompressJPEGRoundsQualityAndPreservesDimensions() async throws {
        let session = MediaImageProcessingSessionStub(
            width: 640,
            height: 480,
            contentType: "image/png"
        )
        let service = makeService(session: session)

        let result = try await service.compressJPEG(
            Data("image".utf8),
            quality: 89.6
        )

        XCTAssertEqual(session.jpegQualities, [90])
        XCTAssertEqual(result.size, CGSize(width: 640, height: 480))
        XCTAssertEqual(result.contentType, "image/jpeg")
    }

    func testCompressJPEGRejectsInvalidQualityBeforeCreatingSession() async {
        let imageProvider = MediaImageProviderStub(
            session: MediaImageProcessingSessionStub(width: 1, height: 1)
        )
        let service = MediaService(
            imageProvider: imageProvider,
            imagePicker: MediaImagePickerStub(data: Data())
        )

        do {
            _ = try await service.compressJPEG(
                Data("image".utf8),
                quality: .infinity
            )
            XCTFail("Expected invalid JPEG quality to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "JPEG quality must be between 0 and 100"
                )
            )
            XCTAssertEqual(imageProvider.sessionCreationCount, 0)
        }
    }

    func testResizeRejectsEmptyDataBeforeCreatingSession() async {
        let imageProvider = MediaImageProviderStub(
            session: MediaImageProcessingSessionStub(width: 1, height: 1)
        )
        let service = MediaService(
            imageProvider: imageProvider,
            imagePicker: MediaImagePickerStub(data: Data())
        )

        do {
            _ = try await service.resizeToModelInput(Data())
            XCTFail("Expected empty image data to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Image source data must not be empty"
                )
            )
            XCTAssertEqual(imageProvider.sessionCreationCount, 0)
        }
    }

    @MainActor
    func testPickImageDelegatesPresenterToPicker() async throws {
        let presenter = UIViewController()
        let expectedData = Data("selected".utf8)
        let service = MediaService(
            imageProvider: MediaImageProviderStub(
                session: MediaImageProcessingSessionStub(width: 1, height: 1)
            ),
            imagePicker: MediaImagePickerStub(data: expectedData)
        )

        let data = try await service.pickImage(from: presenter)

        XCTAssertEqual(data, expectedData)
    }
}

private extension MediaServiceTests {
    func makeService(
        session: MediaImageProcessingSessionStub
    ) -> MediaService {
        MediaService(
            imageProvider: MediaImageProviderStub(session: session),
            imagePicker: MediaImagePickerStub(data: Data())
        )
    }
}

private struct MediaResizeRequest: Equatable, Sendable {
    let width: Int
    let height: Int
    let contentType: String
    let quality: Int
}

private final class MediaImageProcessingSessionStub:
    ImageProcessingSession,
    @unchecked Sendable {

    // 图片信息
    let metadata: ImageProcessingMetadata

    // 并发状态
    private let lock = NSLock()
    private var storedResizeRequests: [MediaResizeRequest] = []
    private var storedJPEGQualities: [Int] = []

    init(
        width: Int,
        height: Int,
        contentType: String = "image/png"
    ) {
        metadata = ImageProcessingMetadata(
            width: width,
            height: height,
            contentType: contentType
        )
    }

    var resizeRequests: [MediaResizeRequest] {
        lock.withLock { storedResizeRequests }
    }

    var jpegQualities: [Int] {
        lock.withLock { storedJPEGQualities }
    }

    func resizeAndEncode(
        width: Int,
        height: Int,
        requestedContentType: String,
        quality: Int
    ) throws -> ImageProcessingResult {
        lock.withLock {
            storedResizeRequests.append(
                MediaResizeRequest(
                    width: width,
                    height: height,
                    contentType: requestedContentType,
                    quality: quality
                )
            )
        }
        return ImageProcessingResult(
            data: Data("resized".utf8),
            width: width,
            height: height,
            contentType: requestedContentType
        )
    }

    func encodeJPEG(quality: Int) throws -> ImageProcessingResult {
        lock.withLock {
            storedJPEGQualities.append(quality)
        }
        return ImageProcessingResult(
            data: Data("jpeg".utf8),
            width: metadata.width,
            height: metadata.height,
            contentType: "image/jpeg"
        )
    }

    func makeVideoFrameData(
        width: Int,
        height: Int
    ) throws -> ImageVideoFrameData {
        ImageVideoFrameData(
            data: Data(repeating: 0, count: width * height * 4),
            width: width,
            height: height,
            bytesPerRow: width * 4,
            pixelFormat: .bgra
        )
    }
}

private final class MediaImageProviderStub:
    ImageProviding,
    @unchecked Sendable {

    // 测试资源
    private let session: MediaImageProcessingSessionStub

    // 并发状态
    private let lock = NSLock()
    private var storedSessionCreationCount = 0

    init(session: MediaImageProcessingSessionStub) {
        self.session = session
    }

    var sessionCreationCount: Int {
        lock.withLock { storedSessionCreationCount }
    }

    func makeProcessingSession(
        data: Data
    ) throws -> any ImageProcessingSession {
        lock.withLock {
            storedSessionCreationCount += 1
        }
        return session
    }

    func resizeImageToFill(
        _ image: CGImage,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> CGImage {
        image
    }
}

private struct MediaImagePickerStub: ImagePicking {
    let data: Data

    @MainActor
    func pickImage(
        from presentingViewController: UIViewController
    ) async throws -> Data {
        data
    }
}
