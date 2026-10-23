//
//  ImageController.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreGraphics
import Foundation

/// Coordinates image decoding, repeated frame delivery, and preview.
final class ImageController: ImageControlling, @unchecked Sendable {

    /// The local image track identifier.
    private static let localVideoTrackID = "video0"

    /// The RTC external video adapter.
    private let rtcManager: any RtcManaging

    /// The image decoder and frame producer.
    private let imageManager: any ImageManaging

    /// The model default frame rate provider.
    private let mediaService: any MediaServicing

    /// The image video frame handler.
    private let frameListener: MediaVideoFrameListener

    /// The lock protecting the track and frame task.
    private let stateLock = NSLock()

    /// The image video track.
    private var activeTrack: RealtimeVideoTrack?

    /// The task repeatedly emitting image frames.
    private var outputTask: Task<Void, Never>?

    /// Creates an image stream and preview controller.
    init(
        rtcManager: any RtcManaging,
        imageManager: any ImageManaging = ImageManager(),
        mediaService: any MediaServicing = MediaService(),
        frameListener: @escaping MediaVideoFrameListener
    ) {
        self.rtcManager = rtcManager
        self.imageManager = imageManager
        self.mediaService = mediaService
        self.frameListener = frameListener
    }

    /// The image track available for preview and uplink.
    var currentTrack: RealtimeVideoTrack? {
        stateLock.withLock {
            activeTrack
        }
    }

    /// Creates a stream of repeated frames from a decoded image.
    ///
    /// - Parameter decodedImage: The orientation-corrected decoded image.
    ///
    /// - Returns: The local image video stream.
    ///
    /// - Throws: An error if a stream exists, the format is invalid, or image processing or frame
    ///   startup fails.
    func createLocalImageStream(
        decodedImage: any DecodedImage
    ) async throws -> RealtimeMediaStream {
        try await createStream(input: .decoded(decodedImage))
    }

    /// Creates a stream of repeated frames from encoded image data.
    ///
    /// - Parameter imageData: The nonempty encoded image data.
    ///
    /// - Returns: The local image video stream.
    ///
    /// - Throws: An error if a stream exists or data, format, decoding, or frame startup fails.
    func createLocalImageStream(
        imageData: Data
    ) async throws -> RealtimeMediaStream {
        try await createStream(input: .data(imageData))
    }

    /// Creates a stream of repeated frames from a local image file.
    ///
    /// - Parameter fileURL: The URL of a readable local image file.
    ///
    /// - Returns: The local image video stream.
    ///
    /// - Throws: An error if a stream exists or file reading, validation, decoding, or startup
    ///   fails.
    func createLocalImageStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream {
        try await createStream(input: .file(fileURL))
    }

    /// Stops image frame delivery and releases its track and preview binding.
    func stopLocalImageStream() async {
        let (track, task) = stateLock.withLock {
            let resources = (activeTrack, outputTask)
            activeTrack = nil
            outputTask = nil
            return resources
        }

        task?.cancel()
        await task?.value

        if let track {
            await MainActor.run {
                do {
                    try VideoRenderRegistry.binding(for: track)?.detach()
                } catch {
                    XmaxLogger.realtime.error(
                        message: "解除本地图片预览绑定失败 (Failed to Detach Local Image Preview)\n"
                            + "└─ \(XmaxLogger.localized("原因：", "Reason: "))"
                            + (error as NSError).localizedDescription
                    )
                }

                VideoRenderRegistry.unregister(track)
            }
        }
    }
}

private extension ImageController {

    /// An encoded, decoded, or file-backed image source.
    enum ImageInput: Sendable {

        /// The encoded image data.
        case data(Data)

        /// A decoded image ready for processing.
        case decoded(any DecodedImage)

        /// A local image file.
        case file(URL)
    }

