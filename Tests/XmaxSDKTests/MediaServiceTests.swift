import CoreGraphics
import XCTest
@testable import XmaxSDK

final class MediaServiceTests: XCTestCase {
    func testModelDefaultCameraResolutionIsPreserved() throws {
        for model in RealtimeModel.allCases {
            let format = model.defaultCameraVideoFormat
            let source = CGSize(width: format.width, height: format.height)
            let size = try MediaService(model: model).resolveModelInputSize(source)
            XCTAssertEqual(size, source)
        }
    }

    func testAlignedSizesStayWithinEachModelsPixelBounds() throws {
        let sizes: [CGSize] = [
            CGSize(width: 799, height: 751),
            CGSize(width: 1_130, height: 1_130),
            CGSize(width: 1_445, height: 1_445),
            CGSize(width: 1_024, height: 1_920),
            CGSize(width: 3_840, height: 2_160),
            CGSize(width: 1, height: 100_000),
            CGSize(width: 100_000, height: 1)
        ]
        for model in RealtimeModel.allCases {
            for source in sizes {
                let size = try MediaService(model: model).resolveModelInputSize(source)
                let pixels = Int(size.width * size.height)
                XCTAssertGreaterThanOrEqual(pixels, model.minimumInputPixels)
                XCTAssertLessThanOrEqual(pixels, model.maximumInputPixels)
                XCTAssertTrue(Int(size.width).isMultiple(of: model.inputSizeAlignment))
                XCTAssertTrue(Int(size.height).isMultiple(of: model.inputSizeAlignment))
            }
        }
    }

    func testResolveModelInputSizeUpscalesAndAlignsSmallImage() throws {
        let size = try MediaService().resolveModelInputSize(
            CGSize(width: 640, height: 480)
        )

        XCTAssertEqual(size, CGSize(width: 896, height: 672))
    }

    func testResolveModelInputSizeDownscalesAndAlignsLargeImage() throws {
        let size = try MediaService().resolveModelInputSize(
            CGSize(width: 1_920, height: 1_080)
        )

        XCTAssertEqual(size, CGSize(width: 1_504, height: 832))
    }

    func testResolveModelInputSizeAlignsImageInsidePixelRange() throws {
        let size = try MediaService().resolveModelInputSize(
            CGSize(width: 1_010, height: 770)
        )

        XCTAssertEqual(size, CGSize(width: 1_024, height: 768))
    }

    func testResolveModelInputSizeRejectsInvalidCGSize() {
        XCTAssertThrowsError(
            try MediaService().resolveModelInputSize(
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

    func testFrameInterpolationRejectsInvalidVideoSize() {
        let service = MediaService()

        XCTAssertFalse(service.supportsFrameInterpolation(
            for: CGSize(width: CGFloat.nan, height: 1_280)
        ))
        XCTAssertFalse(service.supportsFrameInterpolation(
            for: CGSize(width: 704.5, height: 1_280)
        ))
        XCTAssertFalse(service.supportsFrameInterpolation(
            for: CGSize(width: 0, height: 1_280)
        ))
    }

    func testFrameInterpolationVideoSizeUsesAlignedLegacyPixelLimit() {
        XCTAssertTrue(MediaService.supportsFrameInterpolationSize(
            CGSize(width: 704, height: 1_280)
        ))
        XCTAssertTrue(MediaService.supportsFrameInterpolationSize(
            CGSize(width: 992, height: 992)
        ))
        XCTAssertTrue(MediaService.supportsFrameInterpolationSize(
            CGSize(width: 1_120, height: 840)
        ))
        XCTAssertFalse(MediaService.supportsFrameInterpolationSize(
            CGSize(width: 1_120, height: 1_120)
        ))
    }

#if targetEnvironment(simulator)
    func testFrameInterpolationIsUnavailableInSimulator() {
        XCTAssertFalse(
            MediaService().supportsFrameInterpolation(
                for: CGSize(width: 704, height: 1_280)
            )
        )
    }
#endif
}
