import AVFoundation
import Foundation
import ImageIO

/// 协调图片和视频的上传、下载、临时凭证及图片安全检查。
final class StorageService: StorageServicing, Sendable {

    // 服务层组件
    private let apiService: any ApiServicing

    // 基础层组件
    private let storageProvider: any StorageProviding

    // 标识生成
    private let dateProvider: @Sendable () -> Date
    private let identifierProvider: @Sendable () -> String

    /// 创建存储 Service。
    init(
        apiService: any ApiServicing,
        storageProvider: any StorageProviding,
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        identifierProvider: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.apiService = apiService
        self.storageProvider = storageProvider
        self.dateProvider = dateProvider
        self.identifierProvider = identifierProvider
    }

    func uploadImage(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener? = nil
    ) async throws -> StoredFile {
        try await upload(
            source: .data(data),
            fileName: fileName,
            contentType: contentType,
            mediaType: .image,
            checksSafety: false,
            progress: progress
        )
    }

    func uploadImageFile(
        fileURL: URL,
        contentType: String? = nil,
        progress: StorageProgressListener? = nil
    ) async throws -> StoredFile {
        let fileName = fileURL.lastPathComponent
        return try await upload(
            source: .file(fileURL),
            fileName: fileName,
            contentType: contentType ?? inferImageContentType(fileName),
            mediaType: .image,
            checksSafety: false,
            progress: progress
        )
    }

    func uploadImageWithSafetyCheck(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener? = nil
    ) async throws -> StoredFile {
        try await upload(
            source: .data(data),
            fileName: fileName,
            contentType: contentType,
            mediaType: .image,
            checksSafety: true,
            progress: progress
        )
    }

    func uploadImageFileWithSafetyCheck(
        fileURL: URL,
        contentType: String? = nil,
        progress: StorageProgressListener? = nil
    ) async throws -> StoredFile {
        let fileName = fileURL.lastPathComponent
        return try await upload(
            source: .file(fileURL),
            fileName: fileName,
            contentType: contentType ?? inferImageContentType(fileName),
            mediaType: .image,
            checksSafety: true,
            progress: progress
        )
    }

    func uploadVideo(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener? = nil
    ) async throws -> StoredFile {
        try await upload(
            source: .data(data),
            fileName: fileName,
            contentType: contentType,
            mediaType: .video,
            checksSafety: false,
            progress: progress
        )
    }

    func uploadVideoFile(
        fileURL: URL,
        contentType: String? = nil,
        progress: StorageProgressListener? = nil
    ) async throws -> StoredFile {
        let fileName = fileURL.lastPathComponent
        return try await upload(
            source: .file(fileURL),
            fileName: fileName,
            contentType: contentType ?? inferVideoContentType(fileName),
            mediaType: .video,
            checksSafety: false,
            progress: progress
        )
    }

    func downloadImage(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener? = nil
    ) async throws -> DownloadedFile {
        try validateDownload(
            remoteURL: remoteURL,
            destinationURL: destinationURL
        )
        return try await storageProvider.download(
            remoteURL: remoteURL,
            destinationURL: destinationURL,
            progress: progress
        )
    }

    func downloadVideo(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener? = nil
    ) async throws -> DownloadedFile {
        try validateDownload(
            remoteURL: remoteURL,
            destinationURL: destinationURL
        )
        return try await storageProvider.download(
            remoteURL: remoteURL,
            destinationURL: destinationURL,
            progress: progress
        )
    }
}

private extension StorageService {
    struct TemporaryStorageConfiguration: Sendable {
        let prefix: String
        let configuration: StorageConfiguration
    }

    enum StorageMediaType: String, Sendable {
        case image
        case video

