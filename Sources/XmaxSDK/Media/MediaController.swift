//
//  MediaController.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 统一协调本地媒体所有权以及 RTC Engine 生命周期。
actor MediaController: MediaControlling {

    /// 配置本地输入并发送音视频帧。
    private let rtcManager: any RtcManaging

    /// 管理摄像头采集及本地预览。
    private let cameraController: any CameraControlling

    /// 管理图片输入和预览。
    private let imageController: (any ImageControlling)?

    /// 将轨迹映射为媒体坐标并发送。
    private let interactionController: any InteractionControlling

    /// 管理文件视频输入和播放。
    private let videoController: (any VideoControlling)?

    /// 当前本地媒体来源及其有效期。
    private var activeSource: ActiveLocalMediaSource?

    /// 正在创建本地媒体流的操作。
    private var mediaOperation: LocalMediaOperation?

    /// 正在执行的本地媒体停止操作。
    private var stopOperation: LocalMediaStopOperation?

    /// 创建并连接摄像头、图片、视频及交互控制组件。
    ///
    /// - Parameters:
    ///   - rtcManager: RTC 引擎与媒体适配组件。
    ///   - mediaService: 提供模型尺寸规则的媒体服务。
    ///   - videoFrameListener: 接收本地视频帧的回调。
    ///   - audioFrameListener: 接收本地音频帧的回调。
    ///   - errorListener: 接收媒体运行错误的回调。
    ///   - interactionListener: 接收视频像素交互坐标的回调。
    @MainActor
    init(
        rtcManager: any RtcManaging,
        mediaService: any MediaServicing = MediaService(),
        videoFrameListener: @escaping MediaVideoFrameListener,
        audioFrameListener: @escaping MediaAudioFrameListener,
        errorListener: @escaping XmaxErrorListener,
        interactionListener: @escaping InteractionListener
    ) {
        self.rtcManager = rtcManager
        cameraController = CameraController(
            rtcManager: rtcManager,
            mediaService: mediaService,
            videoFrameListener: videoFrameListener,
            errorListener: errorListener
        )
        imageController = ImageController(
            rtcManager: rtcManager,
            mediaService: mediaService,
            frameListener: videoFrameListener
        )
        interactionController = InteractionController(
            listener: interactionListener
        )
        videoController = VideoController(
            rtcManager: rtcManager,
            mediaService: mediaService,
            videoFrameListener: videoFrameListener,
            audioFrameListener: audioFrameListener,
            errorListener: errorListener
        )
    }

    /// 使用指定组件创建统一媒体控制器。
    ///
    /// - Parameters:
    ///   - rtcManager: RTC 引擎与媒体适配组件。
    ///   - cameraController: 摄像头媒体控制器。
    ///   - imageController: 图片媒体控制器；`nil` 时不提供图片来源。
    ///   - interactionListener: 接收视频像素交互坐标的回调。
    ///   - videoController: 视频媒体控制器；`nil` 时不提供文件视频来源。
    init(
        rtcManager: any RtcManaging,
        cameraController: any CameraControlling,
        imageController: (any ImageControlling)? = nil,
        interactionListener: @escaping InteractionListener = { _, _ in },
        videoController: (any VideoControlling)? = nil
    ) {
        self.rtcManager = rtcManager
        self.cameraController = cameraController
        self.imageController = imageController
        interactionController = InteractionController(
            listener: interactionListener
        )
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

    /// 图片和文件视频使用完整内容适配生成画布。
    var usesContainPadding: Bool {
        activeSource?.kind == .image || activeSource?.kind == .video
    }

    /// 当前媒体来源是否包含由 SDK 管理的本地音频。
    var hasAudio: Bool {
        switch activeSource?.kind {
        case .camera:
            return cameraController.useMicrophone
        case .video:
            return videoController?.hasAudio ?? false
        default:
            return false
        }
    }

    /// 当前本地文件视频的音频预览音量。
    var localAudioVolume: Float {
        get async {
            guard let videoController else {
                return LocalAudioPreviewPlayer.defaultVolume
            }
            return await videoController.localAudioVolume
        }
    }

    /// 设置当前相机流的一次性内部就绪处理。
    ///
    /// - Parameter handler: 收到有效帧且预览已绑定时调用；传入空值时清除。
    func setCameraPreviewReadyHandler(
        _ handler: CameraPreviewReadyHandler?
    ) {
        cameraController.setPreviewReadyHandler(handler)
    }

    /// 开始接收当前生成任务的触控轨迹。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 本地媒体输出规格。
    func startInteraction(
        taskID: String,
        videoFormat: RealtimeVideoFormat
    ) async {
        await interactionController.startInteraction(
            taskID: taskID,
            videoFormat: videoFormat
        )
    }

    /// 停止接收轨迹并清理当前任务。
    func stopInteraction() async {
        await interactionController.stopInteraction()
    }

    /// 提交触控轨迹。
    ///
    /// - Parameter frame: 当前视图中采集的轨迹及显示尺寸。
    func submitInteraction(
        _ frame: InteractionFrame
    ) async {
        await interactionController.submitInteraction(frame)
    }

    /// 创建并持有本地相机媒体流，同时启动采集和本地预览。
    ///
    /// - Parameters:
    ///   - videoFormat: 相机采集使用的目标视频格式。
    ///   - position: 首次启用的摄像头位置。
    ///   - useMicrophone: 是否使用麦克风；创建时检查权限，连接时启动采集。
    /// - Returns: 包含本地相机视频轨道的媒体流。
    /// - Throws: 相机权限、RTC 初始化或采集启动失败时抛出错误；
    ///   已有活动媒体来源时也会失败。
    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition,
        useMicrophone: Bool = false
    ) async throws -> RealtimeMediaStream {
        try await createSource(kind: .camera) {
            try await self.cameraController.createLocalCameraStream(
                videoFormat: videoFormat,
                position: position,
                useMicrophone: useMicrophone
            )
        }
    }

    /// 为启用了麦克风的相机流启动内部音频采集；其他来源不受影响。
    ///
    /// - Throws: 操作被取消或 RTC 音频采集启动失败时抛出错误。
    func startMicrophoneCapture() throws {
        try Task.checkCancellation()
        guard activeSource?.kind == .camera else { return }
        try cameraController.startMicrophoneCapture()
    }

    /// 停止相机流的麦克风采集，保留相机预览和麦克风配置。
    ///
    /// - Throws: RTC 音频采集停止失败时抛出错误。
    func stopMicrophoneCapture() throws {
        guard activeSource?.kind == .camera else { return }
        try cameraController.stopMicrophoneCapture()
    }

    /// 从编码后的图片数据创建并持有本地图片媒体流。
    ///
    /// - Parameter imageData: PNG、JPEG 等受支持格式的编码图片数据。
    /// - Returns: 包含持续输出图片帧的本地视频轨道的媒体流。
    /// - Throws: 图片数据无效、媒体准备或外部视频源启动失败时抛出错误；
    ///   已有活动媒体来源时也会失败。
    func createLocalImageStream(
        imageData: Data
    ) async throws -> RealtimeMediaStream {
        let imageController = try requiredImageController()
        return try await createSource(kind: .image) {
            try await imageController.createLocalImageStream(
                imageData: imageData
            )
        }
    }

    /// 从已解码图片创建并持有本地图片媒体流。
    ///
    /// - Parameter decodedImage: 已经完成方向规范化和像素解码的图片。
    /// - Returns: 包含持续输出图片帧的本地视频轨道的媒体流。
    /// - Throws: 图片像素处理、媒体准备或外部视频源启动失败时抛出错误；
    ///   已有活动媒体来源时也会失败。
    func createLocalImageStream(
        decodedImage: any DecodedImage
    ) async throws -> RealtimeMediaStream {
        let imageController = try requiredImageController()
        return try await createSource(kind: .image) {
            try await imageController.createLocalImageStream(
                decodedImage: decodedImage
            )
        }
    }

    /// 从本地图片文件创建并持有本地图片媒体流。
    ///
    /// - Parameter fileURL: 可读取的本地图片文件地址。
    /// - Returns: 包含持续输出图片帧的本地视频轨道的媒体流。
    /// - Throws: 文件读取、图片解码、媒体准备或外部视频源启动失败时
    ///   抛出错误；
    ///   已有活动媒体来源时也会失败。
    func createLocalImageStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        let imageController = try requiredImageController()
        return try await createSource(kind: .image) {
            try await imageController.createLocalImageStream(
                fileURL: fileURL
            )
        }
    }

    /// 从本地视频文件创建并持有本地视频媒体流。
    ///
    /// - Parameter fileURL: 可读取的本地视频文件地址。
    /// - Returns: 包含循环输出文件视频帧的本地媒体流。
    /// - Throws: 文件读取、音视频准备、权限或外部媒体源启动失败时
    ///   抛出错误；
    ///   已有活动媒体来源时也会失败。
    func createLocalVideoStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        let videoController = try requiredVideoController()
        return try await createSource(kind: .video) {
            try await videoController.createLocalVideoStream(
                fileURL: fileURL
            )
        }
    }

    /// 停止并释放当前本地相机媒体流、预览绑定和 RTC 资源；
    /// 当前来源不是相机时忽略。
    func stopLocalCameraStream() async {
        await stopSource(ifKindIs: .camera)
    }

    /// 停止并释放当前本地图片媒体流、帧输出、预览绑定和 RTC 资源；
    /// 当前来源不是图片时忽略。
    func stopLocalImageStream() async {
        await stopSource(ifKindIs: .image)
    }

    /// 停止并释放当前本地视频媒体流、音视频输出、预览绑定和 RTC 资源；
    /// 当前来源不是文件视频时忽略。
    func stopLocalVideoStream() async {
        await stopSource(ifKindIs: .video)
    }

    /// 停止并释放当前本地媒体流、预览绑定和 RTC Engine；
    /// 没有活动来源时忽略。
    func stopLocalStream() async {
        guard let activeSource else {
            return
        }
        await stopSource(ifKindIs: activeSource.kind)
    }

    /// 静音或恢复文件视频的本地音频预览，不影响播放时间轴和 RTC 音频推流。
    ///
    /// - Parameter muted: `true` 表示仅静音本地播放器；
    func setLocalAudioPreviewMuted(
        _ muted: Bool
    ) async {
        guard activeSource?.kind == .video, let videoController else {
            return
        }
        await videoController.setLocalAudioPreviewMuted(muted)
    }

    /// 设置本地文件视频的音频预览音量。
    ///
    /// - Parameter volume: 已校验且取值范围为 `0...1` 的音量。
    func setLocalAudioVolume(
        _ volume: Float
    ) async {
        await videoController?.setLocalAudioVolume(volume)
    }

    /// 在前置和后置摄像头之间切换当前相机。
    ///
    /// - Returns: 包含更新后摄像头位置的本地媒体流。
    /// - Throws: 当前来源不是相机、存在并发媒体操作或摄像头切换失败时抛出错误。
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

    /// 将当前摄像头的采集方向和尺寸同步到预览窗口；其他媒体来源保持不变。
    ///
    /// - Throws: 模型不支持目标尺寸或采集配置失败时抛出错误。
    func updateCameraOrientation() async throws {
        guard activeSource?.kind == .camera, let track = currentTrack,
              let orientation = await track.displayOrientation else { return }
        guard currentTrack === track else { return }
        try await cameraController.updateOrientation(orientation)
    }

    /// 判断指定媒体流是否由当前活动媒体来源持有。
    ///
    /// - Parameter stream: 需要验证所有权的媒体流。
    /// - Returns: 媒体流的视频轨道由当前活动来源持有时返回 `true`，
    ///   否则返回 `false`。
    func owns(
        _ stream: RealtimeMediaStream
    ) -> Bool {
        guard let videoTrack = stream.videoTrack else {
            return false
        }
        return videoTrack === currentTrack
    }
}

