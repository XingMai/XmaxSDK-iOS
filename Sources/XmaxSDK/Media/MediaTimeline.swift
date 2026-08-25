import Foundation

/// 为循环视频和音频提供共享的单调时钟锚点。
struct MediaTimeline: Equatable, Sendable {

    // 时间线参数
    private static let playbackStartDelayUs: Int64 = 100_000
    private static let audioPacketDurationUs: Int64 = 10_000

    // 时间线状态
    let durationUs: Int64
    let cycleDurationUs: Int64
    private let playbackAnchorUs: Int64

    init(
        durationUs: Int64,
        currentTimestampUs: Int64 = MediaTimeline.currentTimestampUs()
    ) throws {
        guard durationUs > 0,
              currentTimestampUs > 0,
              durationUs <= Int64.max - Self.audioPacketDurationUs else {
            throw XmaxError(
                code: .mediaError,
                message: "Media timeline duration is invalid"
            )
        }

        let packetCount = (durationUs + Self.audioPacketDurationUs - 1)
            / Self.audioPacketDurationUs
        guard packetCount <= Int64.max / Self.audioPacketDurationUs,
              currentTimestampUs <= Int64.max - Self.playbackStartDelayUs else {
            throw XmaxError(
                code: .mediaError,
                message: "Media timeline exceeds the supported duration"
            )
        }

        self.durationUs = durationUs
        cycleDurationUs = packetCount * Self.audioPacketDurationUs
        playbackAnchorUs = currentTimestampUs + Self.playbackStartDelayUs
    }

    /// 返回指定循环的播放起点。
    func playbackAnchorUs(forLoop loopIndex: Int64) throws -> Int64 {
        guard loopIndex >= 0,
              loopIndex <= (Int64.max - playbackAnchorUs)
                / cycleDurationUs else {
            throw XmaxError(
                code: .mediaError,
                message: "Media loop index exceeds the supported range"
            )
        }
        return playbackAnchorUs + loopIndex * cycleDurationUs
    }

    private static func currentTimestampUs() -> Int64 {
        Int64(
            min(
                DispatchTime.now().uptimeNanoseconds / 1_000,
                UInt64(Int64.max)
            )
        )
    }
}
