import Foundation

/// 统一协调本地媒体所有权以及 RTC Engine 生命周期。
actor XmaxRealtimeMediaManager {

    // 基础层组件
    private let rtcProvider: any RtcProviding

    // 本地媒体组件
    private let cameraManager: XmaxRealtimeCameraManager
    private let imageManager: XmaxRealtimeImageManager?
    private let videoManager: XmaxRealtimeVideoManager?

    // 本地媒体资源
    private var activeSource: ActiveLocalMediaSource?

    // 并发控制
    private var mediaOperation: LocalMediaOperation?
    private var stopOperation: LocalMediaStopOperation?

    @MainActor
    init(
        rtcProvider: any RtcProviding,
        streamController: any StreamControlling,
        mediaErrorListener: @escaping MediaSourceErrorListener
    ) {
        self.rtcProvider = rtcProvider
        cameraManager = XmaxRealtimeCameraManager(rtcProvider: rtcProvider)
        imageManager = XmaxRealtimeImageManager(
            rtcProvider: rtcProvider,
            streamController: streamController,
            errorListener: mediaErrorListener
        )
        videoManager = XmaxRealtimeVideoManager(
            rtcProvider: rtcProvider,
            streamController: streamController,
            errorListener: mediaErrorListener
        )
    }

    init(
        rtcProvider: any RtcProviding,
        cameraManager: XmaxRealtimeCameraManager,
        imageManager: XmaxRealtimeImageManager? = nil,
        videoManager: XmaxRealtimeVideoManager? = nil
    ) {
        self.rtcProvider = rtcProvider
        self.cameraManager = cameraManager
        self.imageManager = imageManager
        self.videoManager = videoManager
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
        return videoManager?.hasAudio ?? false
    }

    /// 创建相机媒体来源并取得本地媒体所有权。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream {
        try await createSource(kind: .camera) {
            try await self.cameraManager.createLocalCameraStream(
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
        let imageManager = try requiredImageManager()
        return try await createSource(kind: .image) {
            try await imageManager.createLocalImageStream(
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
        let imageManager = try requiredImageManager()
        return try await createSource(kind: .image) {
            try await imageManager.createLocalImageStream(
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
        let imageManager = try requiredImageManager()
        return try await createSource(kind: .image) {
            try await imageManager.createLocalImageStream(
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
        let videoManager = try requiredVideoManager()
        return try await createSource(kind: .video) {
            try await videoManager.createLocalVideoStream(
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
        try await replaceSource(with: .camera) { previousKind in
            if previousKind == .camera {
                return try await self.cameraManager
                    .replaceLocalCameraStream(
                        videoFormat: videoFormat,
                        position: position
                    )
            }
            return try await self.cameraManager.createLocalCameraStream(
                videoFormat: videoFormat,
                position: position
            )
        }
    }

    /// 将当前本地媒体来源替换为图片数据流。
    func replaceLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        let imageManager = try requiredImageManager()
        return try await replaceSource(with: .image) { _ in
            try await imageManager.createLocalImageStream(
                imageData: imageData,
                videoFormat: videoFormat
            )
        }
    }

    /// 将当前本地媒体来源替换为已解码图片流。
    func replaceLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        let imageManager = try requiredImageManager()
        return try await replaceSource(with: .image) { _ in
            try await imageManager.createLocalImageStream(
                decodedImage: decodedImage,
                videoFormat: videoFormat
            )
        }
    }

    /// 将当前本地媒体来源替换为图片流。
    func replaceLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        let imageManager = try requiredImageManager()
        return try await replaceSource(with: .image) { _ in
            try await imageManager.createLocalImageStream(
                fileURL: fileURL,
                videoFormat: videoFormat
            )
        }
    }

    /// 将当前本地媒体来源替换为文件视频流。
    func replaceLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream {
        let videoManager = try requiredVideoManager()
        return try await replaceSource(with: .video) { _ in
            try await videoManager.createLocalVideoStream(
                fileURL: fileURL,
                videoFormat: videoFormat
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
        try await requiredVideoManager().restartForGeneration()
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
    enum LocalMediaKind: Sendable {
        case camera
        case image
        case video
    }

    final class ActiveLocalMediaSource {
        let id: UUID
        var kind: LocalMediaKind

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
            try await self.rtcProvider.initialize()
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
                await rtcProvider.destroy()
                activeSource = nil
            }
            throw XmaxError.from(error)
        }
    }

    func replaceSource(
        with targetKind: LocalMediaKind,
        operation body: @escaping @Sendable (LocalMediaKind) async throws ->
            RealtimeMediaStream
    ) async throws -> RealtimeMediaStream {
        guard let activeSource else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Create a local media stream before replacing it"
            )
        }
        try ensureNoOperationInProgress()

        let sourceID = activeSource.id
        let previousKind = activeSource.kind
        let operation = makeMediaOperation(sourceID: sourceID) {
            if previousKind != targetKind || targetKind != .camera {
                await self.stopSource(kind: previousKind)
                try await self.updateSourceKind(
                    targetKind,
                    sourceID: sourceID
                )
            }
            return try await body(previousKind)
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
            await rtcProvider.destroy()
            self.activeSource = nil
        }
        if stopOperation?.id == operationID {
            stopOperation = nil
        }
    }

    func stopSource(kind: LocalMediaKind) async {
        switch kind {
        case .camera:
            await cameraManager.stopLocalCameraStream()
        case .image:
            await imageManager?.stopLocalImageStream()
        case .video:
            await videoManager?.stopLocalVideoStream()
        }
    }

    func currentTrack(for kind: LocalMediaKind) -> RealtimeVideoTrack? {
        switch kind {
        case .camera:
            cameraManager.currentTrack
        case .image:
            imageManager?.currentTrack
        case .video:
            videoManager?.currentTrack
        }
    }

    func updateSourceKind(
        _ kind: LocalMediaKind,
        sourceID: UUID
    ) throws {
        guard let activeSource, activeSource.id == sourceID else {
            throw XmaxError(
                code: .cancelled,
                message: "Local media stream replacement was cancelled"
            )
        }
        activeSource.kind = kind
    }

    func requiredImageManager() throws -> XmaxRealtimeImageManager {
        guard let imageManager else {
            throw XmaxError(
                code: .internalError,
                message: "Local image media is unavailable"
            )
        }
        return imageManager
    }

    func requiredVideoManager() throws -> XmaxRealtimeVideoManager {
        guard let videoManager else {
            throw XmaxError(
                code: .internalError,
                message: "Local video media is unavailable"
            )
        }
        return videoManager
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
