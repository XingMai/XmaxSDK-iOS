//
//  VideoFrame.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A video frame with owned pixel data and timing information.
struct VideoFrame: Equatable, Sendable {

    /// The buffer reuse identifier used to cache converted pixels.
    let bufferReuseID: UUID?

    /// The frame dimensions and pixel format.
    let format: VideoFormat

    /// The timestamp on the shared media timeline, in microseconds.
    let timestampUs: Int64

    /// The rotation needed for display.
    let rotation: VideoRotation

    /// The image's pixel planes.
    let planes: [VideoFramePlane]

    /// Creates a video frame.
    ///
    /// - Parameters:
    ///   - format: The video dimensions and pixel format.
    ///   - timestampUs: The nonnegative frame timestamp, in microseconds.
    ///   - planes: The pixel planes, with at least one element.
    ///   - rotation: The rotation applied for display.
    ///   - bufferReuseID: The buffer reuse identifier, or `nil` to disable conversion caching.
    ///
    /// - Throws: A configuration error if the timestamp is negative or pixel planes are empty.
    init(
        format: VideoFormat,
        timestampUs: Int64,
        planes: [VideoFramePlane],
        rotation: VideoRotation = .rotation0,
        bufferReuseID: UUID? = nil
    ) throws {
        guard timestampUs >= 0 else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame timestamp must be non-negative"
            )
        }
        guard !planes.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Video frame must contain at least one plane"
            )
        }

        self.bufferReuseID = bufferReuseID
        self.format = format
        self.timestampUs = timestampUs
        self.rotation = rotation
        self.planes = planes
    }

    /// Creates a frame sharing the original pixels with updated timing or rotation.
    ///
    /// - Parameters:
    ///   - timestampUs: The new timestamp, in microseconds.
    ///   - rotation: The new rotation, or `nil` to preserve the original.
    ///
    /// - Returns: A frame sharing the original pixel planes and reuse identifier.
    ///
    /// - Throws: A configuration error if the new timestamp is invalid.
    func updating(
        timestampUs: Int64,
        rotation: VideoRotation? = nil
    ) throws -> VideoFrame {
        try VideoFrame(
            format: format,
            timestampUs: timestampUs,
            planes: planes,
            rotation: rotation ?? self.rotation,
            bufferReuseID: bufferReuseID
        )
    }
}
