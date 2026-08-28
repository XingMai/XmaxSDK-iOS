import XCTest
@testable import XmaxSDK

final class MediaPlaybackTimelineTests: XCTestCase {
    func testAudioAndVideoOffsetsUseSameTimelineTimestamp() {
        let timeline = MediaPlaybackTimeline(mediaDurationSeconds: 2)

        let videoTarget = timeline.target(
            loopIndex: 1,
            mediaOffsetSeconds: 0.25
        )
        let audioTarget = timeline.target(
            loopIndex: 1,
            sampleOffset: AudioFrame.sampleRate / 4
        )

        XCTAssertEqual(videoTarget, audioTarget)
        XCTAssertEqual(
            Int64(videoTarget / 1_000),
            Int64(audioTarget / 1_000)
        )
    }

    func testTimelineTimestampAdvancesAcrossPlaybackLoops() {
        let timeline = MediaPlaybackTimeline(mediaDurationSeconds: 2)

        let firstLoopTimestamp = Int64(
            timeline.target(loopIndex: 0, mediaOffsetSeconds: 0) / 1_000
        )
        let secondLoopTimestamp = Int64(
            timeline.target(loopIndex: 1, mediaOffsetSeconds: 0) / 1_000
        )

        XCTAssertGreaterThan(secondLoopTimestamp, firstLoopTimestamp)
        XCTAssertEqual(
            secondLoopTimestamp - firstLoopTimestamp,
            Int64(timeline.cycleDurationNanoseconds / 1_000)
        )
    }
}
