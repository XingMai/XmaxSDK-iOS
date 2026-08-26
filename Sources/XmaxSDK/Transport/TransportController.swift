import Foundation

/// 统一协调 RTC 房间、媒体流、编码和质量事件。
final class TransportController: TransportControlling, @unchecked Sendable {

    // 传输层组件
    private let roomController: any RoomControlling
    private let streamController: any StreamControlling
    private let encodingController: any EncodingControlling
    private let qualityController: any QualityControlling

    convenience init(
        rtcManager: any RtcManaging,
        remoteStreamListener: @escaping RemoteStreamListener = { _ in },
        generationTiming: StreamGenerationTiming = .live
    ) {
        self.init(
            roomController: RoomController(rtcManager: rtcManager),
            streamController: StreamController(
                rtcManager: rtcManager,
                remoteStreamListener: remoteStreamListener,
                generationTiming: generationTiming
            ),
            encodingController: EncodingController(rtcManager: rtcManager),
            qualityController: QualityController(rtcManager: rtcManager)
        )
    }

    init(
        roomController: any RoomControlling,
        streamController: any StreamControlling,
        encodingController: any EncodingControlling,
        qualityController: any QualityControlling
    ) {
        self.roomController = roomController
        self.streamController = streamController
        self.encodingController = encodingController
        self.qualityController = qualityController
    }

    func setVideoEncoderConfig(
        _ videoFormat: RealtimeVideoFormat
    ) throws {
        try encodingController.configure(videoFormat)
    }

    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    ) {
        qualityController.setNetworkQualityListener(listener)
    }

    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    ) {
        qualityController.setPerformanceAlarmListener(listener)
    }

    func connect(
        connection: RealtimeSessionConnection,
        includeLocalAudio: Bool,
        ensureActive: @escaping @Sendable () throws -> Void
    ) async throws {
        try await roomController.join(
            connection: connection,
            ensureActive: ensureActive
        )
        try ensureActive()
        try streamController.configureRoom(
            roomID: connection.roomID,
            botName: connection.botName
        )
        try streamController.publishLocalStream(
            includeAudio: includeLocalAudio
        )
    }

    func disconnect() async {
        await streamController.resetRoom()
        await roomController.leave()
    }

    func setLocalAudioEnabled(_ enabled: Bool) throws {
        try streamController.setLocalAudioEnabled(enabled)
    }

    func pushLocalVideoFrame(_ frame: VideoFrame) throws {
        try streamController.pushLocalVideoFrame(frame)
    }

    func pushLocalAudioFrame(_ frame: AudioFrame) throws {
        try streamController.pushLocalAudioFrame(frame)
    }

    func beginGeneration(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) async throws -> Task<Void, any Error> {
        let confirmation = try streamController.beginGeneration(
            taskID: taskID
        )
        do {
            try await roomController.startGeneration(
                taskID: taskID,
                videoFormat: videoFormat,
                context: context
            )
            return confirmation
        } catch {
            confirmation.cancel()
            await stopGeneration(taskID: taskID)
            throw XmaxError.from(error)
        }
    }

    func updateGeneration(
        taskID: String,
        conditionVersion: Int,
        videoFormat: RealtimeVideoFormat,
        context: RealtimeContext
    ) async throws {
        try await roomController.changeGenerationCondition(
            taskID: taskID,
            conditionVersion: conditionVersion,
            videoFormat: videoFormat,
            context: context
        )
    }

    func stopGeneration(taskID: String) async {
        let stoppedTaskID = await streamController.stopGeneration(
            taskID: taskID
        )
        await roomController.stopGeneration(taskID: stoppedTaskID)
    }

    func sendTracks(
        taskID: String,
        points: [RealtimePoint]
    ) async throws {
        try await roomController.sendTracks(
            taskID: taskID,
            points: points
        )
    }
}
