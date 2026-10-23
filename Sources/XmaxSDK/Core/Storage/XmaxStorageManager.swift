//
//  XmaxStorageManager.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// Provides public file transfer operations backed by the storage service.
final class XmaxStorageManager: XmaxStorageManaging, Sendable {

    /// The service that uploads, downloads, and checks media.
    private let storageService: any StorageServicing

    /// Creates a file manager with the specified storage service.
    init(
        storageService: any StorageServicing
    ) {
        self.storageService = storageService
    }

    /// Creates a file manager backed by the default object storage implementation.
    ///
    /// - Parameter apiService: The API service that supplies storage credentials and media safety
    ///   checks.
    convenience init(
        apiService: any ApiServicing
    ) {
        self.init(
            storageService: StorageService(
                apiService: apiService,
                storageManager: StorageManager()
            )
        )
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadImage(
                data: data,
                fileName: fileName,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadImageFile(
                fileURL: fileURL,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadImageWithSafetyCheck(
                data: data,
                fileName: fileName,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadImageFileWithSafetyCheck(
                fileURL: fileURL,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadVideo(
                data: data,
                fileName: fileName,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxUploadedFile {
        try await uploadedFile {
            try await storageService.uploadVideoFile(
                fileURL: fileURL,
                contentType: contentType,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxDownloadedFile {
        try await downloadedFile {
            try await storageService.downloadImage(
                remoteURL: remoteURL,
                destinationURL: destinationURL,
                progress: progressListener(progress)
            )
        }
    }

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
    ) async throws -> XmaxDownloadedFile {
        try await downloadedFile {
            try await storageService.downloadVideo(
                remoteURL: remoteURL,
                destinationURL: destinationURL,
                progress: progressListener(progress)
            )
        }
    }
}

private extension XmaxStorageManager {

    /// Adapts byte counts to public file transfer progress notifications.
    ///
    /// - Parameter handler: The progress handler, or `nil` to omit notifications.
    ///
    /// - Returns: A byte progress listener, or `nil` if no handler was supplied.
    func progressListener(
        _ handler: XmaxStorageProgressHandler?
    ) -> StorageProgressListener? {
        guard let handler else {
            return nil
        }
        return { completedBytes, totalBytes in
            let progress = Progress(totalUnitCount: totalBytes)
            progress.completedUnitCount = completedBytes
            handler(progress)
        }
    }

    /// Uploads a file and returns its metadata.
    ///
    /// - Parameter operation: The asynchronous upload returning a service-level result.
    ///
    /// - Returns: The uploaded file metadata.
    ///
    /// - Throws: The upload error converted to an `XmaxError`.
    func uploadedFile(
        _ operation: () async throws -> StoredFile
    ) async throws -> XmaxUploadedFile {
        do {
            let file = try await operation()
            return XmaxUploadedFile(
                url: file.url,
                objectKey: file.objectKey,
                etag: file.etag
            )
        } catch {
            throw XmaxError.from(error)
        }
    }

    /// Downloads a file and returns its metadata.
    ///
    /// - Parameter operation: The asynchronous download returning a service-level result.
    ///
    /// - Returns: The downloaded file metadata.
    ///
    /// - Throws: The download error converted to an `XmaxError`.
    func downloadedFile(
        _ operation: () async throws -> DownloadedFile
    ) async throws -> XmaxDownloadedFile {
        do {
            let file = try await operation()
            return XmaxDownloadedFile(
                fileURL: file.fileURL,
                byteCount: file.byteCount
            )
        } catch {
            throw XmaxError.from(error)
        }
    }
}
