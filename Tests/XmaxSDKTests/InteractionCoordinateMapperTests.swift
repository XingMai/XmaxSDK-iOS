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
    func testReturnSizeChangesDoNotChangeMediaCoordinates() {
        let media = CGSize(width: 1920, height: 1080)
        for displayed in [media, CGSize(width: 1536, height: 864), CGSize(width: 960, height: 540)] {
            XCTAssertEqual(InteractionCoordinateMapper.map(
                CGPoint(x: 120, y: 202.5),
                viewportSize: CGSize(width: 480, height: 270),
                displayedVideoSize: displayed,
                mediaSize: media,
                contentMode: .fit
            ), RealtimePoint(x: 480, y: 810))
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
        ), RealtimePoint(x: 250, y: 250))
    }

    func testFillUsesDisplayedCropBeforeMappingToMediaCoordinates() {
        XCTAssertEqual(InteractionCoordinateMapper.map(
            CGPoint(x: 0, y: 100), viewportSize: CGSize(width: 400, height: 400),
            displayedVideoSize: CGSize(width: 200, height: 100),
            mediaSize: CGSize(width: 1000, height: 1000), contentMode: .fill
        ), RealtimePoint(x: 250, y: 250))
    }

    func testMappedEdgesAreClampedToMediaPixelBounds() {
        XCTAssertEqual(InteractionCoordinateMapper.map(
            CGPoint(x: 200, y: 100), viewportSize: CGSize(width: 200, height: 100),
            displayedVideoSize: CGSize(width: 200, height: 100),
            mediaSize: CGSize(width: 1920, height: 1080), contentMode: .fill
        ), RealtimePoint(x: 1919, y: 1079))
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
            RealtimePoint(x: 360, y: 640)
        )
    }

    func testFillIncludesCroppedVideoOffset() throws {
        XCTAssertEqual(
            InteractionCoordinateMapper.map(
                CGPoint(x: 0, y: 0),
                viewportSize: CGSize(width: 320, height: 480),
                displayedVideoSize: CGSize(width: 720, height: 1280),
                mediaSize: CGSize(width: 720, height: 1280),
                contentMode: .fill
            ),
            RealtimePoint(x: 0, y: 100)
        )
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
