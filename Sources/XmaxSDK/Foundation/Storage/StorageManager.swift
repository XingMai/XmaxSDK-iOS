//
//  StorageManager.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation
@preconcurrency import QCloudCOSXML

/// A COS upload and HTTP file download manager.
final class StorageManager: StorageManaging, Sendable {

    /// The URL session for downloads.
    private let session: URLSession

    /// Creates a storage manager.
    init(
        session: URLSession = .shared
    ) {
        self.session = session
    }

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
        progress: StorageProgressListener? = nil
    ) async throws -> StoredFile {
        try Self.validateUpload(
            source: source,
            objectKey: objectKey,
            contentType: contentType,
            configuration: configuration
        )

        do {
            let service = try Self.makeStorageService(configuration: configuration)
            let request = try Self.makeUploadRequest(
                source: source,
                objectKey: objectKey,
                contentType: contentType,
                configuration: configuration
            )
            let operation = StorageUploadOperation(
                service: service,
                request: request,
                objectKey: objectKey,
                configuration: configuration,
                progress: progress
            )

            return try await operation.value()
        } catch let error as XmaxError {
            throw error
        } catch {
            throw Self.uploadError(error)
        }
    }

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
        progress: StorageProgressListener? = nil
    ) async throws -> DownloadedFile {
        let remoteScheme = remoteURL.scheme?.lowercased()
        guard remoteScheme == "https" || remoteScheme == "http" else {
            throw XmaxError(
                code: .downloadError,
                message: "Storage download URL must use HTTP or HTTPS"
            )
        }
        guard destinationURL.isFileURL else {
            throw XmaxError(
                code: .downloadError,
                message: "Storage download destination must be a file URL"
            )
        }

        do {
            let operation = StorageDownloadOperation(progress: progress)
            return try await operation.value(
                session: session,
                remoteURL: remoteURL,
                destinationURL: destinationURL
            )
        } catch let error as XmaxError {
            throw error
        } catch is CancellationError {
            throw Self.cancelledError(operation: "Storage download")
        } catch {
            let platformError = error as NSError
            if platformError.domain == NSURLErrorDomain, platformError.code == NSURLErrorCancelled {
                throw Self.cancelledError(operation: "Storage download")
            }

            throw XmaxError(
                code: .downloadError,
                message: platformError.localizedDescription
            )
        }
    }

    /// Resolves an object's public URL from the upload response or storage configuration.
    ///
    /// - Parameters:
    ///   - candidate: The candidate URL from the upload response.
    ///   - configuration: The bucket, region, and endpoint configuration.
    ///   - objectKey: The uploaded object key.
    ///
    /// - Returns: An HTTP or HTTPS object URL.
    ///
    /// - Throws: An error if the endpoint is invalid or the object URL cannot be constructed.
    static func resolveObjectURL(
        candidate: String?,
        configuration: StorageConfiguration,
        objectKey: String
    ) throws -> URL {
        let location =
            candidate?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if location.hasPrefix("//"),
            let url = URL(string: "https:\(location)")
        {
            return url
        }
        if let url = URL(string: location) {
            let scheme = url.scheme?.lowercased()
            if scheme == "https" || scheme == "http" {
                return url
            }
        }

        let endpoint: String
        if configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            endpoint = "https://\(configuration.bucket).cos.\(configuration.region).myqcloud.com"
        } else {
            endpoint = try normalizedEndpoint(
                configuration.endpoint,
                bucket: configuration.bucket,
                preservePath: true
            ).absoluteString
        }

        let encodedObjectKey = try encodeObjectKey(objectKey)
        let baseURL = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseURL)/\(encodedObjectKey)") else {
            throw XmaxError(
                code: .uploadError,
                message: "Failed to build storage object URL"
            )
        }

        return url
    }

    /// Validates the upload source, object key, and credentials.
    ///
    /// - Parameters:
    ///   - source: The data or local file to upload.
    ///   - objectKey: The destination object key.
    ///   - contentType: The upload MIME type.
    ///   - configuration: The destination and temporary credentials.
    ///
    /// - Throws: An error if configuration is invalid or the source file is unavailable.
    private static func validateUpload(
        source: StorageUploadSource,
        objectKey: String,
        contentType: String,
        configuration: StorageConfiguration
    ) throws {
        let bucket = configuration.bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = configuration.region.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = objectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let mimeType = contentType.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = configuration.credential

        guard matchesIdentifier(bucket) else {
            throw uploadError(message: "Storage bucket is invalid")
        }
        guard matchesIdentifier(region) else {
            throw uploadError(message: "Storage region is invalid")
        }
        guard !key.isEmpty else {
            throw uploadError(message: "Storage object key is invalid")
        }
        guard !mimeType.isEmpty else {
            throw uploadError(message: "Storage content type cannot be empty")
        }
        guard !credential.accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !credential.secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !credential.sessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw uploadError(message: "Storage temporary credential is incomplete")
        }

        if case let .file(url) = source {
            var isDirectory = ObjCBool(false)
            guard url.isFileURL,
                FileManager.default.fileExists(
                    atPath: url.path,
                    isDirectory: &isDirectory
                ),
                !isDirectory.boolValue
            else {
                throw uploadError(message: "Storage upload file is unavailable")
            }
        }
    }

    /// Creates a COS service for an endpoint.
    ///
    /// - Parameter configuration: The storage region and endpoint.
    ///
    /// - Returns: The COS service for this upload.
    ///
    /// - Throws: An error if the endpoint is invalid or cannot be created.
    private static func makeStorageService(
        configuration: StorageConfiguration
    ) throws -> QCloudCOSXMLService {
        let serviceConfiguration = QCloudServiceConfiguration()
        let endpointValue = configuration.endpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if endpointValue.isEmpty {
            let endpoint = QCloudCOSXMLEndPoint()
            endpoint.regionName = configuration.region
            endpoint.useHTTPS = true
            serviceConfiguration.endpoint = endpoint
        } else {
            let url = try normalizedEndpoint(
                endpointValue,
                bucket: configuration.bucket,
                preservePath: false
            )
            guard let endpoint = QCloudEndPoint(literalURL: url) else {
                throw uploadError(message: "Storage endpoint is invalid")
            }
            endpoint.regionName = configuration.region
            endpoint.useHTTPS = url.scheme?.lowercased() == "https"
            serviceConfiguration.endpoint = endpoint
        }

        return QCloudCOSXMLService(
            configuration: serviceConfiguration
        )
    }

    /// Creates a COS upload request with temporary credentials.
    ///
    /// - Parameters:
    ///   - source: The data or local file to upload.
    ///   - objectKey: The destination object key.
    ///   - contentType: The upload MIME type.
    ///   - configuration: The destination and credentials.
    ///
    /// - Returns: The prepared object upload request.
    ///
    /// - Throws: An error if temporary credentials are invalid.
    private static func makeUploadRequest(
        source: StorageUploadSource,
        objectKey: String,
        contentType: String,
        configuration: StorageConfiguration
    ) throws -> QCloudPutObjectRequest<AnyObject> {
        let request = QCloudPutObjectRequest<AnyObject>()
        request.bucket = configuration.bucket
        request.object = objectKey
        request.contentType = contentType
        request.regionName = configuration.region
        request.credential = try makeCredential(configuration.credential)

        switch source {
        case let .data(data):
            request.body = data as NSData
        case let .file(url):
            request.body = url as NSURL
        }

        return request
    }

    /// Converts temporary credentials to COS signing credentials.
    ///
    /// - Parameter configuration: The temporary keys and session token.
    ///
    /// - Returns: The signing credentials for the upload.
    ///
    /// - Throws: An error if COS credential validation fails.
    private static func makeCredential(
        _ configuration: StorageCredential
    ) throws -> QCloudCredential {
        let credential = QCloudCredential()
        credential.secretID = configuration.accessKeyID
        credential.secretKey = configuration.secretAccessKey
        credential.token = configuration.sessionToken
        credential.startDate = Date(timeIntervalSinceNow: -60)
        credential.expirationDate = Date(timeIntervalSinceNow: 25 * 60)

        guard credential.valid else {
            throw uploadError(message: "Failed to create temporary storage credential")
        }

        return credential
    }

    /// Resolves the storage endpoint with a bucket prefix when needed.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint string.
    ///   - bucket: The destination bucket name.
    ///   - preservePath: Whether to preserve the endpoint path and additional URL components.
    ///
    /// - Returns: The resolved HTTP or HTTPS endpoint.
    ///
    /// - Throws: An error if the endpoint scheme, host, or URL is invalid.
    private static func normalizedEndpoint(
        _ endpoint: String,
        bucket: String,
        preservePath: Bool
    ) throws -> URL {
        let value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = value.contains("://") ? value : "https://\(value)"
        guard var components = URLComponents(string: normalized),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = components.host, !host.isEmpty
        else {
            throw uploadError(message: "Storage endpoint is invalid")
        }

        if host.lowercased().hasPrefix("cos.") {
            components.host = "\(bucket).\(host)"
        }
        if !preservePath {
            components.path = ""
            components.query = nil
            components.fragment = nil
        }

        guard let url = components.url else {
            throw uploadError(message: "Storage endpoint is invalid")
        }
        return url
    }

    /// URL-encodes object key path segments.
    ///
    /// - Parameter objectKey: The original object key.
    ///
    /// - Returns: The encoded object key retaining path separators.
    ///
    /// - Throws: An error if a path segment cannot be encoded.
    private static func encodeObjectKey(
        _ objectKey: String
    ) throws -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encodedParts =
            objectKey
            .split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            .map {
                String($0).addingPercentEncoding(withAllowedCharacters: allowed)
            }

        guard
            encodedParts.allSatisfy({
                $0 != nil
            })
        else {
            throw uploadError(message: "Storage object key cannot be URL encoded")
        }
        return encodedParts.compactMap {
            $0
        }.joined(separator: "/")
    }

    /// Validates a bucket or region identifier.
    ///
    /// - Parameter value: The identifier to validate.
    ///
    /// - Returns: `true` for a nonempty identifier containing only letters, digits, dots, and
    ///   hyphens.
    private static func matchesIdentifier(
        _ value: String
    ) -> Bool {
        !value.isEmpty
            && value.range(
                of: #"^[A-Za-z0-9.-]+$"#,
                options: .regularExpression
            ) != nil
    }

    /// Converts a platform failure to an upload error.
    ///
    /// - Parameter error: The underlying platform error.
    ///
    /// - Returns: An upload error retaining the localized description.
    private static func uploadError(
        _ error: any Error
    ) -> XmaxError {
        let platformError = error as NSError
        return uploadError(message: platformError.localizedDescription)
    }

    /// Creates an upload error.
    ///
    /// - Parameter message: The error description.
    ///
    /// - Returns: An upload error with the specified description.
    private static func uploadError(
        message: String
    ) -> XmaxError {
        XmaxError(
            code: .uploadError,
            message: message
        )
    }

    /// Creates a storage cancellation error.
    ///
    /// - Parameter operation: The cancelled operation's name.
    ///
    /// - Returns: A cancellation error naming the operation.
    private static func cancelledError(
        operation: String
    ) -> XmaxError {
        XmaxError(
            code: .cancelled,
            message: "\(operation) was cancelled"
        )
    }
}

