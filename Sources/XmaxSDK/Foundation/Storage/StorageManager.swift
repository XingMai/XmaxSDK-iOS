//
//  StorageManager.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

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

    /// 使用临时凭证上传数据或本地文件。
    ///
    /// - Parameters:
    ///   - source: 待上传的二进制数据或本地文件。
    ///   - objectKey: 存储桶内的目标对象路径。
    ///   - contentType: 上传内容的 MIME 类型。
    ///   - configuration: 存储地址、桶和临时访问凭证。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 输入无效、凭证无效、上传失败或任务取消时抛出错误。
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

    /// 下载远端文件并写入指定本地位置。
    ///
    /// - Parameters:
    ///   - remoteURL: 待下载文件的远端 URL。
    ///   - destinationURL: 写入文件的本地目标 URL。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 写入完成的本地文件 URL 与字节数。
    /// - Throws: 地址无效、下载或文件写入失败，以及任务取消时抛出错误。
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
    ///
    /// - Parameters:
    ///   - candidate: 上传响应中的候选访问地址。
    ///   - configuration: 存储桶、区域和访问端点配置。
    ///   - objectKey: 上传对象在存储桶内的键。
    /// - Returns: 可通过 HTTP 或 HTTPS 访问的对象地址。
    /// - Throws: 端点无效、对象键编码失败或地址构造失败时抛出错误。
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

    /// 校验上传源、对象键、存储位置及临时凭证。
    ///
    /// - Parameters:
    ///   - source: 待上传的数据或本地文件。
    ///   - objectKey: 目标对象键。
    ///   - contentType: 上传内容的 MIME 类型。
    ///   - configuration: 目标存储位置及临时访问凭证。
    /// - Throws: 上传配置无效或源文件不可用时抛出错误。
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

    /// 根据端点配置创建 COS 服务实例。
    ///
    /// - Parameter configuration: 存储区域及访问端点。
    /// - Returns: 用于本次上传的 COS 服务。
    /// - Throws: 端点无效或无法创建平台端点时抛出错误。
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

    /// 构造携带临时凭证的 COS 单次上传请求。
    ///
    /// - Parameters:
    ///   - source: 待上传的数据或本地文件。
    ///   - objectKey: 目标对象键。
    ///   - contentType: 上传内容的 MIME 类型。
    ///   - configuration: 目标存储位置及凭证。
    /// - Returns: 准备完成的对象上传请求。
    /// - Throws: 临时凭证无效时抛出错误。
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

    /// 将临时访问配置转换为 COS 签名凭证。
    ///
    /// - Parameter configuration: 临时密钥和会话令牌。
    /// - Returns: 供当前上传请求签名使用的凭证。
    /// - Throws: 平台凭证校验失败时抛出错误。
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

    /// 规范化存储端点并按需添加存储桶域名前缀。
    ///
    /// - Parameters:
    ///   - endpoint: 原始端点文本。
    ///   - bucket: 目标存储桶名称。
    ///   - preservePath: 是否保留端点中的路径及附加 URL 信息。
    /// - Returns: 规范化的 HTTP 或 HTTPS 端点。
    /// - Throws: 端点协议、主机或 URL 无效时抛出错误。
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

    /// 对对象键的各路径段进行 URL 编码。
    ///
    /// - Parameter objectKey: 原始对象键。
    /// - Returns: 保留路径分隔符的编码对象键。
    /// - Throws: 任一路径段无法编码时抛出错误。
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

    /// 校验存储桶或区域标识允许的字符。
    ///
    /// - Parameter value: 待校验的标识。
    /// - Returns: 非空且只包含字母、数字、点和连字符时返回 `true`。
    private static func matchesIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.range(
            of: #"^[A-Za-z0-9.-]+$"#,
            options: .regularExpression
        ) != nil
    }

    /// 将平台错误转换为上传错误。
    ///
    /// - Parameter error: 底层平台错误。
    /// - Returns: 保留本地化描述的上传错误。
    private static func uploadError(_ error: any Error) -> XmaxError {
        let platformError = error as NSError
        return uploadError(message: platformError.localizedDescription)
    }

    /// 构造上传错误。
    ///
    /// - Parameter message: 错误描述。
    /// - Returns: 包含指定描述的上传错误。
    private static func uploadError(message: String) -> XmaxError {
        XmaxError(code: .uploadError, message: message)
    }

    /// 构造存储操作取消错误。
    ///
    /// - Parameter operation: 被取消操作的名称。
    /// - Returns: 包含操作名称的取消错误。
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

    /// 创建持有一次 COS 上传请求的异步操作。
    ///
    /// - Parameters:
    ///   - service: 执行请求的 COS 服务。
    ///   - request: 待提交的上传请求。
    ///   - objectKey: 上传对象键。
    ///   - configuration: 用于解析结果地址的存储配置。
    ///   - progress: 上传进度回调；不监听时传入 `nil`。
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

    /// 提交上传请求并等待唯一的完成结果。
    ///
    /// - Returns: 上传成功的对象信息。
    /// - Throws: 上传失败、结果解析失败或任务取消时抛出错误。
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

    /// 安装上传进度和完成回调，并统一转换上传结果。
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
                XmaxLogger.storage.error(
                    message: "上传失败 (Upload Failed)\n" +
                        "├─ \(XmaxLogger.localized("错误域：", "Error Domain: "))\(platformError.domain)\n" +
                        "├─ \(XmaxLogger.localized("错误码：", "Error Code: "))\(platformError.code)\n" +
                        "├─ \(XmaxLogger.localized("错误信息：", "Error Message: "))\(platformError.localizedDescription)\n" +
                        "└─ \(XmaxLogger.localized("耗时：", "Duration: "))\(formatDuration())"
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

    /// 安装异步恢复点，或立即交付已缓存的完成结果。
    ///
    /// - Parameter continuation: 等待上传结果的 continuation。
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

    /// 仅在操作未开始且未结束时提交上传请求。
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

    /// 结束异步等待并取消底层上传请求。
    private func cancel() {
        finish(.failure(XmaxError(
            code: .cancelled,
            message: "Storage upload was cancelled"
        )))
        request.cancel()
    }

    /// 记录首个完成结果并恢复等待者。
    ///
    /// - Parameter result: 上传成功信息或失败错误。
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

    /// 格式化当前上传操作的耗时。
    ///
    /// - Returns: 以毫秒或秒表示的耗时文本。
    private func formatDuration() -> String {
        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        if milliseconds < 1_000 {
            return "\(milliseconds) ms"
        }
        return String(format: "%.2f s", Double(milliseconds) / 1_000)
    }

    /// 按优先顺序读取字符串响应头。
    ///
    /// - Parameters:
    ///   - keys: 可接受的响应头名称。
    ///   - headers: 平台返回的响应头；不可用时为 `nil`。
    /// - Returns: 首个匹配的字符串值；未找到时返回 `nil`。
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
