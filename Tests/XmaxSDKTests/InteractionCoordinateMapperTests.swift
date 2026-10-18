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
            CGPoint(x: 0.431231 * 314, y: 0.56931 * 418),
            viewportSize: CGSize(width: 314, height: 418),
            resolvedMediaSize: CGSize(width: 1256, height: 1672),
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
                resolvedMediaSize: CGSize(width: 200, height: 100),
                contentMode: .fill
            ), expected)
        }
    }

    func testEquivalentMediaAspectRatiosProduceSameCoordinates() {
        for resolvedMediaSize in [CGSize(width: 1920, height: 1080), CGSize(width: 1536, height: 864), CGSize(width: 960, height: 540)] {
            XCTAssertEqual(InteractionCoordinateMapper.map(
                CGPoint(x: 120, y: 202.5),
                viewportSize: CGSize(width: 480, height: 270),
                resolvedMediaSize: resolvedMediaSize,
                contentMode: .fit
            ), RealtimePoint(x: 0.25, y: 0.75))
        }
    }

    func testFitUsesResolvedMediaAspectRatio() {
        let viewport = CGSize(width: 400, height: 400)
        let resolvedMediaSize = CGSize(width: 200, height: 100)
        XCTAssertNil(InteractionCoordinateMapper.map(
            CGPoint(x: 100, y: 99), viewportSize: viewport,
            resolvedMediaSize: resolvedMediaSize, contentMode: .fit
        ))
        XCTAssertEqual(InteractionCoordinateMapper.map(
            CGPoint(x: 100, y: 150), viewportSize: viewport,
            resolvedMediaSize: resolvedMediaSize, contentMode: .fit
        ), RealtimePoint(x: 0.25, y: 0.25))
    }

    func testFillUsesResolvedMediaCrop() {
        XCTAssertEqual(InteractionCoordinateMapper.map(
            CGPoint(x: 0, y: 100), viewportSize: CGSize(width: 400, height: 400),
            resolvedMediaSize: CGSize(width: 200, height: 100), contentMode: .fill
        ), RealtimePoint(x: 0.25, y: 0.25))
    }

    func testMappedEdgesAreClampedToUnitBounds() {
        XCTAssertEqual(InteractionCoordinateMapper.map(
            CGPoint(x: 200, y: 100), viewportSize: CGSize(width: 200, height: 100),
            resolvedMediaSize: CGSize(width: 200, height: 100), contentMode: .fill
        ), RealtimePoint(x: 1, y: 1))
    }

    func testInvalidResolvedMediaSizeDoesNotProducePoint() {
        let valid = CGSize(width: 720, height: 1280)
        for invalid in [CGSize.zero, CGSize(width: CGFloat.nan, height: 1280), CGSize(width: 720, height: CGFloat.infinity)] {
            XCTAssertNil(InteractionCoordinateMapper.map(
                CGPoint(x: 100, y: 100), viewportSize: valid,
                resolvedMediaSize: invalid, contentMode: .fit
            ))
        }
    }

    func testFitMapsDisplayedVideoAndRejectsLetterboxArea() throws {
        let viewportSize = CGSize(width: 320, height: 480)
        let resolvedMediaSize = CGSize(width: 720, height: 1280)

        XCTAssertNil(
            InteractionCoordinateMapper.map(
                CGPoint(x: 10, y: 240),
                viewportSize: viewportSize,
                resolvedMediaSize: resolvedMediaSize,
                contentMode: .fit
            )
        )
        XCTAssertEqual(
            InteractionCoordinateMapper.map(
                CGPoint(x: 160, y: 240),
                viewportSize: viewportSize,
                resolvedMediaSize: resolvedMediaSize,
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
                resolvedMediaSize: CGSize(width: 720, height: 1280),
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
                resolvedMediaSize: CGSize(width: 720, height: 1280),
                contentMode: .fill
            )
        )
    }
}