/// An asynchronous COS upload completing its waiter exactly once.
private final class StorageUploadOperation: @unchecked Sendable {

    /// The COS service performing the request.
    private let service: QCloudCOSXMLService

    /// The upload request.
    private let request: QCloudPutObjectRequest<AnyObject>

    /// The uploaded object key.
    private let objectKey: String

    /// The destination and authentication configuration.
    private let configuration: StorageConfiguration

    /// The upload byte progress handler.
    private let progress: StorageProgressListener?

    /// The upload start time.
    private let startedAt = Date()

    /// The lock protecting completion and its waiter.
    private let lock = NSLock()

    /// The continuation awaiting upload completion.
    private var continuation: CheckedContinuation<StoredFile, Error>?

    /// The result retained until a waiter is registered.
    private var pendingResult: Result<StoredFile, Error>?

    /// Whether the upload request has started.
    private var started = false

    /// Whether the upload has completed.
    private var completed = false

    /// Creates an asynchronous COS upload.
    init(
        service: QCloudCOSXMLService,
        request: QCloudPutObjectRequest<AnyObject>,
        objectKey: String,
        configuration: StorageConfiguration,
        progress: StorageProgressListener?
    ) {
        self.service = service
        self.request = request
        self.objectKey = objectKey
        self.configuration = configuration
        self.progress = progress
    }

