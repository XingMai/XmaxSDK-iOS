import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit
import XCTest
@testable import XmaxSDK

final class ImageManagerTests: XCTestCase {
    func testCenterCropRectCropsWideImageHorizontally() {
        XCTAssertEqual(
            CoreGraphicsDecodedImage.centerCropRect(
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
            CoreGraphicsDecodedImage.centerCropRect(
                sourceWidth: 200,
                sourceHeight: 400,
                targetWidth: 200,
                targetHeight: 100
            ),
            CGRect(x: 0, y: 150, width: 200, height: 100)
        )
    }

    func testDecodeReadsImageSizeAndCreatesBGRAFrameData() throws {
        let sourceData = try encode(
            makeImage(width: 4, height: 2),
            type: .png
        )

        let decodedImage = try ImageManager().decode(sourceData)
        let frameData = try decodedImage.makeVideoFrameData(
            width: 2,
            height: 2
        )

        XCTAssertEqual(decodedImage.size, CGSize(width: 4, height: 2))
        XCTAssertEqual(frameData.width, 2)
        XCTAssertEqual(frameData.height, 2)
        XCTAssertEqual(frameData.bytesPerRow, 8)
        XCTAssertEqual(frameData.pixelFormat, .bgra)
        XCTAssertEqual(frameData.data.count, 16)
    }

    func testVideoFramePreservesTopToBottomImageOrientation() throws {
        let decodedImage = CoreGraphicsDecodedImage(
            image: try makeTwoRowImage()
        )

        let frameData = try decodedImage.makeVideoFrameData(
            width: 2,
            height: 2
        )

        XCTAssertEqual(
            Data(frameData.data.prefix(4)),
            Data([0, 0, 255, 255])
        )
        XCTAssertEqual(
            Data(frameData.data.suffix(4)),
            Data([255, 0, 0, 255])
        )
    }

    @MainActor
    func testDecodeAcceptsUIKitImageDirectly() throws {
        let image = UIImage(cgImage: try makeImage(width: 4, height: 2))

        let decodedImage = try ImageManager().decode(image)

        XCTAssertEqual(decodedImage.size, CGSize(width: 4, height: 2))
    }

    func testDecodeRejectsEmptyData() {
        XCTAssertThrowsError(try ImageManager().decode(Data())) { error in
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .mediaError,
                    message: "Failed to create image source from data"
                )
            )
        }
    }

    func testVideoFrameRejectsInvalidDimensions() throws {
        let decodedImage = CoreGraphicsDecodedImage(
            image: try makeImage(width: 2, height: 2)
        )

        XCTAssertThrowsError(
            try decodedImage.makeVideoFrameData(width: 0, height: 2)
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
}

private extension ImageManagerTests {
    func makeImage(width: Int, height: Int) throws -> CGImage {
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
        context.fill(
            CGRect(x: 0, y: 0, width: width, height: height)
        )
        return try XCTUnwrap(context.makeImage())
    }

    func makeTwoRowImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(
            red: 0,
            green: 0,
            blue: 1,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        context.setFillColor(
            red: 1,
            green: 0,
            blue: 0,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 1, width: 2, height: 1))
        return try XCTUnwrap(context.makeImage())
    }

    func encode(
        _ image: CGImage,
        type: UTType
    ) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
