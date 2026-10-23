//
//  StorageManaging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An interface for file uploads and downloads.
protocol StorageManaging: Sendable {

    /// Uploads data or a local file using temporary credentials.
    ///
    /// - Parameters:
    ///   - source: The data or local file to upload.
    ///   - objectKey: The destination object key.
    ///   - contentType: The upload MIME type.
    ///   - configuration: The endpoint, bucket, and temporary credentials.
    ///   - progress: The byte progress handler, or `nil` to omit notifications.
    ///
    /// - Returns: The uploaded URL, object key, and available ETag.
    ///
    /// - Throws: An error if input or credentials are invalid, uploading fails, or the task is
    ///   cancelled.
    func upload(
        source: StorageUploadSource,
        objectKey: String,
        contentType: String,
        configuration: StorageConfiguration,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// Downloads a file to the specified local location.
    ///
    /// - Parameters:
    ///   - remoteURL: The remote file URL.
    ///   - destinationURL: The destination local file URL.
    ///   - progress: The byte progress handler, or `nil` to omit notifications.
    ///
    /// - Returns: The completed local URL and byte count.
    ///
    /// - Throws: An error if a URL is invalid, downloading or writing fails, or the task is
    ///   cancelled.
    func download(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile
}

extension StorageManaging {

    /// Uploads data or a local file.
    ///
    /// - Parameters:
    ///   - source: The data or local file to upload.
    ///   - objectKey: The destination object key.
    ///   - contentType: The upload MIME type.
    ///   - configuration: The endpoint, bucket, and temporary credentials.
    ///
    /// - Returns: The uploaded URL, object key, and available ETag.
    ///
    /// - Throws: An error if input or credentials are invalid, uploading fails, or the task is
    ///   cancelled.
    func upload(
        source: StorageUploadSource,
        objectKey: String,
        contentType: String,
        configuration: StorageConfiguration
    ) async throws -> StoredFile {
        try await upload(
            source: source,
            objectKey: objectKey,
            contentType: contentType,
            configuration: configuration,
            progress: nil
        )
    }

    /// Downloads a remote file.
    ///
    /// - Parameters:
    ///   - remoteURL: The remote file URL.
    ///   - destinationURL: The destination local file URL.
    ///
    /// - Returns: The completed local URL and byte count.
    ///
    /// - Throws: An error if a URL is invalid, downloading or writing fails, or the task is
    ///   cancelled.
    func download(
        remoteURL: URL,
        destinationURL: URL
    ) async throws -> DownloadedFile {
        try await download(
            remoteURL: remoteURL,
            destinationURL: destinationURL,
            progress: nil
        )
    }
}
