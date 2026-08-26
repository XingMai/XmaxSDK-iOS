import Foundation

/// 统一协调本地媒体所有权以及 RTC Engine 生命周期。
actor MediaController: MediaControlling {

    // 基础层组件
    private let rtcManager: any RtcManaging

    // 本地媒体组件
    private let cameraController: CameraController
    private let imageController: ImageController?
    private let videoController: VideoController?

    // 本地媒体资源
    private var activeSource: ActiveLocalMediaSource?

    // 并发控制
    private var mediaOperation: LocalMediaOperation?
    private var stopOperation: LocalMediaStopOperation?

    @MainActor
    init(
        rtcManager: any RtcManaging,
        videoFrameListener: @escaping MediaVideoFrameListener,
        audioFrameListener: @escaping MediaAudioFrameListener,
        mediaErrorListener: @escaping MediaSourceErrorListener
    ) {
        self.rtcManager = rtcManager
        cameraController = CameraController(
            rtcManager: rtcManager
        )
        imageController = ImageController(
            rtcManager: rtcManager,
            frameListener: videoFrameListener,
            errorListener: mediaErrorListener
        )
        videoController = VideoController(
            rtcManager: rtcManager,
            videoFrameListener: videoFrameListener,
            audioFrameListener: audioFrameListener,
            errorListener: mediaErrorListener
        )
    }

    init(
        rtcManager: any RtcManaging,
        cameraController: CameraController,
        imageController: ImageController? = nil,
        videoController: VideoController? = nil
    ) {
        self.rtcManager = rtcManager
        self.cameraController = cameraController
        self.imageController = imageController
        self.videoController = videoController
    }

    /// 当前活动的本地视频轨道；没有媒体来源时返回空值。
    var currentTrack: RealtimeVideoTrack? {
        guard let activeSource else {
            return nil
        }
        return currentTrack(for: activeSource.kind)
    }

    /// 当前本地视频格式；没有活动轨道时返回空值。
    var currentVideoFormat: RealtimeVideoFormat? {
        currentTrack?.videoFormat
    }

    /// 当前媒体来源是否包含由 SDK 管理的本地音频。
    var hasAudio: Bool {
        guard activeSource?.kind == .video else {
            return false
        }
        return videoController?.hasAudio ?? false
    }

    /// 设置摄像头预览就绪监听器。
    func setCameraPreviewReadyListener(
        _ listener: RealtimeCameraPreviewReadyListener?
    ) {
        cameraController.setPreviewReadyListener(listener)
    }

    /// 创建相机媒体来源并取得本地媒体所有权。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        try await createSource(kind: .camera) {
            try await self.cameraController.createLocalCameraStream(
                videoFormat: videoFormat,
                position: position
            )
        }
    }

    /// 创建图片数据媒体来源并取得本地媒体所有权。
    func createLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        let imageController = try requiredImageController()
        return try await createSource(kind: .image) {
            try await imageController.createLocalImageStream(
                imageData: imageData,
                videoFormat: videoFormat
            )
        }
    }

    /// 创建已解码图片媒体来源并取得本地媒体所有权。
    func createLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        let imageController = try requiredImageController()
        return try await createSource(kind: .image) {
            try await imageController.createLocalImageStream(
                decodedImage: decodedImage,
                videoFormat: videoFormat
            )
        }
    }

    /// 创建图片媒体来源并取得本地媒体所有权。
    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        let imageController = try requiredImageController()
        return try await createSource(kind: .image) {
            try await imageController.createLocalImageStream(
                fileURL: fileURL,
                videoFormat: videoFormat
            )
        }
    }

    /// 创建文件视频媒体来源并取得本地媒体所有权。
    func createLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        let videoController = try requiredVideoController()
        return try await createSource(kind: .video) {
            try await videoController.createLocalVideoStream(
                fileURL: fileURL,
                videoFormat: videoFormat
            )
        }
    }

    /// 保留本地视频轨道并替换相机采集参数。
    func replaceLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        try await updateCameraSource {
            try await self.cameraController.replaceLocalCameraStream(
                videoFormat: videoFormat,
                position: position
            )
        }
    }

    /// 停止相机媒体来源并释放 RTC Engine。
    func stopLocalCameraStream() async {
        await stopSource(ifKindIs: .camera)
    }

    /// 停止图片媒体来源并释放 RTC Engine。
    func stopLocalImageStream() async {
        await stopSource(ifKindIs: .image)
    }

    /// 停止文件视频媒体来源并释放 RTC Engine。
    func stopLocalVideoStream() async {
        await stopSource(ifKindIs: .video)
    }

    /// 视频来源在新一轮生成开始时从文件起点重新播放。
    func restartForGeneration() async throws {
        guard activeSource?.kind == .video else {
            return
        }
        try await requiredVideoController().restartForGeneration()
    }

    /// 在当前相机来源空闲时切换前置或后置摄像头。
    func switchCamera() async throws -> RealtimeMediaStream {
        guard activeSource?.kind == .camera else {
            throw XmaxError(
                code: .rtcError,
                message: "Local camera preview is not started"
            )
        }
        try ensureNoOperationInProgress()
        return try await cameraController.switchCamera()
    }

    /// 判断媒体流是否由当前活动来源创建并持有。
    func owns(_ stream: RealtimeMediaStream) -> Bool {
        guard let videoTrack = stream.videoTrack else {
            return false
        }
        return videoTrack === currentTrack
    }
}

