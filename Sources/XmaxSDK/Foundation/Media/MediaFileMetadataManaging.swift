//
//  MediaFileMetadataManaging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An interface for local media metadata.
protocol MediaFileMetadataManaging: Sendable {

    /// Reads video dimensions, orientation, duration, and audio availability.
    ///
    /// - Parameter fileURL: The URL of a readable local video file.
    ///
    /// - Returns: The metadata needed to prepare a local video stream.
    ///
    /// - Throws: An error if the file is unreadable, lacks video, or has invalid metadata.
    func readMetadata(
        fileURL: URL
    ) async throws -> MediaFileMetadata
}
