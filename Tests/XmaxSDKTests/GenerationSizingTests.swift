//
//  GenerationSizingTests.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import XCTest
@testable import XmaxSDK

final class GenerationSizingTests: XCTestCase {
    func testCappedMediaSizeBecomesUplinkBaselineWithoutChangingGenerationBucket() throws {
        let service = MediaService()
        let sourceMediaSize = CGSize(width: 3840, height: 2160)
        let resolvedMediaSize = try service.resolveMediaSize(sourceMediaSize, source: .video)
        let baseline = RealtimeVideoFormat(width: Int(resolvedMediaSize.width), height: Int(resolvedMediaSize.height), fps: 30)

        XCTAssertEqual(resolvedMediaSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(QualityVideoFormat.resolve(baseline, level: 2, downlink: false).size, CGSize(width: 1536, height: 864))
        XCTAssertEqual(QualityVideoFormat.resolve(baseline, level: 5, downlink: false).size, CGSize(width: 960, height: 540))
        XCTAssertEqual(try service.resolveGenerationSize(resolvedMediaSize), CGSize(width: 1920, height: 1024))
    }

    func testGenerationCanvasUsesNearestBucketWithoutValidatingMediaAsBucket() throws {
        let service = MediaService()
        XCTAssertEqual(try service.resolveGenerationSize(CGSize(width: 1080, height: 1920)), CGSize(width: 1024, height: 1920))
        XCTAssertEqual(try service.resolveGenerationSize(CGSize(width: 3840, height: 2160)), CGSize(width: 1920, height: 1024))
        XCTAssertEqual(try service.resolveGenerationSize(CGSize(width: 640, height: 480)), CGSize(width: 1920, height: 1024))
        XCTAssertThrowsError(try service.resolveMediaSize(CGSize(width: 1080, height: 1920), source: .camera))
        XCTAssertThrowsError(try service.resolveGenerationSize(.zero))
    }

    func testInterpolationAndNetworkLimitsAreCombinedNotMultiplied() throws {
        let baseline = RealtimeVideoFormat(width: 1024, height: 1920, fps: 30)
        let limit = try targetFormat(baseline, level: 1, interpolation: true).size
        XCTAssertEqual(limit, CGSize(width: 672, height: 1260))
        let expected = [limit, limit, CGSize(width: 640, height: 1200), CGSize(width: 512, height: 960), CGSize(width: 512, height: 960)]
        for level in 1...5 {
            let format = try targetFormat(baseline, level: level, interpolation: true)
            XCTAssertEqual(format.size, expected[level - 1])
            XCTAssertLessThanOrEqual(format.width * format.height, 900000)
            XCTAssertEqual(format.width * baseline.height, format.height * baseline.width)
        }
        let disabled = try targetFormat(baseline, level: 4, interpolation: false)
        XCTAssertEqual(disabled.size, CGSize(width: 512, height: 960))
        XCTAssertEqual(try targetFormat(baseline, level: 1, interpolation: false).size, baseline.size)
    }

    func testReturnSizeUsesVideoSourceNotGenerationCanvas() throws {
        let source = RealtimeVideoFormat(width: 1080, height: 1920, fps: 30)
        let service = MediaService()
        let canvas = try service.resolveGenerationSize(source.size)
        XCTAssertEqual(canvas.width, 1024)
        let normal = try targetFormat(source, level: 2, interpolation: false)
        XCTAssertEqual(normal.size, CGSize(width: 864, height: 1536))
        let interpolated = try targetFormat(source, level: 2, interpolation: true)
        XCTAssertEqual(interpolated.size, CGSize(width: 684, height: 1216))
        XCTAssertEqual(interpolated.width * 16, interpolated.height * 9)
    }

    func testReturnSizeFallsBackToFourAlignmentWithoutChangingUplink() throws {
        let source = RealtimeVideoFormat(width: 802, height: 600, fps: 30)
        let target = try targetFormat(source, level: 1, interpolation: false)
        XCTAssertEqual(target.size, CGSize(width: 800, height: 600))
        XCTAssertEqual(QualityVideoFormat.resolve(source, level: 1, downlink: false).size, source.size)
    }

    func testReturnSizeRemainsAlignedAndWithinLimitsAcrossTiersAndOrientations() throws {
        let sizes = [(720, 1280), (832, 1472), (1024, 1920), (1922, 1080), (802, 600), (160, 120)]
        for (width, height) in sizes {
            for (w, h) in [(width, height), (height, width)] {
                let source = RealtimeVideoFormat(width: w, height: h, fps: 30)
                for level in 1...5 {
                    let network = QualityVideoFormat.resolveDownlinkMaximumSize(source, level: level)
                    for interpolation in [false, true] {
                        let target = try targetFormat(source, level: level, interpolation: interpolation)
                        XCTAssertTrue(target.width.isMultiple(of: 4))
                        XCTAssertTrue(target.height.isMultiple(of: 4))
                        XCTAssertGreaterThanOrEqual(target.width, 4)
                        XCTAssertGreaterThanOrEqual(target.height, 4)
                        XCTAssertLessThanOrEqual(Double(target.width), network.width)
                        XCTAssertLessThanOrEqual(Double(target.height), network.height)
                        XCTAssertLessThanOrEqual(target.width, source.width)
                        XCTAssertLessThanOrEqual(target.height, source.height)
                        let ratioError = abs(Double(target.width) * Double(h) / (Double(target.height) * Double(w)) - 1)
                        XCTAssertLessThan(ratioError, 0.01)
                        if interpolation {
                            XCTAssertLessThanOrEqual(target.width * target.height, 900000)
                        }
                    }
                }
            }
        }
    }

    func testReturnSizeRejectsDimensionsThatCannotFitFourPixels() {
        for size in [(2, 600), (600, 2)] {
            let source = RealtimeVideoFormat(width: size.0, height: size.1, fps: 30)
            XCTAssertThrowsError(try targetFormat(source, level: 1, interpolation: false)) { error in
                XCTAssertEqual((error as? XmaxError)?.code, .invalidConfiguration)
            }
        }
    }
    func testLowerTierWithinBudgetDoesNotShrinkForInterpolation() throws {
        let source = RealtimeVideoFormat(width: 1922, height: 1080, fps: 30)
        for level in [3, 4, 5] {
            let plain = try targetFormat(source, level: level, interpolation: false)
            let interpolated = try targetFormat(source, level: level, interpolation: true)
            XCTAssertEqual(plain.size, interpolated.size)
        }
    }

    func testDownlinkBoundsRemainUnalignedUntilTargetSizeResolution() throws {
        let source = RealtimeVideoFormat(width: 1024, height: 1920, fps: 30)
        let bounds = QualityVideoFormat.resolveDownlinkMaximumSize(source, level: 2)
        XCTAssertEqual(bounds.width, 819.2, accuracy: 0.0001)
        XCTAssertEqual(bounds.height, 1536, accuracy: 0.0001)
        XCTAssertEqual(try targetFormat(source, level: 2, interpolation: false).size, CGSize(width: 800, height: 1500))
    }

    private func targetFormat(_ baseline: RealtimeVideoFormat, level: Int, interpolation: Bool) throws -> RealtimeVideoFormat {
        let maximumSize = QualityVideoFormat.resolveDownlinkMaximumSize(baseline, level: level)
        let target = try MediaService().resolveTargetSize(
            baseline.size,
            maximumSize: maximumSize,
            frameInterpolationEnabled: interpolation
        )
        return QualityVideoFormat.resolve(baseline, level: level, downlink: true)
            .resized(width: Int(target.width), height: Int(target.height))
    }

}