private extension MediaController {

    /// 区分当前持有的本地媒体来源。
    enum LocalMediaKind: Sendable {

        /// 摄像头实时采集。
        case camera

        /// 图片持续输出。
        case image

        /// 文件视频播放。
        case video
    }

    /// 标识当前活动媒体来源及其类型。
    final class ActiveLocalMediaSource {

        /// 来源的唯一标识。
        let id: UUID

        /// 当前本地媒体来源。
        let kind: LocalMediaKind

        /// 记录当前媒体来源的身份和类型。
        init(
            id: UUID,
            kind: LocalMediaKind
        ) {
            self.id = id
            self.kind = kind
        }
    }

    /// 关联媒体创建任务与所属来源。
    struct LocalMediaOperation {

        /// 媒体创建操作的唯一标识。
        let id: UUID

        /// 本次操作所属媒体流的有效期标识。
        let sourceID: UUID

        /// 创建并返回本地媒体流的异步任务。
        let task: Task<RealtimeMediaStream, any Error>
    }

    /// 关联媒体停止任务与所属来源。
    struct LocalMediaStopOperation {

        /// 媒体停止操作的唯一标识。
        let id: UUID

        /// 停止操作对应的媒体流标识。
        let sourceID: UUID

        /// 释放指定媒体流资源的异步任务。
        let task: Task<Void, Never>
    }

