import XCTest
@testable import XmaxSDK

final class MediaTimelineTests: XCTestCase {
    func testRoundsLoopDurationToTenMillisecondAudioPacket() throws {
        let timeline = try MediaTimeline(
            durationUs: 1_005_001,
            currentTimestampUs: 2_000_000
        )

        XCTAssertEqual(timeline.durationUs, 1_005_001)
        XCTAssertEqual(timeline.cycleDurationUs, 1_010_000)
        XCTAssertEqual(
            try timeline.playbackAnchorUs(forLoop: 0),
            2_100_000
        )
        XCTAssertEqual(
            try timeline.playbackAnchorUs(forLoop: 2),
            4_120_000
        )
    }

    func testRejectsInvalidDurationAndLoopIndex() throws {
        XCTAssertThrowsError(
            try MediaTimeline(durationUs: 0, currentTimestampUs: 1)
        )

        let timeline = try MediaTimeline(
            durationUs: 1_000_000,
            currentTimestampUs: 1_000_000
        )
        XCTAssertThrowsError(
            try timeline.playbackAnchorUs(forLoop: -1)
        )
        XCTAssertThrowsError(
            try MediaTimeline(
                durationUs: 1_000_000,
                mediaStartUs: 1_000_000,
                currentTimestampUs: 1
            )
        )
    }

    func testFirstLoopStartsAtCheckpointAndFollowingLoopsStartAtBeginning()
        throws {
        let timeline = try MediaTimeline(
            durationUs: 2_005_001,
            mediaStartUs: 1_000_000,
            currentTimestampUs: 5_000_000
        )

        XCTAssertEqual(timeline.mediaStartUs, 1_000_000)
        XCTAssertEqual(timeline.cycleDurationUs, 2_010_000)
        XCTAssertEqual(timeline.mediaStartUs(forLoop: 0), 1_000_000)
        XCTAssertEqual(timeline.mediaStartUs(forLoop: 1), 0)
        XCTAssertEqual(timeline.cycleDurationUs(forLoop: 0), 1_010_000)
        XCTAssertEqual(timeline.cycleDurationUs(forLoop: 1), 2_010_000)
        XCTAssertEqual(try timeline.playbackAnchorUs(forLoop: 0), 5_100_000)
        XCTAssertEqual(try timeline.playbackAnchorUs(forLoop: 1), 6_110_000)
        XCTAssertEqual(try timeline.playbackAnchorUs(forLoop: 2), 8_120_000)
    }
}
