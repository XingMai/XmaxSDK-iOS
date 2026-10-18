//
//  InteractionCoordinateMapperTests.swift
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

final class InteractionCoordinateMapperTests: XCTestCase {
    func testNormalizedCoordinatesPreserveFractionalPrecision() throws {
        let point = try XCTUnwrap(InteractionCoordinateMapper.map(
            CGPoint(x: 0.431231 * 300, y: 0.56931 * 400),
            viewportSize: CGSize(width: 300, height: 400),
            displayedVideoSize: CGSize(width: 1248, height: 1664),
            mediaSize: CGSize(width: 1256, height: 1672),
            contentMode: .fit
        ))

        XCTAssertEqual(point.x, 0.431231, accuracy: 0.000000001)
        XCTAssertEqual(point.y, 0.56931, accuracy: 0.000000001)
    }

    func testFillClampsOutOfRangeCoordinates() {
        for (input, expected) in [
            (CGPoint(x: -10, y: -10), RealtimePoint(x: 0, y: 0)),
            (CGPoint(x: 250, y: 150), RealtimePoint(x: 1, y: 1))
        ] {
            XCTAssertEqual(InteractionCoordinateMapper.map(
                input,
                viewportSize: CGSize(width: 200, height: 100),
                displayedVideoSize: CGSize(width: 200, height: 100),
                mediaSize: CGSize(width: 1920, height: 1080),
                contentMode: .fill
            ), expected)
        }
    }

    func testReturnSizeChangesDoNotChangeMediaCoordinates() {
        let media = CGSize(width: 1920, height: 1080)
        for displayed in [media, CGSize(width: 1536, height: 864), CGSize(width: 960, height: 540)] {
            XCTAssertEqual(InteractionCoordinateMapper.map(
                CGPoint(x: 120, y: 202.5),
                viewportSize: CGSize(width: 480, height: 270),
                displayedVideoSize: displayed,
                mediaSize: media,
                contentMode: .fit
            ), RealtimePoint(x: 0.25, y: 0.75))
        }
    }

    func testFitUsesDisplayedAspectRatioBeforeMappingToMediaCoordinates() {
        let viewport = CGSize(width: 400, height: 400)
        let displayed = CGSize(width: 200, height: 100)
        let media = CGSize(width: 1000, height: 1000)
        XCTAssertNil(InteractionCoordinateMapper.map(
            CGPoint(x: 100, y: 99), viewportSize: viewport,
            displayedVideoSize: displayed, mediaSize: media, contentMode: .fit
        ))
        XCTAssertEqual(InteractionCoordinateMapper.map(
            CGPoint(x: 100, y: 150), viewportSize: viewport,
            displayedVideoSize: displayed, mediaSize: media, contentMode: .fit
        ), RealtimePoint(x: 0.25, y: 0.25))
    }

    func testFillUsesDisplayedCropBeforeMappingToMediaCoordinates() {
        XCTAssertEqual(InteractionCoordinateMapper.map(
            CGPoint(x: 0, y: 100), viewportSize: CGSize(width: 400, height: 400),
            displayedVideoSize: CGSize(width: 200, height: 100),
            mediaSize: CGSize(width: 1000, height: 1000), contentMode: .fill
        ), RealtimePoint(x: 0.25, y: 0.25))
    }

    func testMappedEdgesAreClampedToUnitBounds() {
        XCTAssertEqual(InteractionCoordinateMapper.map(
            CGPoint(x: 200, y: 100), viewportSize: CGSize(width: 200, height: 100),
            displayedVideoSize: CGSize(width: 200, height: 100),
            mediaSize: CGSize(width: 1920, height: 1080), contentMode: .fill
        ), RealtimePoint(x: 1, y: 1))
    }

    func testInvalidMediaOrDisplayedSizeDoesNotProducePoint() {
        let valid = CGSize(width: 720, height: 1280)
        for invalid in [CGSize.zero, CGSize(width: CGFloat.nan, height: 1280), CGSize(width: 720, height: CGFloat.infinity)] {
            for (media, displayed) in [(valid, invalid), (invalid, valid)] {
                XCTAssertNil(InteractionCoordinateMapper.map(
                    CGPoint(x: 100, y: 100), viewportSize: valid,
                    displayedVideoSize: displayed, mediaSize: media, contentMode: .fit
                ))
            }
        }
    }

    func testFitMapsDisplayedVideoAndRejectsLetterboxArea() throws {
        let viewportSize = CGSize(width: 320, height: 480)
        let videoSize = CGSize(width: 720, height: 1280)

        XCTAssertNil(
            InteractionCoordinateMapper.map(
                CGPoint(x: 10, y: 240),
                viewportSize: viewportSize,
                displayedVideoSize: videoSize,
                mediaSize: videoSize,
                contentMode: .fit
            )
        )
        XCTAssertEqual(
            InteractionCoordinateMapper.map(
                CGPoint(x: 160, y: 240),
                viewportSize: viewportSize,
                displayedVideoSize: videoSize,
                mediaSize: videoSize,
                contentMode: .fit
            ),
            RealtimePoint(x: 0.5, y: 0.5)
        )
    }

    func testFillIncludesCroppedVideoOffset() throws {
        let point = try XCTUnwrap(
            InteractionCoordinateMapper.map(
                CGPoint(x: 0, y: 0),
                viewportSize: CGSize(width: 320, height: 480),
                displayedVideoSize: CGSize(width: 720, height: 1280),
                mediaSize: CGSize(width: 720, height: 1280),
                contentMode: .fill
            )
        )

        XCTAssertEqual(point.x, 0, accuracy: 0.000000001)
        XCTAssertEqual(point.y, 0.078125, accuracy: 0.000000001)
    }

    func testInvalidGeometryDoesNotProducePoint() {
        XCTAssertNil(
            InteractionCoordinateMapper.map(
                CGPoint(x: 10, y: 10),
                viewportSize: .zero,
                displayedVideoSize: CGSize(width: 720, height: 1280),
                mediaSize: CGSize(width: 720, height: 1280),
                contentMode: .fill
            )
        )
    }
}
