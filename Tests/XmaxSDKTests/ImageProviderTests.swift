import CoreGraphics
import XCTest
@testable import XmaxSDK

final class ImageProviderTests: XCTestCase {
    func testCenterCropRectCropsWideImageHorizontally() {
        XCTAssertEqual(
            ImageProvider.centerCropRect(
                sourceWidth: 400,
                sourceHeight: 200,
                targetWidth: 100,
                targetHeight: 100
            ),
            CGRect(x: 100, y: 0, width: 200, height: 200)
        )
    }

    func testCenterCropRectCropsTallImageVertically() {
        XCTAssertEqual(
            ImageProvider.centerCropRect(
                sourceWidth: 200,
                sourceHeight: 400,
                targetWidth: 200,
                targetHeight: 100
            ),
            CGRect(x: 0, y: 150, width: 200, height: 100)
        )
    }

    func testResizeImageToFillReturnsRequestedPixelDimensions() throws {
        let source = try makeImage(width: 8, height: 4)

        let output = try ImageProvider().resizeImageToFill(
            source,
            targetWidth: 3,
            targetHeight: 5
        )

        XCTAssertEqual(output.width, 3)
        XCTAssertEqual(output.height, 5)
    }

    func testResizeImageToFillRejectsInvalidDimensions() throws {
        let source = try makeImage(width: 2, height: 2)

        XCTAssertThrowsError(
            try ImageProvider().resizeImageToFill(
                source,
                targetWidth: 0,
                targetHeight: 2
            )
        ) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Image width and height must be finite numbers greater than zero"
                )
            )
        }
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(
            red: 0.25,
            green: 0.5,
            blue: 0.75,
            alpha: 1
        )
        context.fill(CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(height)
        ))
        return try XCTUnwrap(context.makeImage())
    }
}
