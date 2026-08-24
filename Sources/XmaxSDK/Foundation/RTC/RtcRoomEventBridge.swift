import Foundation
@preconcurrency import VolcEngineRTC

/// 将火山 RTC Room 回调转发给中性的 RTC 基础层。
final class RtcRoomEventBridge: NSObject, ByteRTCRoomDelegate {
    typealias RoomStateHandler = @Sendable (
        ByteRTCRoom,
        String,
        String,
        Int,
        String
    ) -> Void
    typealias RemoteVideoHandler = @Sendable (
        ByteRTCRoom,
        String,
        ByteRTCStreamInfo,
        Bool
    ) -> Void
    typealias NetworkQualityHandler = @Sendable (
        ByteRTCRoom,
        ByteRTCNetworkQualityStats,
        [ByteRTCNetworkQualityStats]
    ) -> Void
    typealias LocalStatsHandler = @Sendable (
        ByteRTCRoom,
        ByteRTCLocalStreamStats
    ) -> Void
    typealias RemoteStatsHandler = @Sendable (
        ByteRTCRoom,
        ByteRTCRemoteStreamStats
    ) -> Void

    private let onRoomState: RoomStateHandler
    private let onRemoteVideo: RemoteVideoHandler
    private let onNetworkQuality: NetworkQualityHandler
    private let onLocalStats: LocalStatsHandler
    private let onRemoteStats: RemoteStatsHandler

    init(
        onRoomState: @escaping RoomStateHandler,
        onRemoteVideo: @escaping RemoteVideoHandler,
        onNetworkQuality: @escaping NetworkQualityHandler,
        onLocalStats: @escaping LocalStatsHandler,
        onRemoteStats: @escaping RemoteStatsHandler
    ) {
        self.onRoomState = onRoomState
        self.onRemoteVideo = onRemoteVideo
        self.onNetworkQuality = onNetworkQuality
        self.onLocalStats = onLocalStats
        self.onRemoteStats = onRemoteStats
    }

    func rtcRoom(
        _ rtcRoom: ByteRTCRoom,
        onRoomStateChanged roomId: String,
        withUid uid: String,
        state: Int,
        extraInfo: String
    ) {
        onRoomState(rtcRoom, roomId, uid, state, extraInfo)
    }

    func rtcRoom(
        _ rtcRoom: ByteRTCRoom,
        onUserPublishStreamVideo streamId: String,
        info: ByteRTCStreamInfo,
        isPublish: Bool
    ) {
        onRemoteVideo(rtcRoom, streamId, info, isPublish)
    }

    func rtcRoom(
        _ rtcRoom: ByteRTCRoom,
        onNetworkQuality localQuality: ByteRTCNetworkQualityStats,
        remoteQualities: [ByteRTCNetworkQualityStats]
    ) {
        onNetworkQuality(rtcRoom, localQuality, remoteQualities)
    }

    @objc(rtcRoom:onLocalStreamStats:info:stats:)
    func rtcRoom(
        _ rtcRoom: ByteRTCRoom,
        onLocalStreamStats streamId: String,
        info: ByteRTCStreamInfo,
        stats: ByteRTCLocalStreamStats
    ) {
        onLocalStats(rtcRoom, stats)
    }

    @objc(rtcRoom:onRemoteStreamStats:info:stats:)
    func rtcRoom(
        _ rtcRoom: ByteRTCRoom,
        onRemoteStreamStats streamId: String,
        info: ByteRTCStreamInfo,
        stats: ByteRTCRemoteStreamStats
    ) {
        onRemoteStats(rtcRoom, stats)
    }
}
