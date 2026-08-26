import Foundation

/// 为循环视频和音频提供共享的单调时钟锚点。
struct MediaTimeline: Equatable, Sendable {

    // 时间线参数
    private static let playbackStartDelayUs: Int64 = 100_000
    private static let audioPacketDurationUs: Int64 = 10_000

    // 时间线状态
    let durationUs: Int64
    let cycleDurationUs: Int64
    let mediaStartUs: Int64
    private let initialCycleDurationUs: Int64
    private let playbackAnchorUs: Int64

    init(
        durationUs: Int64,
        mediaStartUs: Int64 = 0,
        currentTimestampUs: Int64 = MediaTimeline.currentTimestampUs()
    ) throws {
        guard durationUs > 0,
              mediaStartUs >= 0,
              mediaStartUs < durationUs,
              currentTimestampUs > 0,
              durationUs <= Int64.max - Self.audioPacketDurationUs else {
            throw XmaxError(
                code: .mediaError,
                message: "Media timeline duration is invalid"
            )
        }

        let cycleDurationUs = Self.roundedCycleDurationUs(durationUs)
        let initialCycleDurationUs = Self.roundedCycleDurationUs(
            durationUs - mediaStartUs
        )
        guard currentTimestampUs <= Int64.max - Self.playbackStartDelayUs else {
            throw XmaxError(
                code: .mediaError,
                message: "Media timeline exceeds the supported duration"
            )
        }

        self.durationUs = durationUs
        self.cycleDurationUs = cycleDurationUs
        self.mediaStartUs = mediaStartUs
        self.initialCycleDurationUs = initialCycleDurationUs
        playbackAnchorUs = currentTimestampUs + Self.playbackStartDelayUs
    }

    /// 返回指定循环的播放起点。
    func playbackAnchorUs(forLoop loopIndex: Int64) throws -> Int64 {
        guard loopIndex >= 0 else {
            throw XmaxError(
                code: .mediaError,
                message: "Media loop index exceeds the supported range"
            )
        }
        guard loopIndex > 0 else {
            return playbackAnchorUs
        }

        let completedFullLoops = loopIndex - 1
        guard playbackAnchorUs <= Int64.max - initialCycleDurationUs,
              completedFullLoops <= (
                Int64.max - playbackAnchorUs - initialCycleDurationUs
              ) / cycleDurationUs else {
            throw XmaxError(
                code: .mediaError,
                message: "Media loop index exceeds the supported range"
            )
        }
        return playbackAnchorUs
            + initialCycleDurationUs
            + completedFullLoops * cycleDurationUs
    }

    /// 返回指定循环在源文件中的读取起点。
    func mediaStartUs(forLoop loopIndex: Int64) -> Int64 {
        loopIndex == 0 ? mediaStartUs : 0
    }

    /// 返回指定循环需要输出的音频包时长。
    func cycleDurationUs(forLoop loopIndex: Int64) -> Int64 {
        loopIndex == 0 ? initialCycleDurationUs : cycleDurationUs
    }

    private static func currentTimestampUs() -> Int64 {
        Int64(
            min(
                DispatchTime.now().uptimeNanoseconds / 1_000,
                UInt64(Int64.max)
            )
        )
    }

    private static func roundedCycleDurationUs(_ durationUs: Int64) -> Int64 {
        let packetCount = (
            durationUs + audioPacketDurationUs - 1
        ) / audioPacketDurationUs
        return packetCount * audioPacketDurationUs
    }
}