private extension MediaController {
    enum LocalMediaKind: Sendable {
        case camera
        case image
        case video
    }

    final class ActiveLocalMediaSource {
        let id: UUID
        let kind: LocalMediaKind

        init(id: UUID, kind: LocalMediaKind) {
            self.id = id
            self.kind = kind
        }
    }

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

    func createSource(
        kind: LocalMediaKind,
        operation body: @escaping @Sendable () async throws ->
            RealtimeMediaStream
    ) async throws -> RealtimeMediaStream {
        guard activeSource == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local media stream before " +
                    "creating another one"
            )
        }

        let sourceID = UUID()
        activeSource = ActiveLocalMediaSource(id: sourceID, kind: kind)
        let operation = makeMediaOperation(sourceID: sourceID) {
            try await self.rtcManager.initialize()
            return try await body()
        }
        mediaOperation = operation

        do {
            let stream = try await operation.task.value
            try ensureCreationActive(sourceID: sourceID)
            clearMediaOperation(id: operation.id)
            return stream
        } catch {
            clearMediaOperation(id: operation.id)
            if activeSource?.id == sourceID,
               stopOperation?.sourceID != sourceID {
                await rtcManager.destroy()
                activeSource = nil
            }
            throw XmaxError.from(error)
        }
    }

    func updateCameraSource(
        operation body: @escaping @Sendable () async throws ->
            RealtimeMediaStream
    ) async throws -> RealtimeMediaStream {
        guard let activeSource, activeSource.kind == .camera else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Create a local camera stream before updating it"
            )
        }
        try ensureNoOperationInProgress()

        let sourceID = activeSource.id
        let operation = makeMediaOperation(sourceID: sourceID) {
            try await body()
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

    func stopSource(ifKindIs kind: LocalMediaKind) async {
        guard let activeSource, activeSource.kind == kind else {
            return
        }
        let sourceID = activeSource.id
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

        if let activeSource, activeSource.id == sourceID {
            await stopSource(kind: activeSource.kind)
            await rtcManager.destroy()
            self.activeSource = nil
        }
        if stopOperation?.id == operationID {
            stopOperation = nil
        }
    }

    func stopSource(kind: LocalMediaKind) async {
        switch kind {
        case .camera:
            await cameraController.stopLocalCameraStream()
        case .image:
            await imageController?.stopLocalImageStream()
        case .video:
            await videoController?.stopLocalVideoStream()
        }
    }

    func currentTrack(for kind: LocalMediaKind) -> RealtimeVideoTrack? {
        switch kind {
        case .camera:
            cameraController.currentTrack
        case .image:
            imageController?.currentTrack
        case .video:
            videoController?.currentTrack
        }
    }

    func requiredImageController() throws -> ImageController {
        guard let imageController else {
            throw XmaxError(
                code: .internalError,
                message: "Local image media is unavailable"
            )
        }
        return imageController
    }

    func requiredVideoController() throws -> VideoController {
        guard let videoController else {
            throw XmaxError(
                code: .internalError,
                message: "Local video media is unavailable"
            )
        }
        return videoController
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

    func ensureCreationActive(sourceID: UUID) throws {
        guard activeSource?.id == sourceID,
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
