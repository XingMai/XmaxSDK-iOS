import Foundation
@preconcurrency import QCloudCOSXML

/// 封装第三方对象存储上传和 HTTP 文件下载能力。
final class StorageManager: StorageManaging, Sendable {

    // 平台资源
    private let session: URLSession

    /// 创建存储 Manager。
    ///
    /// - Parameter session: HTTP 下载使用的 URL Session。
    init(session: URLSession = .shared) {
        self.session = session
    }

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
            let (data, response) = try await session.data(from: remoteURL)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                throw XmaxError(
                    code: .downloadError,
                    message: statusCode.map {
                        "Storage download failed with HTTP \($0)"
                    } ?? "Storage download returned a non-HTTP response",
                    httpStatus: statusCode
                )
            }

            try data.write(to: destinationURL, options: .atomic)
            let byteCount = Int64(data.count)
            progress?(byteCount, byteCount)

            return DownloadedFile(
                fileURL: destinationURL,
                byteCount: byteCount
            )
        } catch let error as XmaxError {
            throw error
        } catch is CancellationError {
            throw Self.cancelledError(operation: "Storage download")
        } catch {
            let platformError = error as NSError
            if platformError.domain == NSURLErrorDomain,
               platformError.code == NSURLErrorCancelled {
                throw Self.cancelledError(operation: "Storage download")
            }

            throw XmaxError(
                code: .downloadError,
                message: platformError.localizedDescription
            )
        }
    }

    /// 根据上传结果或存储配置生成对象访问地址。
    static func resolveObjectURL(
        candidate: String?,
        configuration: StorageConfiguration,
        objectKey: String
    ) throws -> URL {
        let location = candidate?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if location.hasPrefix("//"),
           let url = URL(string: "https:\(location)") {
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
              !credential.sessionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw uploadError(message: "Storage temporary credential is incomplete")
        }

        if case let .file(url) = source {
            var isDirectory = ObjCBool(false)
            guard url.isFileURL,
                  FileManager.default.fileExists(
                      atPath: url.path,
                      isDirectory: &isDirectory
                  ),
                  !isDirectory.boolValue else {
                throw uploadError(message: "Storage upload file is unavailable")
            }
        }
    }

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
              let host = components.host, !host.isEmpty else {
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

    private static func encodeObjectKey(_ objectKey: String) throws -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        let encodedParts = objectKey
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) }

        guard encodedParts.allSatisfy({ $0 != nil }) else {
            throw uploadError(message: "Storage object key cannot be URL encoded")
        }
        return encodedParts.compactMap { $0 }.joined(separator: "/")
    }

    private static func matchesIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.range(
            of: #"^[A-Za-z0-9.-]+$"#,
            options: .regularExpression
        ) != nil
    }

    private static func uploadError(_ error: any Error) -> XmaxError {
        let platformError = error as NSError
        return uploadError(message: platformError.localizedDescription)
    }

    private static func uploadError(message: String) -> XmaxError {
        XmaxError(code: .uploadError, message: message)
    }

    private static func cancelledError(operation: String) -> XmaxError {
        XmaxError(
            code: .cancelled,
            message: "\(operation) was cancelled"
        )
    }
}

/// 持有一次第三方上传请求，并保证完成、失败和取消只恢复异步调用一次。
private final class StorageUploadOperation: @unchecked Sendable {

    // 上传资源
    private let service: QCloudCOSXMLService
    private let request: QCloudPutObjectRequest<AnyObject>

    // 上传配置
    private let objectKey: String
    private let configuration: StorageConfiguration
    private let progress: StorageProgressListener?

    // 运行统计
    private let startedAt = Date()

    // 并发控制
    private let lock = NSLock()

    // 运行状态
    private var continuation: CheckedContinuation<StoredFile, Error>?
    private var pendingResult: Result<StoredFile, Error>?
    private var started = false
    private var completed = false

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

    private func configureCallbacks() {
        request.sendProcessBlock = { [progress] _, totalBytes, expectedBytes in
            progress?(totalBytes, max(expectedBytes, 0))
        }
        request.finishBlock = { [weak self] result, error in
            guard let self else {
                return
            }

            if let error {
                let platformError = error as NSError
                XmaxLogger.error(
                    category: "Storage",
                    message: "上传失败 (Upload Failed)\n" +
                        "├─ 错误域：\(platformError.domain)\n" +
                        "├─ 错误码：\(platformError.code)\n" +
                        "├─ 错误信息：\(platformError.localizedDescription)\n" +
                        "└─ 耗时：\(formatDuration())"
                )
                finish(.failure(XmaxError(
                    code: .uploadError,
                    message: platformError.localizedDescription
                )))
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
                let etag = Self.headerValue(
                    keys: ["Etag", "ETag", "etag"],
                    headers: headers
                )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                finish(.success(StoredFile(
                    url: url,
                    objectKey: objectKey,
                    etag: etag.isEmpty ? nil : etag
                )))
            } catch {
                finish(.failure(error))
            }
        }
    }

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

    private func cancel() {
        finish(.failure(XmaxError(
            code: .cancelled,
            message: "Storage upload was cancelled"
        )))
        request.cancel()
    }

    private func finish(_ result: Result<StoredFile, Error>) {
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

    private func formatDuration() -> String {
        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        if milliseconds < 1_000 {
            return "\(milliseconds) ms"
        }
        return String(format: "%.2f s", Double(milliseconds) / 1_000)
    }

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
