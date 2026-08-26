import CoreGraphics
import Foundation
import XCTest
@testable import XmaxSDK

final class ImageSourceControllerTests: XCTestCase {
    func testPrepareAcceptsEncodedImageDataDirectly() async throws {
        let imageData = Data("encoded-image".utf8)
        let decodedImage = DecodedImageStub(width: 400, height: 800)
        let controller = ImageSourceController(
            imageManager: ImageManagingStub(decodedImage: decodedImage),
            mediaService: MediaServicingStub(
                resolvedSize: CGSize(width: 832, height: 1_472)
            ),
            frameListener: { _ in },
            errorListener: { _ in }
        )

        let format = try await controller.prepare(
            imageData: imageData,
            videoFormat: nil
        )
        controller.stop()

        XCTAssertEqual(
            format,
            RealtimeVideoFormat(width: 832, height: 1_472, fps: 24)
        )
        XCTAssertEqual(
            decodedImage.frameSizes,
            [CGSize(width: 832, height: 1_472)]
        )
    }

    func testPrepareResolvesDefaultFormatAndStartEmitsFrame() async throws {
        let fileURL = try makeTemporaryImageDataFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let decodedImage = DecodedImageStub(
            width: 640,
            height: 480
        )
        let recorder = ImageFrameRecorder()
        let controller = ImageSourceController(
            imageManager: ImageManagingStub(decodedImage: decodedImage),
            mediaService: MediaServicingStub(
                resolvedSize: CGSize(width: 896, height: 672)
            ),
            frameListener: { frame in
                recorder.append(frame)
            },
            errorListener: { _ in }
        )

        let format = try await controller.prepare(
            fileURL: fileURL,
            videoFormat: nil
        )
        try controller.start()
        controller.stop()

        XCTAssertEqual(
            format,
            RealtimeVideoFormat(width: 896, height: 672, fps: 24)
        )
        XCTAssertEqual(
            decodedImage.frameSizes,
            [CGSize(width: 896, height: 672)]
        )
        let frame = try XCTUnwrap(recorder.frames.first)
        XCTAssertEqual(
            frame.format,
            try VideoFormat(width: 896, height: 672, pixelFormat: .bgra)
        )
        XCTAssertEqual(frame.planes.first?.stride, 896 * 4)
        XCTAssertGreaterThan(frame.timestampUs, 0)
    }

    func testPreparePreservesRequestedFrameRateAfterSizeResolution() async throws {
        let fileURL = try makeTemporaryImageDataFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let mediaService = MediaServicingStub(
            resolvedSize: CGSize(width: 832, height: 1_472)
        )
        let controller = ImageSourceController(
            imageManager: ImageManagingStub(
                decodedImage: DecodedImageStub(width: 400, height: 800)
            ),
            mediaService: mediaService,
            frameListener: { _ in },
            errorListener: { _ in }
        )

        let format = try await controller.prepare(
            fileURL: fileURL,
            videoFormat: RealtimeVideoFormat(
                width: 720,
                height: 1_280,
                fps: 30
            )
        )
        controller.stop()

        XCTAssertEqual(
            mediaService.requestedSizes,
            [CGSize(width: 720, height: 1_280)]
        )
        XCTAssertEqual(
            format,
            RealtimeVideoFormat(width: 832, height: 1_472, fps: 30)
        )
    }

    func testStartRejectsSourceThatHasNotBeenPrepared() {
        let controller = ImageSourceController(
            imageManager: ImageManagingStub(
                decodedImage: DecodedImageStub(width: 1, height: 1)
            ),
            mediaService: MediaServicingStub(
                resolvedSize: CGSize(width: 832, height: 1_472)
            ),
            frameListener: { _ in },
            errorListener: { _ in }
        )

        XCTAssertThrowsError(try controller.start()) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Prepare the local image before starting the " +
                        "image source"
                )
            )
        }
    }

    func testPrepareRejectsEmptyImageData() async {
        let controller = ImageSourceController(
            imageManager: ImageManagingStub(
                decodedImage: DecodedImageStub(width: 1, height: 1)
            ),
            mediaService: MediaServicingStub(
                resolvedSize: CGSize(width: 832, height: 1_472)
            ),
            frameListener: { _ in },
            errorListener: { _ in }
        )

        do {
            _ = try await controller.prepare(
                imageData: Data(),
                videoFormat: nil
            )
            XCTFail("Expected empty image data to be rejected")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Image source data must not be empty"
                )
            )
        }
    }
}

private extension ImageSourceControllerTests {
    func makeTemporaryImageDataFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try Data("image".utf8).write(to: url)
        return url
    }
}

private final class ImageFrameRecorder: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var storedFrames: [any VideoFrame] = []

    var frames: [any VideoFrame] {
        lock.withLock { storedFrames }
    }

    func append(_ frame: any VideoFrame) {
        lock.withLock {
            storedFrames.append(frame)
        }
    }
}

private final class DecodedImageStub:
    DecodedImage,
    @unchecked Sendable {

    // 图片信息
    let size: CGSize

    // 并发状态
    private let lock = NSLock()
    private var storedFrameSizes: [CGSize] = []

    init(width: Int, height: Int) {
        size = CGSize(width: width, height: height)
    }

    var frameSizes: [CGSize] {
        lock.withLock { storedFrameSizes }
    }

    func makeVideoFrameData(
        width: Int,
        height: Int
    ) throws -> ImageVideoFrameData {
        lock.withLock {
            storedFrameSizes.append(CGSize(width: width, height: height))
        }
        return ImageVideoFrameData(
            data: Data(repeating: 0, count: width * height * 4),
            width: width,
            height: height,
            bytesPerRow: width * 4,
            pixelFormat: .bgra
        )
    }
}

private final class ImageManagingStub: ImageManaging, Sendable {

    // 图片资源
    private let decodedImage: any DecodedImage

    init(decodedImage: any DecodedImage) {
        self.decodedImage = decodedImage
    }

    func decode(_ data: Data) throws -> any DecodedImage {
        decodedImage
    }
}