    /// 取得本地媒体所有权并执行媒体创建任务。
    ///
    /// - Parameters:
    ///   - kind: 需要创建的媒体来源类型。
    ///   - body: 引擎初始化后执行的媒体创建操作。
    /// - Returns: 创建成功且仍有效的本地媒体流。
    /// - Throws: 已有来源、引擎初始化或媒体创建失败，以及操作取消时抛出错误。
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
            try Task.checkCancellation()
            return try await body()
        }
        mediaOperation = operation

        do {
            let stream = try await withTaskCancellationHandler {
                try await operation.task.value
            } onCancel: {
                operation.task.cancel()
            }
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

    /// 停止指定类型的本地媒体来源。
    ///
    /// - Parameter kind: 需要停止的媒体来源类型。
    func stopSource(
        ifKindIs kind: LocalMediaKind
    ) async {
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

    /// 等待媒体创建结束并释放指定来源及 RTC 引擎。
    ///
    /// - Parameters:
    ///   - sourceID: 待释放的媒体来源标识。
    ///   - operationID: 当前停止操作的标识。
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
                    XmaxLogger.realtime.error(
                        message: "等待本地媒体操作结束失败 " +
                            "(Failed to Await Local Media Operation Completion)\n" +
                            "└─ \(XmaxLogger.localized("原因：", "Reason: "))" +
                            (error as NSError).localizedDescription
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

    /// 停止指定类型的本地媒体来源。
    ///
    /// - Parameter kind: 需要停止的媒体来源类型。
    func stopSource(
        kind: LocalMediaKind
    ) async {
        switch kind {
        case .camera:
            await cameraController.stopLocalCameraStream()
        case .image:
            await imageController?.stopLocalImageStream()
        case .video:
            await videoController?.stopLocalVideoStream()
        }
    }

    /// 获取指定来源类型当前持有的视频轨道。
    ///
    /// - Parameter kind: 本地媒体来源类型。
    /// - Returns: 对应组件的视频轨道；尚未创建时返回 `nil`。
    func currentTrack(
        for kind: LocalMediaKind
    ) -> RealtimeVideoTrack? {
        switch kind {
        case .camera:
            cameraController.currentTrack
        case .image:
            imageController?.currentTrack
        case .video:
            videoController?.currentTrack
        }
    }

    /// 获取已配置的图片控制器。
    ///
    /// - Returns: 当前图片控制器。
    /// - Throws: 图片能力未配置时抛出错误。
    func requiredImageController() throws -> any ImageControlling {
        guard let imageController else {
            throw XmaxError(
                code: .internalError,
                message: "Local image media is unavailable"
            )
        }
        return imageController
    }

    /// 获取已配置的文件视频控制器。
    ///
    /// - Returns: 当前文件视频控制器。
    /// - Throws: 文件视频能力未配置时抛出错误。
    func requiredVideoController() throws -> any VideoControlling {
        guard let videoController else {
            throw XmaxError(
                code: .internalError,
                message: "Local video media is unavailable"
            )
        }
        return videoController
    }

    /// 创建关联媒体来源的异步操作。
    ///
    /// - Parameters:
    ///   - sourceID: 操作所属媒体来源标识。
    ///   - operation: 创建本地媒体流的异步操作。
    /// - Returns: 包含唯一操作标识和任务的媒体操作。
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

    /// 校验媒体创建结果仍属于当前有效来源。
    ///
    /// - Parameter sourceID: 媒体创建对应的来源标识。
    /// - Throws: 来源已失效或进入停止流程时抛出取消错误。
    func ensureCreationActive(
        sourceID: UUID
    ) throws {
        guard activeSource?.id == sourceID,
              stopOperation?.sourceID != sourceID else {
            throw XmaxError(
                code: .cancelled,
                message: "Local media stream creation was cancelled"
            )
        }
    }

    /// 校验当前没有媒体创建或停止操作。
    ///
    /// - Throws: 存在未完成媒体操作时抛出错误。
    func ensureNoOperationInProgress() throws {
        guard mediaOperation == nil, stopOperation == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Another local media operation is already in progress"
            )
        }
    }

    /// 清除匹配的媒体创建操作。
    ///
    /// - Parameter id: 需要清除的操作标识。
    func clearMediaOperation(
        id: UUID
    ) {
        if mediaOperation?.id == id {
            mediaOperation = nil
        }
    }

    /// 判断错误是否为 SDK 操作取消。
    ///
    /// - Parameter error: 待判断的错误。
    /// - Returns: SDK 错误码为取消时返回 `true`。
    static func isCancelled(
        _ error: any Error
    ) -> Bool {
        (error as? XmaxError)?.code == .cancelled
    }
}
