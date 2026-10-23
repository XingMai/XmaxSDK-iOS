//
//  StorageServicing.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An interface for image and video transfers and image safety.
protocol StorageServicing: Sendable {

    /// Uploads encoded image data.
    ///
    /// - Parameters:
    ///   - data: The encoded image file data.
    ///   - fileName: The filename, including its extension.
    ///   - contentType: The file's MIME type.
    ///   - progress: The byte progress handler, or `nil` to omit notifications.
    ///
    /// - Returns: The uploaded URL, object key, and available ETag.
    ///
    /// - Throws: An error if input validation, credential retrieval, or uploading fails.
    func uploadImage(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// Uploads a local image file.
    ///
    /// - Parameters:
    ///   - fileURL: The readable local image URL.
    ///   - contentType: The MIME type, or `nil` to infer it from the filename.
    ///   - progress: The byte progress handler, or `nil` to omit notifications.
    ///
    /// - Returns: The uploaded URL, object key, and available ETag.
    ///
    /// - Throws: An error if the file is invalid, credentials are unavailable, or uploading fails.
    func uploadImageFile(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// Uploads image data and verifies content safety.
    ///
    /// - Parameters:
    ///   - data: The encoded image file data.
    ///   - fileName: The filename, including its extension.
    ///   - contentType: The file's MIME type.
    ///   - progress: The byte progress handler, or `nil` to omit notifications.
    ///
    /// - Returns: The uploaded URL, object key, and available ETag.
    ///
    /// - Throws: An error if input validation, credentials, uploading, or safety verification
    ///   fails.
    func uploadImageWithSafetyCheck(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// Uploads a local image and verifies content safety.
    ///
    /// - Parameters:
    ///   - fileURL: The readable local image URL.
    ///   - contentType: The MIME type, or `nil` to infer it from the filename.
    ///   - progress: The byte progress handler, or `nil` to omit notifications.
    ///
    /// - Returns: The uploaded URL, object key, and available ETag.
    ///
    /// - Throws: An error if the file is invalid, credentials are unavailable, or uploading or
    ///   safety verification fails.
    func uploadImageFileWithSafetyCheck(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// Uploads encoded video data.
    ///
    /// - Parameters:
    ///   - data: The encoded video file data.
    ///   - fileName: The filename, including its extension.
    ///   - contentType: The file's MIME type.
    ///   - progress: The byte progress handler, or `nil` to omit notifications.
    ///
    /// - Returns: The uploaded URL, object key, and available ETag.
    ///
    /// - Throws: An error if input validation, credential retrieval, or uploading fails.
    func uploadVideo(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// Uploads a local video file.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of a readable local video file.
    ///   - contentType: The MIME type, or `nil` to infer it from the filename.
    ///   - progress: The byte progress handler, or `nil` to omit notifications.
    ///
    /// - Returns: The uploaded URL, object key, and available ETag.
    ///
    /// - Throws: An error if the file is invalid, credentials are unavailable, or uploading fails.
    func uploadVideoFile(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile

    /// Downloads a remote image to a local file.
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
    func downloadImage(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile

    /// Downloads a remote video to a local file.
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
    func downloadVideo(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile
}
