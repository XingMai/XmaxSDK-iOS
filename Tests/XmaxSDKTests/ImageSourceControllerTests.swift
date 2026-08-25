import CoreGraphics
import Foundation
import XCTest
@testable import XmaxSDK

final class ImageSourceControllerTests: XCTestCase {
    func testPrepareResolvesDefaultFormatAndStartEmitsFrame() async throws {
        let fileURL = try makeTemporaryImageDataFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let session = ImageProcessingSessionStub(
            width: 640,
            height: 480
        )
        let recorder = ImageFrameRecorder()
        let controller = ImageSourceController(
            imageProvider: ImageProvidingStub(session: session),
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
        XCTAssertEqual(session.frameSizes, [CGSize(width: 896, height: 672)])
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
            imageProvider: ImageProvidingStub(
                session: ImageProcessingSessionStub(width: 400, height: 800)
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
            imageProvider: ImageProvidingStub(
                session: ImageProcessingSessionStub(width: 1, height: 1)
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

private final class ImageProcessingSessionStub:
    ImageProcessingSession,
    @unchecked Sendable {

    // 图片信息
    let metadata: ImageProcessingMetadata

    // 并发状态
    private let lock = NSLock()
    private var storedFrameSizes: [CGSize] = []

    init(width: Int, height: Int) {
        metadata = ImageProcessingMetadata(
            width: width,
            height: height,
            contentType: "image/png"
        )
    }

    var frameSizes: [CGSize] {
        lock.withLock { storedFrameSizes }
    }

    func resizeAndEncode(
        width: Int,
        height: Int,
        requestedContentType: String,
        quality: Int
    ) throws -> ImageProcessingResult {
        ImageProcessingResult(
            data: Data("image".utf8),
            width: width,
            height: height,
            contentType: requestedContentType
        )
    }

    func encodeJPEG(quality: Int) throws -> ImageProcessingResult {
        ImageProcessingResult(
            data: Data("image".utf8),
            width: metadata.width,
            height: metadata.height,
            contentType: "image/jpeg"
        )
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

private final class ImageProvidingStub: ImageProviding, Sendable {

    // 图片资源
    private let session: any ImageProcessingSession

    init(session: any ImageProcessingSession) {
        self.session = session
    }

    func makeProcessingSession(
        data: Data
    ) throws -> any ImageProcessingSession {
        session
    }

    func resizeImageToFill(
        _ image: CGImage,
        targetWidth: Int,
        targetHeight: Int
    ) throws -> CGImage {
        image
    }
}