    /// Creates image preview and periodic frame delivery.
    ///
    /// - Parameter input: The image source.
    ///
    /// - Returns: The local image video stream.
    ///
    /// - Throws: An error if a stream exists or reading, decoding, processing, or RTC configuration
    ///   fails.
    func createStream(
        input: ImageInput
    ) async throws -> RealtimeMediaStream {
        guard currentTrack == nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Stop the current local image stream before creating another one"
            )
        }

        var track: RealtimeVideoTrack?

        do {
            let image = try decode(input)
            let resolvedFormat = try resolveVideoFormat(
                sourceMediaSize: image.size
            )
            let frame = try image.makeVideoFrame(
                width: resolvedFormat.width,
                height: resolvedFormat.height
            )
            let localTrack = RealtimeVideoTrack(
                id: Self.localVideoTrackID,
                videoFormat: resolvedFormat
            )
            track = localTrack

            try rtcManager.useExternalVideoSource()
            await MainActor.run {
                VideoRenderRegistry.register(
                    localTrack,
                    binding: VideoRenderBinding(imageFrame: frame)
                )
            }

            try emitFrame(frame)
            let task = startFrameOutput(
                frame: frame,
                frameRate: resolvedFormat.fps
            )
            stateLock.withLock {
                activeTrack = localTrack
                outputTask = task
            }

            return RealtimeMediaStream(
                id: StreamID.local.rawValue,
                videoTrack: localTrack
            )
        } catch {
            if let track {
                await MainActor.run {
                    VideoRenderRegistry.unregister(track)
                }
            }

            throw XmaxError.from(error)
        }
    }

    /// Decodes an image source.
    ///
    /// - Parameter input: The image data, decoded image, or file.
    ///
    /// - Returns: The decoded image.
    ///
    /// - Throws: An error if the URL or data is invalid or reading or decoding fails.
    func decode(
        _ input: ImageInput
    ) throws -> any DecodedImage {
        let data: Data

        switch input {
        case .decoded(let image):
            return image
        case .data(let imageData):
            data = imageData
        case .file(let fileURL):
            guard fileURL.isFileURL, !fileURL.path.isEmpty else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Local image file URL must reference a file"
                )
            }

            data = try Data(
                contentsOf: fileURL,
                options: .mappedIfSafe
            )
        }

        guard !data.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image source data must not be empty"
            )
        }

        return try imageManager.decode(data)
    }

    /// Resolves image media dimensions within the model's area limit.
    ///
    /// - Parameter sourceMediaSize: The original image dimensions.
    ///
    /// - Returns: The image video format using the model's default frame rate.
    ///
    /// - Throws: An error if image dimensions or output format are invalid.
    func resolveVideoFormat(
        sourceMediaSize: CGSize
    ) throws -> RealtimeVideoFormat {
        let resolvedMediaSize = try mediaService.resolveMediaSize(
            sourceMediaSize,
            source: .image
        )
        let resolvedFormat = RealtimeVideoFormat(
            width: Int(resolvedMediaSize.width),
            height: Int(resolvedMediaSize.height),
            fps: mediaService.model.defaultFrameRate
        )
        try resolvedFormat.validate()
        return resolvedFormat
    }

    /// Repeats image pixels at the requested frame rate.
    ///
    /// - Parameters:
    ///   - frame: The image frame with reusable pixels.
    ///   - frameRate: The output frames per second.
    ///
    /// - Returns: The cancellable frame delivery task.
    func startFrameOutput(
        frame: VideoFrame,
        frameRate: Int
    ) -> Task<Void, Never> {
        let interval = max(
            UInt64(1000000000 / frameRate),
            1
        )

        return Task.detached { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }

                guard !Task.isCancelled, let self else {
                    return
                }

                do {
                    try self.emitFrame(frame)
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    XmaxLogger.media.error(
                        message:
                            "图片帧推送失败 (Image Frame Push Failed)\n└─ \(XmaxLogger.localized("原因：", "Reason: "))\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    /// Delivers an image frame with the current host timestamp.
    ///
    /// - Parameter frame: The image pixels and format.
    ///
    /// - Throws: An error if frame preparation or delivery fails.
    func emitFrame(
        _ frame: VideoFrame
    ) throws {
        let timestampUs = Int64(
            min(
                DispatchTime.now().uptimeNanoseconds / 1000,
                UInt64(Int64.max)
            )
        )
        try frameListener(try frame.updating(timestampUs: timestampUs))
    }
}
