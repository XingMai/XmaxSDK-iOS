//
//  GenerationSizingTests.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/XingMai/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import XCTest
@testable import XmaxSDK

final class GenerationSizingTests: XCTestCase {
    func testGenerationCanvasUsesNearestBucketWithoutValidatingMediaAsBucket() throws {
        let service = MediaService()
        XCTAssertEqual(try service.resolveGenerationSize(CGSize(width: 1080, height: 1920)), CGSize(width: 1024, height: 1920))
        XCTAssertEqual(try service.resolveGenerationSize(CGSize(width: 3840, height: 2160)), CGSize(width: 1920, height: 1024))
        XCTAssertEqual(try service.resolveGenerationSize(CGSize(width: 640, height: 480)), CGSize(width: 1920, height: 1024))
        XCTAssertThrowsError(try service.resolveModelInputSize(CGSize(width: 1080, height: 1920)))
        XCTAssertThrowsError(try service.resolveGenerationSize(.zero))
    }

    func testInterpolationAndNetworkLimitsAreCombinedNotMultiplied() throws {
        let baseline = RealtimeVideoFormat(width: 1024, height: 1920, fps: 30)
        let limit = try MediaService().resolveFrameInterpolationSize(baseline.size)
        XCTAssertEqual(limit, CGSize(width: 688, height: 1290))
        let expected = [limit, limit, CGSize(width: 656, height: 1230), CGSize(width: 512, height: 960), CGSize(width: 512, height: 960)]
        for level in 1...5 {
            let format = QualityVideoFormat.resolveReturnFormat(baseline, level: level, interpolationSize: limit)
            XCTAssertEqual(format.size, expected[level - 1])
            XCTAssertLessThanOrEqual(format.width * format.height, 900000)
            XCTAssertEqual(format.width * baseline.height, format.height * baseline.width)
        }
        let disabled = QualityVideoFormat.resolveReturnFormat(baseline, level: 4, interpolationSize: nil)
        XCTAssertEqual(disabled.size, CGSize(width: 512, height: 960))
        XCTAssertEqual(QualityVideoFormat.resolveReturnFormat(baseline, level: 1, interpolationSize: nil).size, baseline.size)
    }

    func testReturnSizeUsesVideoSourceNotGenerationCanvas() throws {
        let source = RealtimeVideoFormat(width: 1080, height: 1920, fps: 30)
        let service = MediaService()
        let canvas = try service.resolveGenerationSize(source.size)
        XCTAssertEqual(canvas.width, 1024)
        let normal = QualityVideoFormat.resolveReturnFormat(source, level: 2, interpolationSize: nil)
        XCTAssertEqual(normal.size, CGSize(width: 864, height: 1536))
        let interpolated = QualityVideoFormat.resolveReturnFormat(source, level: 2, interpolationSize: try service.resolveFrameInterpolationSize(source.size))
        XCTAssertEqual(interpolated.size, CGSize(width: 702, height: 1248))
        XCTAssertEqual(interpolated.width * 16, interpolated.height * 9)
    }
}
