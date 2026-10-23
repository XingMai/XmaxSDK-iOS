//
//  XmaxStorageManaging.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// An interface for uploading and downloading media files.
public protocol XmaxStorageManaging: Sendable {

    /// Uploads encoded image data.
    ///
    /// - Parameters:
    ///   - data: The encoded image file data.
    ///   - fileName: The filename, including its extension.
    ///   - contentType: The file's MIME type, such as `image/jpeg`.
    ///   - progress: The transfer progress handler, or `nil` to omit progress notifications.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, or the upload fails.
    func uploadImage(
        _ data: Data,
        fileName: String,
        contentType: String,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// Uploads a local image file.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of a readable local image file.
    ///   - contentType: The file's MIME type, or `nil` to infer it from the filename.
    ///   - progress: The transfer progress handler, or `nil` to omit progress notifications.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, or the upload fails.
    func uploadImage(
        at fileURL: URL,
        contentType: String?,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// Uploads encoded image data and checks its content before returning.
    ///
    /// - Parameters:
    ///   - data: The encoded image file data.
    ///   - fileName: The filename, including its extension.
    ///   - contentType: The file's MIME type, such as `image/jpeg`.
    ///   - progress: The transfer progress handler, or `nil` to omit progress notifications.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, the upload, or the content
    ///   safety check fails.
    func uploadImageWithSafetyCheck(
        _ data: Data,
        fileName: String,
        contentType: String,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// Uploads a local image file and checks its content before returning.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of a readable local image file.
    ///   - contentType: The file's MIME type, or `nil` to infer it from the filename.
    ///   - progress: The transfer progress handler, or `nil` to omit progress notifications.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, the upload, or the content
    ///   safety check fails.
    func uploadImageWithSafetyCheck(
        at fileURL: URL,
        contentType: String?,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// Uploads encoded video data.
    ///
    /// - Parameters:
    ///   - data: The encoded video file data.
    ///   - fileName: The filename, including its extension.
    ///   - contentType: The file's MIME type, such as `video/mp4`.
    ///   - progress: The transfer progress handler, or `nil` to omit progress notifications.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, or the upload fails.
    func uploadVideo(
        _ data: Data,
        fileName: String,
        contentType: String,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// Uploads a local video file.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of a readable local video file.
    ///   - contentType: The file's MIME type, or `nil` to infer it from the filename.
    ///   - progress: The transfer progress handler, or `nil` to omit progress notifications.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, or the upload fails.
    func uploadVideo(
        at fileURL: URL,
        contentType: String?,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxUploadedFile

    /// Downloads an image to the specified local file.
    ///
    /// - Parameters:
    ///   - remoteURL: The URL of the remote image.
    ///   - destinationURL: The local URL at which to save the downloaded file.
    ///   - progress: The transfer progress handler, or `nil` to omit progress notifications.
    ///
    /// - Returns: The local file URL and the number of bytes downloaded.
    ///
    /// - Throws: An error if a URL is invalid, the file cannot be written, or the download fails.
    func downloadImage(
        from remoteURL: URL,
        to destinationURL: URL,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxDownloadedFile

    /// Downloads a video to the specified local file.
    ///
    /// - Parameters:
    ///   - remoteURL: The URL of the remote video.
    ///   - destinationURL: The local URL at which to save the downloaded file.
    ///   - progress: The transfer progress handler, or `nil` to omit progress notifications.
    ///
    /// - Returns: The local file URL and the number of bytes downloaded.
    ///
    /// - Throws: An error if a URL is invalid, the file cannot be written, or the download fails.
    func downloadVideo(
        from remoteURL: URL,
        to destinationURL: URL,
        progress: XmaxStorageProgressHandler?
    ) async throws -> XmaxDownloadedFile
}

public extension XmaxStorageManaging {

    /// Uploads encoded image data.
    ///
    /// - Parameters:
    ///   - data: The encoded image file data.
    ///   - fileName: The filename, including its extension.
    ///   - contentType: The file's MIME type, such as `image/jpeg`.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, or the upload fails.
    func uploadImage(
        _ data: Data,
        fileName: String,
        contentType: String
    ) async throws -> XmaxUploadedFile {
        try await uploadImage(
            data,
            fileName: fileName,
            contentType: contentType,
            progress: nil
        )
    }

    /// Uploads a local image file.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of a readable local image file.
    ///   - contentType: The file's MIME type, or `nil` to infer it from the filename.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, or the upload fails.
    func uploadImage(
        at fileURL: URL,
        contentType: String? = nil
    ) async throws -> XmaxUploadedFile {
        try await uploadImage(
            at: fileURL,
            contentType: contentType,
            progress: nil
        )
    }

    /// Uploads encoded image data and checks its content before returning.
    ///
    /// - Parameters:
    ///   - data: The encoded image file data.
    ///   - fileName: The filename, including its extension.
    ///   - contentType: The file's MIME type, such as `image/jpeg`.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, the upload, or the content
    ///   safety check fails.
    func uploadImageWithSafetyCheck(
        _ data: Data,
        fileName: String,
        contentType: String
    ) async throws -> XmaxUploadedFile {
        try await uploadImageWithSafetyCheck(
            data,
            fileName: fileName,
            contentType: contentType,
            progress: nil
        )
    }

    /// Uploads a local image file and checks its content before returning.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of a readable local image file.
    ///   - contentType: The file's MIME type, or `nil` to infer it from the filename.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, the upload, or the content
    ///   safety check fails.
    func uploadImageWithSafetyCheck(
        at fileURL: URL,
        contentType: String? = nil
    ) async throws -> XmaxUploadedFile {
        try await uploadImageWithSafetyCheck(
            at: fileURL,
            contentType: contentType,
            progress: nil
        )
    }

    /// Uploads encoded video data.
    ///
    /// - Parameters:
    ///   - data: The encoded video file data.
    ///   - fileName: The filename, including its extension.
    ///   - contentType: The file's MIME type, such as `video/mp4`.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, or the upload fails.
    func uploadVideo(
        _ data: Data,
        fileName: String,
        contentType: String
    ) async throws -> XmaxUploadedFile {
        try await uploadVideo(
            data,
            fileName: fileName,
            contentType: contentType,
            progress: nil
        )
    }

    /// Uploads a local video file.
    ///
    /// - Parameters:
    ///   - fileURL: The URL of a readable local video file.
    ///   - contentType: The file's MIME type, or `nil` to infer it from the filename.
    ///
    /// - Returns: The remote file URL, object key, and entity tag, if available.
    ///
    /// - Throws: An error if input validation, credential retrieval, or the upload fails.
    func uploadVideo(
        at fileURL: URL,
        contentType: String? = nil
    ) async throws -> XmaxUploadedFile {
        try await uploadVideo(
            at: fileURL,
            contentType: contentType,
            progress: nil
        )
    }

    /// Downloads an image to a local file.
    ///
    /// - Parameters:
    ///   - remoteURL: The URL of the remote image.
    ///   - destinationURL: The local URL at which to save the downloaded file.
    ///
    /// - Returns: The local file URL and the number of bytes downloaded.
    ///
    /// - Throws: An error if a URL is invalid, the file cannot be written, or the download fails.
    func downloadImage(
        from remoteURL: URL,
        to destinationURL: URL
    ) async throws -> XmaxDownloadedFile {
        try await downloadImage(
            from: remoteURL,
            to: destinationURL,
            progress: nil
        )
    }

    /// Downloads a video to a local file.
    ///
    /// - Parameters:
    ///   - remoteURL: The URL of the remote video.
    ///   - destinationURL: The local URL at which to save the downloaded file.
    ///
    /// - Returns: The local file URL and the number of bytes downloaded.
    ///
    /// - Throws: An error if a URL is invalid, the file cannot be written, or the download fails.
    func downloadVideo(
        from remoteURL: URL,
        to destinationURL: URL
    ) async throws -> XmaxDownloadedFile {
        try await downloadVideo(
            from: remoteURL,
            to: destinationURL,
            progress: nil
        )
    }
}
