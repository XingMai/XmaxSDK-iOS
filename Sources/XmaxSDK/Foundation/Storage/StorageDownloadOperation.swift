//
//  StorageDownloadOperation.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// A file-backed download with task-specific progress notifications.
final class StorageDownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    /// The transfer progress handler.
    private let progress: StorageProgressListener?

    /// The lock protecting the pending download continuation.
    private let lock = NSLock()

    /// The pending result, accessed only while holding the lock.
    private var continuation: CheckedContinuation<(URL, URLResponse), any Error>?

    /// Creates a download operation.
    init(
        progress: StorageProgressListener?
    ) {
        self.progress = progress
    }

    /// Downloads a file and commits it after a successful HTTP response.
    ///
    /// - Parameters:
    ///   - session: The session performing the download.
    ///   - remoteURL: The HTTP or HTTPS source URL.
    ///   - destinationURL: The local destination, replaced only after downloading succeeds.
    ///
    /// - Returns: The completed file URL and its on-disk byte count.
    ///
    /// - Throws: An error if the HTTP response, transfer, or file commit fails, or the task is
    ///   cancelled. Temporary files are removed on failure.
    func value(
        session: URLSession,
        remoteURL: URL,
        destinationURL: URL
    ) async throws -> DownloadedFile {
        try Task.checkCancellation()
        let (temporaryURL, response) = try await download(
            session: session,
            remoteURL: remoteURL
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            throw XmaxError(
                code: .downloadError,
                message: statusCode.map {
                    "Storage download failed with HTTP \($0)"
                } ?? "Storage download returned a non-HTTP response",
                httpStatus: statusCode
            )
        }

        guard let size = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw XmaxError(
                code: .downloadError,
                message: "Storage download file size is unavailable"
            )
        }
        try commitFile(
            at: temporaryURL,
            to: destinationURL
        )

        let byteCount = Int64(size)
        progress?(
            byteCount,
            byteCount
        )
        return DownloadedFile(
            fileURL: destinationURL,
            byteCount: byteCount
        )
    }

    /// Reports bytes written for a successful HTTP response; zero total bytes indicates unknown
    /// content length until completion.
    ///
    /// - Parameters:
    ///   - session: The session performing the transfer.
    ///   - downloadTask: The task whose progress changed.
    ///   - bytesWritten: The bytes written since the previous notification.
    ///   - totalBytesWritten: The accumulated downloaded byte count.
    ///   - totalBytesExpectedToWrite: The expected byte count, or the system's unknown-size value.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode)
        else {
            return
        }
        progress?(
            totalBytesWritten,
            max(0, totalBytesExpectedToWrite)
        )
    }

    /// Preserves the completed file until the awaiting operation can validate and commit it.
    ///
    /// - Parameters:
    ///   - session: The session performing the transfer.
    ///   - downloadTask: The completed download task.
    ///   - location: The temporary file, valid only during this callback.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let continuation = takeContinuation() else {
            return
        }

        do {
            guard let response = downloadTask.response else {
                throw XmaxError(
                    code: .downloadError,
                    message: "Storage download returned no response"
                )
            }

            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(
                at: location,
                to: temporaryURL
            )
            continuation.resume(returning: (temporaryURL, response))
        } catch {
            continuation.resume(throwing: error)
        }
    }

    /// Completes a transfer that failed or was cancelled.
    ///
    /// - Parameters:
    ///   - session: The session performing the transfer.
    ///   - task: The completed task.
    ///   - error: The transfer error, or `nil` after a successful download.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error else {
            return
        }
        takeContinuation()?.resume(throwing: error)
    }
}

private extension StorageDownloadOperation {

    /// Starts a delegate-backed download and forwards cancellation to its task.
    ///
    /// - Parameters:
    ///   - session: The session performing the transfer.
    ///   - remoteURL: The HTTP or HTTPS source URL.
    ///
    /// - Returns: The owned temporary file and its response.
    ///
    /// - Throws: The transfer error, or a cancellation error.
    func download(
        session: URLSession,
        remoteURL: URL
    ) async throws -> (URL, URLResponse) {
        let task = session.downloadTask(with: remoteURL)
        task.delegate = self

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = lock.withLock {
                    guard !Task.isCancelled else {
                        return true
                    }
                    self.continuation = continuation
                    task.resume()
                    return false
                }
                if cancelled {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// Removes the pending result so only one completion callback can resume it.
    ///
    /// - Returns: The pending continuation, or `nil` if it has already completed.
    func takeContinuation() -> CheckedContinuation<(URL, URLResponse), any Error>? {
        lock.withLock {
            defer {
                continuation = nil
            }
            return continuation
        }
    }

    /// Moves a completed download into place without exposing a partial destination file.
    ///
    /// - Parameters:
    ///   - temporaryURL: The completed temporary file.
    ///   - destinationURL: The local destination, which must not be a directory.
    ///
    /// - Throws: An error if staging or replacement fails, or cancellation precedes the commit.
    func commitFile(
        at temporaryURL: URL,
        to destinationURL: URL
    ) throws {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        let destinationExists = fileManager.fileExists(
            atPath: destinationURL.path,
            isDirectory: &isDirectory
        )
        guard !isDirectory.boolValue else {
            throw XmaxError(
                code: .downloadError,
                message: "Storage download destination must not be a directory"
            )
        }

        let stagingDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destinationURL,
            create: true
        )
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }

        let stagedURL = stagingDirectory.appendingPathComponent("download")
        try fileManager.moveItem(
            at: temporaryURL,
            to: stagedURL
        )
        try Task.checkCancellation()

        if destinationExists {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: stagedURL
            )
        } else {
            try fileManager.moveItem(
                at: stagedURL,
                to: destinationURL
            )
        }
    }
}
