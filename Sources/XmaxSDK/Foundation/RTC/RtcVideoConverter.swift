//
//  RtcVideoConverter.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import CoreMedia
import Foundation
@preconcurrency import AgoraRtcKit

/// An Agora external video frame with owned contiguous pixels.
final class RtcVideoFrame {

    /// The external frame ready for Agora.
    let value: AgoraVideoFrame

    /// Validates pixel planes and creates an Agora external frame.
    ///
    /// - Parameter frame: The source pixels, dimensions, and timestamp.
    ///
    /// - Throws: An error if dimensions, plane count, or pixel layout are invalid.
    init(
        frame: VideoFrame
    ) throws {
        let width = frame.format.width
        let height = frame.format.height
        guard let rtcWidth = Int32(exactly: width),
            let rtcHeight = Int32(exactly: height)
        else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame dimensions exceed the RTC range"
            )
        }

        let layout: [(bytes: Int, rows: Int)]
        switch frame.format.pixelFormat {
        case .i420:
            layout = [
                (width, height), ((width + 1) / 2, (height + 1) / 2),
                ((width + 1) / 2, (height + 1) / 2)
            ]
        case .nv12, .nv21:
            layout = [(width, height), (((width + 1) / 2) * 2, (height + 1) / 2)]
        case .rgba, .bgra, .argb:
            layout = [(width * 4, height)]
        }
        guard frame.planes.count == layout.count else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame requires \(layout.count) data planes"
            )
        }

        var data = Data()
        for (plane, size) in zip(
            frame.planes,
            layout
        ) {
            guard plane.stride >= size.bytes,
                size.rows > 0,
                plane.byteLength >= size.bytes,
                size.rows - 1 <= (plane.byteLength - size.bytes) / plane.stride
            else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "Video frame plane is smaller than its dimensions"
                )
            }
            plane.data.withUnsafeBytes { bytes in
                for row in 0..<size.rows {
                    let start = bytes.baseAddress!.advanced(
                        by: plane.byteOffset + row * plane.stride
                    )
                    data.append(
                        start.assumingMemoryBound(to: UInt8.self),
                        count: size.bytes
                    )
                }
            }
        }

        value = AgoraVideoFrame()
        value.format = RtcVideoConverter.convertPixelFormat(frame.format.pixelFormat)
        value.strideInPixels = rtcWidth
        value.height = rtcHeight
        value.dataBuf = data
        updateMetadata(from: frame)
    }

    /// Updates timestamp and rotation while retaining pixels.
    ///
    /// - Parameter frame: The frame providing updated timing and rotation.
    func updateMetadata(
        from frame: VideoFrame
    ) {
        value.time = CMTime(
            value: frame.timestampUs,
            timescale: 1000000
        )
        value.rotation = Int32(frame.rotation.rawValue)
    }
}

/// Reuses RTC pixels for explicitly unchanged video buffers.
final class RtcVideoFrameCache {

    /// The last reusable buffer and its Agora representation.
    private var cachedFrame: (id: UUID, frame: RtcVideoFrame)?

    /// Returns an RTC frame, caching pixels by reuse identifier.
    ///
    /// - Parameter frame: The source video frame.
    ///
    /// - Returns: The RTC frame with prepared pixels.
    ///
    /// - Throws: An error if dimensions or pixel layout are invalid.
    func frame(
        for frame: VideoFrame
    ) throws -> RtcVideoFrame {
        if let id = frame.bufferReuseID, let cachedFrame, cachedFrame.id == id {
            cachedFrame.frame.updateMetadata(from: frame)
            return cachedFrame.frame
        }

        let converted = try RtcVideoConverter.convertFrame(frame)
        cachedFrame = frame.bufferReuseID.map {
            ($0, converted)
        }
        return converted
    }

    /// Clears the cached RTC frame and pixels.
    func removeAll() {
        cachedFrame = nil
    }
}

/// Converts between SDK and Agora video types.
enum RtcVideoConverter {

    /// Converts an SDK frame to an Agora external frame.
    ///
    /// - Parameter frame: The SDK video frame to convert.
    ///
    /// - Returns: An RTC frame owning contiguous pixels.
    ///
    /// - Throws: An error if dimensions or pixel layout are invalid.
    static func convertFrame(
        _ frame: VideoFrame
    ) throws -> RtcVideoFrame {
        try RtcVideoFrame(frame: frame)
    }

    /// Converts SDK encoding settings to an Agora configuration.
    ///
    /// - Parameter configuration: The dimensions, frame rate, bitrate bounds, and encoding
    ///   preference.
    ///
    /// - Returns: An adaptive-orientation encoder configuration with mirroring initially disabled.
    static func makeEncoderConfiguration(
        _ configuration: VideoEncodingConfiguration
    ) -> AgoraVideoEncoderConfiguration {
        let result = AgoraVideoEncoderConfiguration(
            size: CGSize(
                width: configuration.width,
                height: configuration.height
            ),
            frameRate: configuration.frameRate,
            bitrate: max(
                0,
                configuration.maximumBitrate
            ),
            orientationMode: .adaptative,
            mirrorMode: .disabled
        )
        result.minBitrate = configuration.minimumBitrate
        result.degradationPreference =
            switch configuration.encoderPreference {
            case .auto:
                .maintainAuto
            case .maintainFramerate:
                .maintainFramerate
            case .maintainQuality:
                .maintainQuality
            }
        return result
    }

    /// Maps SDK pixel formats to Agora external frame formats.
    ///
    /// - Parameter format: The SDK pixel format.
    ///
    /// - Returns: The corresponding Agora pixel format identifier.
    static func convertPixelFormat(
        _ format: VideoPixelFormat
    ) -> Int {
        switch format {
        case .i420:
            1
        case .bgra:
            2
        case .nv21:
            3
        case .rgba:
            4
        case .argb:
            7
        case .nv12:
            8
        }
    }
}
