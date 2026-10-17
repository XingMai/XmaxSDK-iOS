//
//  MediaServiceTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics
import XCTest
@testable import XmaxSDK

final class MediaServiceTests: XCTestCase {
    func testBucketResolutionsArePreservedInBothOrientations() throws {
        let service = MediaService(model: .x2_1_1_preview_us)
        for size in [CGSize(width: 1024, height: 1920), CGSize(width: 1920, height: 1024)] {
            XCTAssertEqual(try service.resolveModelInputSize(size), size)
        }
    }

    func testBucketRejectsOtherSizesWithoutResizingOrRounding() {
        let service = MediaService(model: .x2_1_1_preview_us)
        let sizes: [CGSize] = [
            CGSize(width: 832, height: 1472),
            CGSize(width: 1920, height: 1080),
            CGSize(width: 512, height: 960),
            CGSize(width: 2048, height: 3840),
            CGSize(width: 1120, height: 1120),
            CGSize(width: 1024, height: 1919.9),
            CGSize(width: 0, height: 1920),
            CGSize(width: CGFloat.nan, height: 1920),
            CGSize(width: CGFloat.infinity, height: 1920)
        ]
        for size in sizes {
            XCTAssertThrowsError(try service.resolveModelInputSize(size)) { error in
                XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
            }
        }
    }

    func testInterpolationTargetIsIndependentOfInputBuckets() throws {
        let target = try MediaService(model: .x2_1_1_preview_us).resolveFrameInterpolationSize(
            CGSize(width: 1024, height: 1920)
        )
        XCTAssertEqual(target, CGSize(width: 688, height: 1290))
    }

    func testInterpolationSizePreservesExactAspectRatioWithinPixelBudget() throws {
        let cases: [(CGSize, CGSize)] = [
            (CGSize(width: 832, height: 1472), CGSize(width: 702, height: 1242)),
            (CGSize(width: 1024, height: 1920), CGSize(width: 688, height: 1290)),
            (CGSize(width: 1120, height: 1120), CGSize(width: 948, height: 948)),
            (CGSize(width: 704, height: 1280), CGSize(width: 682, height: 1240)),
            (CGSize(width: 1472, height: 832), CGSize(width: 1242, height: 702)),
            (CGSize(width: 640, height: 480), CGSize(width: 640, height: 480)),
            (CGSize(width: 1000, height: 900), CGSize(width: 1000, height: 900))
        ]
        for (source, expected) in cases {
            let target = try MediaService().resolveFrameInterpolationSize(source)
            XCTAssertEqual(target, expected)
            XCTAssertEqual(target.width * source.height, target.height * source.width)
            XCTAssertLessThanOrEqual(target.width * target.height, 900000)
            XCTAssertLessThanOrEqual(target.width, source.width)
            XCTAssertLessThanOrEqual(target.height, source.height)
            XCTAssertTrue(Int(target.width).isMultiple(of: 2))
            XCTAssertTrue(Int(target.height).isMultiple(of: 2))
        }
    }

    func testInterpolationSizeRejectsInvalidDimensions() {
        for width: CGFloat in [.nan, .infinity, 0, -1, 704.5, CGFloat(Int.max)] {
            XCTAssertThrowsError(try MediaService().resolveFrameInterpolationSize(
                CGSize(width: width, height: 1280)
            )) { error in
                XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
            }
        }
    }

    func testInterpolationSizeRejectsUnrepresentableEvenAspectRatio() {
        XCTAssertThrowsError(try MediaService().resolveFrameInterpolationSize(
            CGSize(width: 1001, height: 1000)
        )) { error in
            XCTAssertEqual((error as? XmaxError)?.code, .frameInterpolationUnsupported)
        }
    }

    func testModelDefaultCameraResolutionIsPreserved() throws {
        for model in RealtimeModel.allCases {
            let format = model.defaultCameraVideoFormat
            let source = CGSize(width: format.width, height: format.height)
            let size = try MediaService(model: model).resolveModelInputSize(source)
            XCTAssertEqual(size, source)
        }
    }

    func testBothAgoraModelsRequireExactResolutionBuckets() throws {
        for model in RealtimeModel.allCases {
            let service = MediaService(model: model)
            for size in model.resolutionBuckets {
                XCTAssertEqual(try service.resolveModelInputSize(size), size)
            }
            for size in [CGSize(width: 640, height: 480), CGSize(width: 1920, height: 1080), CGSize(width: CGFloat.nan, height: 480)] {
                XCTAssertThrowsError(try service.resolveModelInputSize(size)) { error in
                    XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
                }
            }
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

    func testFrameInterpolationVideoSizeUses900000PixelLimit() {
        XCTAssertFalse(MediaService.supportsFrameInterpolationSize(
            CGSize(width: 704, height: 1280)
        ))
        XCTAssertTrue(MediaService.supportsFrameInterpolationSize(
            CGSize(width: 702, height: 1242)
        ))
        XCTAssertTrue(MediaService.supportsFrameInterpolationSize(
            CGSize(width: 1000, height: 900)
        ))
        XCTAssertFalse(MediaService.supportsFrameInterpolationSize(
            CGSize(width: 1000, height: 901)
        ))
        XCTAssertFalse(MediaService.supportsFrameInterpolationSize(
            CGSize(width: 992, height: 992)
        ))
        XCTAssertFalse(MediaService.supportsFrameInterpolationSize(
            CGSize(width: 1120, height: 840)
        ))
        XCTAssertFalse(MediaService.supportsFrameInterpolationSize(
            CGSize(width: 1120, height: 1120)
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