    /// Submits the upload and awaits its result.
    ///
    /// - Returns: The uploaded object information.
    ///
    /// - Throws: An error if uploading or result decoding fails, or the task is cancelled.
    func value() async throws -> StoredFile {
        configureCallbacks()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(continuation)
                startIfNeeded()
            }
        } onCancel: {
            self.cancel()
        }
    }

    /// Installs upload progress and completion handlers.
    private func configureCallbacks() {
        request.sendProcessBlock = { [progress] _, totalBytes, expectedBytes in
            progress?(
                totalBytes,
                max(
                    expectedBytes,
                    0
                )
            )
        }
        request.finishBlock = { [weak self] result, error in
            guard let self else {
                return
            }

            if let error {
                let platformError = error as NSError
                XmaxLogger.storage.error(
                    message: "上传失败 (Upload Failed)\n"
                        + "├─ \(XmaxLogger.localized("错误域：", "Error Domain: "))\(platformError.domain)\n"
                        + "├─ \(XmaxLogger.localized("错误码：", "Error Code: "))\(platformError.code)\n"
                        + "├─ \(XmaxLogger.localized("错误信息：", "Error Message: "))\(platformError.localizedDescription)\n"
                        + "└─ \(XmaxLogger.localized("耗时：", "Duration: "))\(formatDuration())"
                )
                finish(
                    .failure(
                        XmaxError(
                            code: .uploadError,
                            message: platformError.localizedDescription
                        )
                    )
                )
                return
            }

            do {
                let headers = result as? [AnyHashable: Any]
                let location = Self.headerValue(
                    keys: ["Location", "location"],
                    headers: headers
                )
                let url = try StorageManager.resolveObjectURL(
                    candidate: location,
                    configuration: configuration,
                    objectKey: objectKey
                )
                let etag =
                    Self.headerValue(
                        keys: ["Etag", "ETag", "etag"],
                        headers: headers
                    )?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""
                finish(
                    .success(
                        StoredFile(
                            url: url,
                            objectKey: objectKey,
                            etag: etag.isEmpty ? nil : etag
                        )
                    )
                )
            } catch {
                finish(.failure(error))
            }
        }
    }

    /// Registers the upload waiter or delivers a completed result.
    ///
    /// - Parameter continuation: The continuation awaiting the upload.
    private func install(
        _ continuation: CheckedContinuation<StoredFile, Error>
    ) {
        lock.lock()
        let pendingResult = self.pendingResult
        self.pendingResult = nil
        if pendingResult == nil {
            self.continuation = continuation
        }
        lock.unlock()

        if let pendingResult {
            continuation.resume(with: pendingResult)
        }
    }

    /// Submits an upload that has not started or completed.
    private func startIfNeeded() {
        lock.lock()
        guard !started, !completed else {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        service.putObject(request)
    }

    /// Cancels the underlying upload and completes its waiter.
    private func cancel() {
        finish(
            .failure(
                XmaxError(
                    code: .cancelled,
                    message: "Storage upload was cancelled"
                )
            )
        )
        request.cancel()
    }

    /// Completes the upload waiter with the first result.
    ///
    /// - Parameter result: The uploaded object or failure.
    private func finish(
        _ result: Result<StoredFile, Error>
    ) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil {
            pendingResult = result
        }
        lock.unlock()

        continuation?.resume(with: result)
    }

    /// Formats the upload duration.
    ///
    /// - Returns: The duration in milliseconds or seconds.
    private func formatDuration() -> String {
        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        if milliseconds < 1_000 {
            return "\(milliseconds) ms"
        }
        return String(
            format: "%.2f s",
            Double(milliseconds) / 1_000
        )
    }

    /// Returns the first matching string response header.
    ///
    /// - Parameters:
    ///   - keys: The accepted header names in priority order.
    ///   - headers: The response headers, if available.
    ///
    /// - Returns: The first matching string value, or `nil`.
    private static func headerValue(
        keys: [String],
        headers: [AnyHashable: Any]?
    ) -> String? {
        for key in keys {
            if let value = headers?[key] as? String {
                return value
            }
        }
        return nil
    }
}
