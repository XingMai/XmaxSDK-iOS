import Foundation

/// 统一协调本地媒体所有权以及 RTC Engine 生命周期。
actor XmaxRealtimeMediaManager {

    // 基础层组件
    private let rtcProvider: any RtcProviding

    // 本地媒体组件
    private let cameraManager: XmaxRealtimeCameraManager

    // 本地媒体资源
    private var activeSourceID: UUID?
    private var mediaOperation: LocalMediaOperation?
    private var stopOperation: LocalMediaStopOperation?

    @MainActor
    init(rtcProvider: any RtcProviding) {
        self.rtcProvider = rtcProvider
        cameraManager = XmaxRealtimeCameraManager(rtcProvider: rtcProvider)
    }

    init(
        rtcProvider: any RtcProviding,
        cameraManager: XmaxRealtimeCameraManager
    ) {
        self.rtcProvider = rtcProvider
        self.cameraManager = cameraManager
    }

    /// 当前活动的本地视频轨道；没有媒体来源时返回空值。
    var currentTrack: RealtimeVideoTrack? {
        guard activeSourceID != nil else {
            return nil
        }
        return cameraManager.currentTrack
    }

    /// 当前本地视频格式；没有活动轨道时返回空值。
    var currentVideoFormat: RealtimeVideoFormat? {
        currentTrack?.videoFormat
    }

    /// 当前相机输入不包含由 SDK 管理的本地音频。
    var hasAudio: Bool {
        false
    }

    /// 创建相机媒体来源并取得本地媒体所有权。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        guard activeSourceID == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local media stream before " +
                    "creating another one"
            )
        }

        let sourceID = UUID()
        activeSourceID = sourceID
        let operation = makeMediaOperation(sourceID: sourceID) {
            try await self.rtcProvider.initialize()
            return try await self.cameraManager.createLocalCameraStream(
                videoFormat: videoFormat,
                position: position
            )
        }
        mediaOperation = operation

        do {
            let stream = try await operation.task.value
            try ensureCreationActive(sourceID: sourceID)
            clearMediaOperation(id: operation.id)
            return stream
        } catch {
            clearMediaOperation(id: operation.id)
            if activeSourceID == sourceID,
               stopOperation?.sourceID != sourceID {
                await rtcProvider.destroy()
                activeSourceID = nil
            }
            throw XmaxError.from(error)
        }
    }

    /// 保留本地视频轨道并替换相机采集参数。
    func replaceLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        guard let sourceID = activeSourceID else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Create a local media stream before replacing it"
            )
        }
        try ensureNoOperationInProgress()

        let operation = makeMediaOperation(sourceID: sourceID) {
            try await self.cameraManager.replaceLocalCameraStream(
                videoFormat: videoFormat,
                position: position
            )
        }
        mediaOperation = operation

        do {
            let stream = try await operation.task.value
            try ensureCreationActive(sourceID: sourceID)
            clearMediaOperation(id: operation.id)
            return stream
        } catch {
            clearMediaOperation(id: operation.id)
            throw XmaxError.from(error)
        }
    }

    /// 停止相机媒体来源并释放 RTC Engine。
    func stopLocalCameraStream() async {
        guard let sourceID = activeSourceID else {
            return
        }
        if let stopOperation, stopOperation.sourceID == sourceID {
            await stopOperation.task.value
            return
        }

        let operationID = UUID()
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.performStop(
                sourceID: sourceID,
                operationID: operationID
            )
        }
        stopOperation = LocalMediaStopOperation(
            id: operationID,
            sourceID: sourceID,
            task: task
        )
        await task.value
    }

    /// 在当前相机来源空闲时切换前置或后置摄像头。
    func switchCamera() async throws -> RealtimeMediaStream {
        guard activeSourceID != nil else {
            throw XmaxError(
                code: .rtcError,
                message: "Local camera preview is not started"
            )
        }
        try ensureNoOperationInProgress()
        return try await cameraManager.switchCamera()
    }

    /// 判断媒体流是否由当前活动来源创建并持有。
    func owns(_ stream: RealtimeMediaStream) -> Bool {
        guard let videoTrack = stream.videoTrack else {
            return false
        }
        return videoTrack === currentTrack
    }
}

private extension XmaxRealtimeMediaManager {
    struct LocalMediaOperation {
        let id: UUID
        let sourceID: UUID
        let task: Task<RealtimeMediaStream, any Error>
    }

    struct LocalMediaStopOperation {
        let id: UUID
        let sourceID: UUID
        let task: Task<Void, Never>
    }

    func makeMediaOperation(
        sourceID: UUID,
        operation: @escaping @Sendable () async throws -> RealtimeMediaStream
    ) -> LocalMediaOperation {
        LocalMediaOperation(
            id: UUID(),
            sourceID: sourceID,
            task: Task(operation: operation)
        )
    }

    func performStop(
        sourceID: UUID,
        operationID: UUID
    ) async {
        if let mediaOperation,
           mediaOperation.sourceID == sourceID {
            do {
                _ = try await mediaOperation.task.value
            } catch {
                if !Self.isCancelled(error) {
                    XmaxLogger.error(
                        "等待本地媒体操作结束失败\n└─ 原因：" +
                            (error as NSError).localizedDescription,
                        category: "Realtime"
                    )
                }
            }
        }

        await cameraManager.stopLocalCameraStream()
        await rtcProvider.destroy()

        if activeSourceID == sourceID {
            activeSourceID = nil
        }
        if stopOperation?.id == operationID {
            stopOperation = nil
        }
    }

    func ensureCreationActive(sourceID: UUID) throws {
        guard activeSourceID == sourceID,
              stopOperation?.sourceID != sourceID else {
            throw XmaxError(
                code: .cancelled,
                message: "Local media stream creation was cancelled"
            )
        }
    }

    func ensureNoOperationInProgress() throws {
        guard mediaOperation == nil, stopOperation == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Another local media operation is already in progress"
            )
        }
    }

    func clearMediaOperation(id: UUID) {
        if mediaOperation?.id == id {
            mediaOperation = nil
        }
    }

    static func isCancelled(_ error: any Error) -> Bool {
        (error as? XmaxError)?.code == .cancelled
    }
}
