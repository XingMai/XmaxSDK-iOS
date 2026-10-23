//
//  ImageControlling.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An interface for image streams, frames, and preview.
protocol ImageControlling: Sendable {

    /// The image video track, or `nil` before creation or after stopping.
    var currentTrack: RealtimeVideoTrack? {
        get
    }

    /// Creates a stream of repeated frames from a decoded image.
    ///
    /// - Parameters:
    ///   - decodedImage: The orientation-corrected decoded image.
    ///
    /// - Returns: The local image video stream.
    ///
    /// - Throws: An error if a stream exists, the format is invalid, or image processing or frame
    ///   startup fails.
    func createLocalImageStream(
        decodedImage: any DecodedImage
    ) async throws -> RealtimeMediaStream

    /// Creates a stream of repeated frames from encoded image data.
    ///
    /// - Parameters:
    ///   - imageData: The nonempty encoded image data.
    ///
    /// - Returns: The local image video stream.
    ///
    /// - Throws: An error if a stream exists or data, format, decoding, or frame startup fails.
    func createLocalImageStream(
        imageData: Data
    ) async throws -> RealtimeMediaStream

    /// Creates a stream of repeated frames from a local image file.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of a readable local image file.
    ///
    /// - Returns: The local image video stream.
    ///
    /// - Throws: An error if a stream exists or file reading, validation, decoding, or startup
    ///   fails.
    func createLocalImageStream(
        fileURL: URL
    ) async throws -> RealtimeMediaStream

    /// Stops image frame delivery and releases its track and preview binding.
    func stopLocalImageStream() async
}
