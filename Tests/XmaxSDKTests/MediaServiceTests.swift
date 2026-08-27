import CoreGraphics
import XCTest
@testable import XmaxSDK

final class MediaServiceTests: XCTestCase {
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