        var displayName: String {
            rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    struct TemporaryStoragePayload: Decodable, Sendable {
        let bucket: String?
        let region: String?
        let endpoint: String?
        let prefix: String?
        let credentials: CredentialPayload?

        enum CodingKeys: CodingKey {
            case bucket
            case region
            case endpoint
            case prefix
            case credentials
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bucket = try? container.decode(String.self, forKey: .bucket)
            region = try? container.decode(String.self, forKey: .region)
            endpoint = try? container.decode(String.self, forKey: .endpoint)
            prefix = try? container.decode(String.self, forKey: .prefix)
            credentials = try? container.decode(
                CredentialPayload.self,
                forKey: .credentials
            )
        }
    }

    struct CredentialPayload: Decodable, Sendable {
        let accessKeyID: String?
        let secretAccessKey: String?
        let sessionToken: String?

        enum CodingKeys: String, CodingKey {
            case accessKeyID = "accessKeyId"
            case secretAccessKey
            case sessionToken
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            accessKeyID = try? container.decode(
                String.self,
                forKey: .accessKeyID
            )
            secretAccessKey = try? container.decode(
                String.self,
                forKey: .secretAccessKey
            )
            sessionToken = try? container.decode(
                String.self,
                forKey: .sessionToken
            )
        }
    }

    struct ImageSafetyRequest: Encodable, Sendable {
        let url: String
    }

    struct ImageSafetyPayload: Decodable, Sendable {
        let safe: Bool?
        let url: String?

        enum CodingKeys: CodingKey {
            case safe
            case url
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            safe = try? container.decode(Bool.self, forKey: .safe)
            url = try? container.decode(String.self, forKey: .url)
        }
    }

    func upload(
        source: StorageUploadSource,
        fileName: String,
        contentType: String,
        mediaType: StorageMediaType,
        checksSafety: Bool,
        progress: StorageProgressListener?
    ) async throws -> StoredFile {
        let startedAt = Date()
        do {
            let safeName = try validateUpload(
                source: source,
                fileName: fileName,
                contentType: contentType,
                mediaType: mediaType
            )
            let byteCount = try sourceByteCount(source)
            let resolution = await readResolution(
                source: source,
                mediaType: mediaType
            )
            XmaxLogger.info(
                "开始上传\n" +
                    "├─ 类型：\(mediaType.rawValue)\n" +
                    "├─ 分辨率：\(resolution)\n" +
                    "├─ 大小：\(formatByteCount(byteCount))\n" +
                    "└─ 安全检测：\(checksSafety)",
                category: "Storage"
            )

            let temporary = try await fetchStorageConfiguration()
            let objectKey = makeObjectKey(
                prefix: temporary.prefix,
                fileName: safeName
            )
            let stored = try await storageProvider.upload(
                source: source,
                objectKey: objectKey,
                contentType: contentType.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                configuration: temporary.configuration,
                progress: progress
            )

            let result: StoredFile
            if checksSafety {
                let checkedURL = try await checkImage(stored.url)
                result = StoredFile(
                    url: checkedURL,
                    objectKey: stored.objectKey,
                    etag: stored.etag
                )
            } else {
                result = stored
            }

            XmaxLogger.info(
                "上传完成\n" +
                    "├─ 地址：\(result.url.absoluteString)\n" +
                    "└─ 耗时：\(formatDuration(since: startedAt))",
                category: "Storage"
            )
            return result
        } catch let error as XmaxError {
            if error.code != .uploadError {
                logUploadFailure(error, startedAt: startedAt)
            }
            throw error
        } catch is CancellationError {
            let error = XmaxError(
                code: .cancelled,
                message: "Storage upload was cancelled"
            )
            logUploadFailure(error, startedAt: startedAt)
            throw error
        } catch {
            let uploadError = XmaxError(
                code: .uploadError,
                message: ErrorMessageFormatter.format(error)
            )
            throw uploadError
        }
    }

    func fetchStorageConfiguration() async throws -> TemporaryStorageConfiguration {
        let payload = try await apiService.get(
            "/cos/sts",
            as: TemporaryStoragePayload.self
        )
        let message = "Invalid storage credential payload"
        guard let bucket = requiredString(payload.bucket),
              let region = requiredString(payload.region),
              let endpoint = normalizedString(payload.endpoint),
              let prefix = normalizedString(payload.prefix),
              let credentials = payload.credentials,
              let accessKeyID = requiredString(credentials.accessKeyID),
              let secretAccessKey = requiredString(
                  credentials.secretAccessKey
              ),
              let sessionToken = requiredString(credentials.sessionToken) else {
            throw XmaxError(code: .apiError, message: message)
        }

        return TemporaryStorageConfiguration(
            prefix: prefix,
            configuration: StorageConfiguration(
                bucket: bucket,
                region: region,
                endpoint: endpoint,
                credential: StorageCredential(
                    accessKeyID: accessKeyID,
                    secretAccessKey: secretAccessKey,
                    sessionToken: sessionToken
                )
            )
        )
    }

    func checkImage(_ url: URL) async throws -> URL {
        let payload = try await apiService.post(
            "/cos/image/check",
            body: ImageSafetyRequest(url: url.absoluteString),
            as: ImageSafetyPayload.self
        )
        let message = "Invalid image safety check payload"
        guard let safe = payload.safe else {
            throw XmaxError(code: .apiError, message: message)
        }
        guard safe else {
            throw XmaxError(
                code: .unsafeImage,
                message: "The image did not pass the safety check"
            )
        }
        guard let value = normalizedString(payload.url),
              let checkedURL = URL(string: value),
              isHTTPURL(checkedURL) else {
            throw XmaxError(code: .apiError, message: message)
        }
        return checkedURL
    }

    func validateUpload(
        source: StorageUploadSource,
        fileName: String,
        contentType: String,
        mediaType: StorageMediaType
    ) throws -> String {
        switch source {
        case .data(let data):
            guard !data.isEmpty else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "\(mediaType.displayName) data cannot be empty"
                )
            }
        case .file(let fileURL):
            var isDirectory = ObjCBool(false)
            guard fileURL.isFileURL,
                  FileManager.default.fileExists(
                      atPath: fileURL.path,
                      isDirectory: &isDirectory
                  ),
                  !isDirectory.boolValue else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "\(mediaType.displayName) file URL must reference " +
                        "an existing file"
                )
            }
        }

        let normalizedContentType = contentType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedContentType.hasPrefix("\(mediaType.rawValue)/") else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "\(mediaType.displayName) content type must begin " +
                    "with \(mediaType.rawValue)/"
            )
        }

        let safeName = sanitizeFileName(fileName)
        guard !safeName.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "\(mediaType.displayName) file name cannot be empty"
            )
        }
        return safeName
    }

    func validateDownload(
        remoteURL: URL,
        destinationURL: URL
    ) throws {
        guard isHTTPURL(remoteURL) else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Invalid download URL"
            )
        }
        guard destinationURL.isFileURL, !destinationURL.path.isEmpty else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Download destination URL must be a file URL"
            )
        }
    }

    func inferImageContentType(_ fileName: String) throws -> String {
        try inferContentType(
            fileName: fileName,
            types: [
                "jpg": "image/jpeg",
                "jpeg": "image/jpeg",
                "jpe": "image/jpeg",
                "png": "image/png",
                "gif": "image/gif",
                "webp": "image/webp",
                "heic": "image/heic",
                "heif": "image/heif",
                "bmp": "image/bmp",
                "svg": "image/svg+xml",
                "tif": "image/tiff",
                "tiff": "image/tiff",
                "avif": "image/avif"
            ],
            mediaType: "image"
        )
    }

    func inferVideoContentType(_ fileName: String) throws -> String {
        try inferContentType(
            fileName: fileName,
            types: [
                "mp4": "video/mp4",
                "mov": "video/quicktime",
                "m4v": "video/x-m4v",
                "webm": "video/webm",
                "avi": "video/x-msvideo",
                "mkv": "video/x-matroska",
                "3gp": "video/3gpp",
                "3g2": "video/3gpp2",
                "ts": "video/mp2t"
            ],
            mediaType: "video"
        )
    }

    func inferContentType(
        fileName: String,
        types: [String: String],
        mediaType: String
    ) throws -> String {
        let fileExtension = URL(fileURLWithPath: fileName)
            .pathExtension
            .lowercased()
        guard let contentType = types[fileExtension] else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Unable to infer \(mediaType) content type from " +
                    "file extension"
            )
        }
        return contentType
    }

    func sanitizeFileName(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.formUnion(CharacterSet(charactersIn: "._-"))
        let components = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: allowed.inverted)
        var result = components.joined(separator: "_")
        while result.contains("__") {
            result = result.replacingOccurrences(of: "__", with: "_")
        }
        return result.trimmingCharacters(
            in: CharacterSet(charactersIn: "._-")
        )
    }

    func makeObjectKey(prefix: String, fileName: String) -> String {
        let milliseconds = Int64(
            dateProvider().timeIntervalSince1970 * 1_000
        )
        let identifier = identifierProvider().lowercased()
        return "\(prefix)\(milliseconds)_\(identifier)_\(fileName)"
    }

    func sourceByteCount(_ source: StorageUploadSource) throws -> Int64 {
        switch source {
        case .data(let data):
            return Int64(data.count)
        case .file(let fileURL):
            let attributes = try FileManager.default.attributesOfItem(
                atPath: fileURL.path
            )
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }
    }

    func readResolution(
        source: StorageUploadSource,
        mediaType: StorageMediaType
    ) async -> String {
        do {
            switch mediaType {
            case .image:
                return try readImageResolution(source)
            case .video:
                return try await readVideoResolution(source)
            }
        } catch {
            return "--"
        }
    }

    func readImageResolution(_ source: StorageUploadSource) throws -> String {
        let imageSource: CGImageSource?
        switch source {
        case .data(let data):
            imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        case .file(let fileURL):
            imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil)
        }
        guard let imageSource,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  imageSource,
                  0,
                  nil
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return "--"
        }
        return formatResolution(
            width: width.intValue,
            height: height.intValue
        )
    }

    func readVideoResolution(
        _ source: StorageUploadSource
    ) async throws -> String {
        guard case .file(let fileURL) = source else {
            return "--"
        }
        let asset = AVURLAsset(url: fileURL)
        guard let track = try await asset.loadTracks(
            withMediaType: .video
        ).first else {
            return "--"
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformedSize = naturalSize.applying(transform)
        return formatResolution(
            width: Int(abs(transformedSize.width).rounded()),
            height: Int(abs(transformedSize.height).rounded())
        )
    }

    func formatResolution(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else {
            return "--"
        }
        return "\(width) × \(height)"
    }

    func formatByteCount(_ byteCount: Int64) -> String {
        let count = Double(byteCount)
        if byteCount < 1_024 {
            return "\(byteCount) B"
        }
        if byteCount < 1_024 * 1_024 {
            return String(format: "%.1f KB", count / 1_024)
        }
        if byteCount < 1_024 * 1_024 * 1_024 {
            return String(format: "%.2f MB", count / (1_024 * 1_024))
        }
        return String(
            format: "%.2f GB",
            count / (1_024 * 1_024 * 1_024)
        )
    }

    func formatDuration(since startedAt: Date) -> String {
        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        if milliseconds < 1_000 {
            return "\(milliseconds) ms"
        }
        return String(format: "%.2f s", Double(milliseconds) / 1_000)
    }

    func logUploadFailure(_ error: XmaxError, startedAt: Date) {
        XmaxLogger.error(
            "上传失败\n" +
                "├─ 错误码：\(error.code.rawValue)\n" +
                "├─ 原因：\(error.message)\n" +
                "└─ 耗时：\(formatDuration(since: startedAt))",
            category: "Storage"
        )
    }

    func normalizedString(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func requiredString(_ value: String?) -> String? {
        guard let value = normalizedString(value), !value.isEmpty else {
            return nil
        }
        return value
    }

    func isHTTPURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return (scheme == "https" || scheme == "http")
            && url.host?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty == false
    }
}
