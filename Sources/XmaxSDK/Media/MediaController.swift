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

/// Coordinates local media ownership and the RTC engine lifecycle.
actor MediaController: MediaControlling {

    // MARK: - Dependencies

    /// The adapter for local input and media frame delivery.
    private let rtcManager: any RtcManaging

    /// The camera and preview controller.
    private let cameraController: any CameraControlling

    /// The image and preview controller.
    private let imageController: (any ImageControlling)?

    /// The trajectory coordinate and delivery controller.
    private let interactionController: any InteractionControlling

    /// The video file input and playback controller.
    private let videoController: (any VideoControlling)?

    /// The external video and preview controller.
    private let externalController: (any ExternalVideoControlling)?

    // MARK: - State

    /// The active media source and its validity.
    private var activeSource: ActiveLocalMediaSource?

    /// The pending media creation operation.
    private var mediaOperation: LocalMediaOperation?

    /// The pending media stop operation.
    private var stopOperation: LocalMediaStopOperation?

    /// Creates the camera, image, video, and interaction components.
    ///
    /// - Parameters:
    ///   - rtcManager: The RTC engine and media adapter.
    ///   - mediaService: The model media sizing service.
    ///   - videoFrameListener: The local video frame handler.
    ///   - audioFrameListener: The local audio frame handler.
    ///   - errorListener: The runtime media failure handler.
    ///   - interactionListener: The video interaction coordinate handler.
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

        externalController = ExternalVideoController(
            rtcManager: rtcManager,
            mediaService: mediaService,
            videoFrameListener: videoFrameListener,
            audioFrameListener: audioFrameListener,
            errorListener: errorListener
        )
    }

    /// Creates a media controller with the specified components.
    ///
    /// - Parameters:
    ///   - rtcManager: The RTC engine and media adapter.
    ///   - cameraController: The camera controller.
    ///   - imageController: The image controller, or `nil` to omit image input.
    ///   - interactionListener: The video interaction coordinate handler.
    ///   - videoController: The video controller, or `nil` to omit video file input.
    ///   - externalController: The external controller, or `nil` to omit external video input.
    init(
        rtcManager: any RtcManaging,
        cameraController: any CameraControlling,
        imageController: (any ImageControlling)? = nil,
        interactionListener: @escaping InteractionListener = { _, _ in
        },
        videoController: (any VideoControlling)? = nil,
        externalController: (any ExternalVideoControlling)? = nil
    ) {
        self.rtcManager = rtcManager
        self.cameraController = cameraController
        self.imageController = imageController
        interactionController = InteractionController(
            listener: interactionListener
        )
        self.videoController = videoController
        self.externalController = externalController
    }

    /// The active video track, if a local source exists.
    var currentTrack: RealtimeVideoTrack? {
        guard let activeSource else {
            return nil
        }
        return currentTrack(for: activeSource.kind)
    }

    /// The current video format, if a track exists.
    var currentVideoFormat: RealtimeVideoFormat? {
        currentTrack?.videoFormat
    }

    /// Whether the source includes SDK-managed audio.
    var hasAudio: Bool {
        switch activeSource?.kind {
        case .camera:
            return cameraController.useMicrophone
        case .video:
            return videoController?.hasAudio ?? false
        case .external:
            return externalController?.hasAudio ?? false
        default:
            return false
        }
    }

    /// The local video file preview volume.
    var localAudioVolume: Float {
        get async {
            guard let videoController else {
                return LocalAudioPreviewPlayer.defaultVolume
            }
            return await videoController.localAudioVolume
        }
    }

    /// Sets a one-shot camera readiness handler.
    ///
    /// - Parameter handler: The handler called after a valid frame and preview binding, or `nil` to
    ///   remove it.
    func setCameraPreviewReadyHandler(
        _ handler: CameraPreviewReadyHandler?
    ) {
        cameraController.setPreviewReadyHandler(handler)
    }

    /// Starts accepting interactions for a generation task.
    ///
    /// - Parameters:
    ///   - taskID: The generation task identifier.
    ///   - videoFormat: The resolved local media format.
    func startInteraction(
        taskID: String,
        videoFormat: RealtimeVideoFormat
    ) async {
        await interactionController.startInteraction(
            taskID: taskID,
            videoFormat: videoFormat
        )
    }

    /// Stops accepting interactions and clears the task.
    func stopInteraction() async {
        await interactionController.stopInteraction()
    }

    /// Submits a touch trajectory.
    ///
    /// - Parameter frame: The view trajectory and viewport dimensions.
    func submitInteraction(
        _ frame: InteractionFrame
    ) async {
        await interactionController.submitInteraction(frame)
    }

    /// Creates a camera stream and starts local preview.
    ///
    /// - Parameters:
    ///   - videoFormat: The requested camera video format.
    ///   - position: The initial camera position.
    ///   - useMicrophone: Whether to request microphone access and capture audio while connected.
    ///
    /// - Returns: The local camera media stream.
    ///
    /// - Throws: An error if camera permission, RTC initialization, or capture startup fails; an
    ///   existing active media source also prevents creation.
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

    /// Starts microphone capture for a configured camera source.
    ///
    /// - Throws: An error if the operation is cancelled or RTC audio capture cannot start.
    func startMicrophoneCapture() throws {
        try Task.checkCancellation()
        guard activeSource?.kind == .camera else {
            return
        }
        try cameraController.startMicrophoneCapture()
    }

    /// Stops microphone capture while retaining camera preview and configuration.
    ///
    /// - Throws: An error if RTC audio capture cannot stop.
    func stopMicrophoneCapture() throws {
        guard activeSource?.kind == .camera else {
            return
        }
        try cameraController.stopMicrophoneCapture()
    }

    /// Creates a local image stream from encoded data.
    ///
    /// - Parameter imageData: Encoded image data, such as PNG or JPEG.
    ///
    /// - Returns: The local track continuously delivering image frames.
    ///
    /// - Throws: An error if image data, media preparation, or external video startup fails; an
    ///   existing active media source also prevents creation.
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

    /// Creates a local stream from a decoded image.
    ///
    /// - Parameter decodedImage: The orientation-corrected decoded image.
    ///
    /// - Returns: The local track continuously delivering image frames.
    ///
    /// - Throws: An error if image processing, media preparation, or external video startup fails;
    ///   an existing active media source also prevents creation.
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

    /// Creates a local stream from an image file.
    ///
    /// - Parameter fileURL: The URL of a readable local image file.
    ///
    /// - Returns: The local track continuously delivering image frames.
    ///
    /// - Throws: An error if file reading, image decoding, media preparation, or external video
    ///   startup fails; an existing active media source also prevents creation.
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

    /// Creates a local stream from a video file.
    ///
    /// - Parameter fileURL: The URL of a readable local video file.
    ///
    /// - Returns: The local media stream looping the video file.
    ///
    /// - Throws: An error if file reading, media preparation, or external source startup fails; an
    ///   existing active media source also prevents creation.
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

    /// Stops the camera stream and releases its preview and RTC resources; other input sources are
    /// unaffected.
    func stopLocalCameraStream() async {
        await stopSource(ifKindIs: .camera)
    }

    /// Stops the image stream and releases frame delivery, preview, and RTC resources; other input
    /// sources are unaffected.
    func stopLocalImageStream() async {
        await stopSource(ifKindIs: .image)
    }

    /// Stops video file playback and releases preview and RTC resources; other input sources are
    /// unaffected.
    func stopLocalVideoStream() async {
        await stopSource(ifKindIs: .video)
    }

    /// Binds an external source as a local video stream.
    ///
    /// - Parameter source: The video source owned by your app.
    ///
    /// - Returns: The local external video stream.
    ///
    /// - Throws: An error if a source exists, a component is unavailable, or binding fails.
    func createExternalVideoStream(
        source: any RealtimeExternalVideoSource
    ) async throws -> RealtimeMediaStream {
        guard let externalController else {
            throw XmaxError(
                code: .internalError,
                message: "External video media is unavailable"
            )
        }
        return try await createSource(kind: .external) {
            try await externalController.createExternalVideoStream(source: source)
        }
    }

    /// Unbinds external video without releasing your app's capture or playback resources.
    func stopExternalVideoStream() async {
        await stopSource(ifKindIs: .external)
    }

    /// Stops local media and releases preview and the RTC engine; does nothing if no source is
    /// active.
    func stopLocalStream() async {
        guard let activeSource else {
            return
        }
        await stopSource(ifKindIs: activeSource.kind)
    }

    /// Mutes or restores local preview without changing playback timing or RTC audio.
    ///
    /// - Parameter muted: `true` to mute only local playback;
    func setLocalAudioPreviewMuted(
        _ muted: Bool
    ) async {
        guard activeSource?.kind == .video, let videoController else {
            return
        }
        await videoController.setLocalAudioPreviewMuted(muted)
    }

    /// Sets the local video file preview volume.
    ///
    /// - Parameter volume: The validated volume, in the range `0...1`.
    func setLocalAudioVolume(
        _ volume: Float
    ) async {
        await videoController?.setLocalAudioVolume(volume)
    }

    /// Switches the active camera position.
    ///
    /// - Returns: The local stream with its updated camera position.
    ///
    /// - Throws: An error if no camera is active, an operation conflicts, or switching fails.
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

    /// Updates camera orientation and dimensions for the preview window.
    ///
    /// - Throws: An error if the model rejects the dimensions or capture configuration fails.
    func updateCameraOrientation() async throws {
        guard activeSource?.kind == .camera, let track = currentTrack,
            let orientation = await track.displayOrientation
        else {
            return
        }
        guard currentTrack === track else {
            return
        }
        try await cameraController.updateOrientation(orientation)
    }

    /// Updates the active camera format while retaining its track.
    ///
    /// - Parameter videoFormat: The new dimensions, frame rate, and encoding settings.
    ///
    /// - Throws: An error if no camera exists, a media operation conflicts, or configuration fails.
    func updateCameraFormat(
        _ videoFormat: RealtimeVideoFormat
    ) async throws {
        guard activeSource?.kind == .camera else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Camera preview is not started"
            )
        }
        try ensureNoOperationInProgress()
        try await cameraController.updateVideoFormat(videoFormat)
    }

    /// Checks whether a stream belongs to the active media source.
    ///
    /// - Parameter stream: The stream whose ownership is checked.
    ///
    /// - Returns: `true` if the active source owns the stream's video track; otherwise `false`.
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

    /// The active local input source.
    enum LocalMediaKind: Sendable {

        /// Live camera capture.
        case camera

        /// Repeated image frames.
        case image

        /// Video file playback.
        case video

        /// Video frames supplied by your app.
        case external
    }

    /// The identity and kind of an active media source.
    final class ActiveLocalMediaSource {

        /// The source identifier.
        let id: UUID

        /// The active local media source.
        let kind: LocalMediaKind

        /// Creates a media source context.
        init(
            id: UUID,
            kind: LocalMediaKind
        ) {
            self.id = id
            self.kind = kind
        }
    }

    /// A media creation task associated with its source.
    struct LocalMediaOperation {

        /// The media creation operation identifier.
        let id: UUID

        /// The media source revision for this operation.
        let sourceID: UUID

        /// The asynchronous local stream creation task.
        let task: Task<RealtimeMediaStream, any Error>
    }

    /// A media stop task associated with its source.
    struct LocalMediaStopOperation {

        /// The media stop operation identifier.
        let id: UUID

        /// The media source being stopped.
        let sourceID: UUID

        /// The resource cleanup task.
        let task: Task<Void, Never>
    }

    /// Claims media ownership and creates a local stream.
    ///
    /// - Parameters:
    ///   - kind: The source type to create.
    ///   - body: The creation operation performed after engine initialization.
    ///
    /// - Returns: The created local stream whose binding remains current.
    ///
    /// - Throws: An error if a source exists, initialization or creation fails, or the call is
    ///   cancelled.
    func createSource(
        kind: LocalMediaKind,
        operation body:
            @escaping @Sendable () async throws ->
            RealtimeMediaStream
    ) async throws -> RealtimeMediaStream {
        guard activeSource == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local media stream before creating another one"
            )
        }

        let sourceID = UUID()
        activeSource = ActiveLocalMediaSource(
            id: sourceID,
            kind: kind
        )
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
            if activeSource?.id == sourceID, stopOperation?.sourceID != sourceID {
                await rtcManager.destroy()
                activeSource = nil
            }
            throw XmaxError.from(error)
        }
    }

    /// Stops a local source of the specified type.
    ///
    /// - Parameter kind: The source type to stop.
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

    /// Waits for media creation and releases the source and RTC engine.
    ///
    /// - Parameters:
    ///   - sourceID: The media source to release.
    ///   - operationID: The current stop operation identifier.
    func performStop(
        sourceID: UUID,
        operationID: UUID
    ) async {
        if let mediaOperation, mediaOperation.sourceID == sourceID {
            do {
                _ = try await mediaOperation.task.value
            } catch {
                if !Self.isCancelled(error) {
                    XmaxLogger.realtime.error(
                        message: "等待本地媒体操作结束失败 "
                            + "(Failed to Await Local Media Operation Completion)\n"
                            + "└─ \(XmaxLogger.localized("原因：", "Reason: "))"
                            + (error as NSError).localizedDescription
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

    /// Stops a local source of the specified type.
    ///
    /// - Parameter kind: The source type to stop.
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
        case .external:
            await externalController?.stopExternalVideoStream()
        }
    }

    /// Returns the track owned by a source type.
    ///
    /// - Parameter kind: The local source type.
    ///
    /// - Returns: The source's video track, or `nil` before creation.
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
        case .external:
            externalController?.currentTrack
        }
    }

    /// Returns the configured image controller.
    ///
    /// - Returns: The image controller.
    ///
    /// - Throws: An error if image input is not configured.
    func requiredImageController() throws -> any ImageControlling {
        guard let imageController else {
            throw XmaxError(
                code: .internalError,
                message: "Local image media is unavailable"
            )
        }
        return imageController
    }

    /// Returns the configured video file controller.
    ///
    /// - Returns: The video file controller.
    ///
    /// - Throws: An error if video file input is not configured.
    func requiredVideoController() throws -> any VideoControlling {
        guard let videoController else {
            throw XmaxError(
                code: .internalError,
                message: "Local video media is unavailable"
            )
        }
        return videoController
    }

    /// Creates an asynchronous media operation for a source.
    ///
    /// - Parameters:
    ///   - sourceID: The operation's media source identifier.
    ///   - operation: The asynchronous stream creation operation.
    ///
    /// - Returns: The identified media operation and task.
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

    /// Verifies that media creation still belongs to the active source.
    ///
    /// - Parameter sourceID: The source being created.
    ///
    /// - Throws: A cancellation error if the source is stale or stopping.
    func ensureCreationActive(
        sourceID: UUID
    ) throws {
        guard activeSource?.id == sourceID, stopOperation?.sourceID != sourceID else {
            throw XmaxError(
                code: .cancelled,
                message: "Local media stream creation was cancelled"
            )
        }
    }

    /// Verifies that no media creation or stop operation is pending.
    ///
    /// - Throws: An error if a media operation is still pending.
    func ensureNoOperationInProgress() throws {
        guard mediaOperation == nil, stopOperation == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Another local media operation is already in progress"
            )
        }
    }

    /// Clears a matching media creation operation.
    ///
    /// - Parameter id: The operation identifier to clear.
    func clearMediaOperation(
        id: UUID
    ) {
        if mediaOperation?.id == id {
            mediaOperation = nil
        }
    }

    /// Checks whether an error represents SDK cancellation.
    ///
    /// - Parameter error: The error to check.
    ///
    /// - Returns: `true` if the SDK error code is cancellation.
    static func isCancelled(
        _ error: any Error
    ) -> Bool {
        (error as? XmaxError)?.code == .cancelled
    }
}
