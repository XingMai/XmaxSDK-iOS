//
//  StorageService.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AVFoundation
import Foundation
import ImageIO

/// 协调图片和视频的上传、下载、临时凭证及图片安全检查。
final class StorageService: StorageServicing, Sendable {

    /// 服务层组件
    private let apiService: any ApiServicing

    /// 基础层组件
    private let storageManager: any StorageManaging

    /// 标识生成
    private let dateGenerator: @Sendable () -> Date
    private let identifierGenerator: @Sendable () -> String

    /// 创建媒体存储服务并配置对象路径生成策略。
    ///
    /// - Parameters:
    ///   - apiService: 请求临时凭证与安全检查的 API 服务。
    ///   - storageManager: 执行实际文件上传与下载的基础组件。
    ///   - dateGenerator: 生成对象路径所用当前时间的回调。
    ///   - identifierGenerator: 生成对象路径所用随机标识的回调。
    init(
        apiService: any ApiServicing,
        storageManager: any StorageManaging,
        dateGenerator: @escaping @Sendable () -> Date = { Date() },
        identifierGenerator: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.apiService = apiService
        self.storageManager = storageManager
        self.dateGenerator = dateGenerator
        self.identifierGenerator = identifierGenerator
    }

    /// 上传图片数据。
    ///
    /// - Parameters:
    ///   - data: 编码后的图片文件数据。
    ///   - fileName: 包含扩展名的文件名，用于构造对象路径。
    ///   - contentType: 文件的 MIME 类型。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
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

    /// 上传本地图片文件。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地图片文件 URL。
    ///   - contentType: 文件 MIME 类型；`nil` 时根据文件名推断。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 文件无效、凭证获取或上传失败时抛出错误。
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

    /// 上传图片数据并通过内容安全检查。
    ///
    /// - Parameters:
    ///   - data: 编码后的图片文件数据。
    ///   - fileName: 包含扩展名的文件名，用于构造对象路径。
    ///   - contentType: 文件的 MIME 类型。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 输入无效、凭证获取或上传失败、安全检查失败时抛出错误。
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

    /// 上传本地图片文件并通过内容安全检查。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地图片文件 URL。
    ///   - contentType: 文件 MIME 类型；`nil` 时根据文件名推断。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 文件无效、凭证获取或上传失败、安全检查失败时抛出错误。
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

    /// 上传视频数据。
    ///
    /// - Parameters:
    ///   - data: 编码后的视频文件数据。
    ///   - fileName: 包含扩展名的文件名，用于构造对象路径。
    ///   - contentType: 文件的 MIME 类型。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 输入无效、凭证获取或上传失败时抛出错误。
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

    /// 上传本地视频文件。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地视频文件 URL。
    ///   - contentType: 文件 MIME 类型；`nil` 时根据文件名推断。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 包含访问 URL、对象路径与可用 ETag 的上传结果。
    /// - Throws: 文件无效、凭证获取或上传失败时抛出错误。
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

    /// 将远端图片下载到本地文件。
    ///
    /// - Parameters:
    ///   - remoteURL: 待下载文件的远端 URL。
    ///   - destinationURL: 写入文件的本地目标 URL。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 写入完成的本地文件 URL 与字节数。
    /// - Throws: 地址无效、下载或文件写入失败，以及任务取消时抛出错误。
    func downloadImage(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener? = nil
    ) async throws -> DownloadedFile {
        try validateDownload(
            remoteURL: remoteURL,
            destinationURL: destinationURL
        )
        return try await storageManager.download(
            remoteURL: remoteURL,
            destinationURL: destinationURL,
            progress: progress
        )
    }

    /// 将远端视频下载到本地文件。
    ///
    /// - Parameters:
    ///   - remoteURL: 待下载文件的远端 URL。
    ///   - destinationURL: 写入文件的本地目标 URL。
    ///   - progress: 接收已传输字节数与总字节数的回调；`nil` 不接收进度。
    /// - Returns: 写入完成的本地文件 URL 与字节数。
    /// - Throws: 地址无效、下载或文件写入失败，以及任务取消时抛出错误。
    func downloadVideo(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener? = nil
    ) async throws -> DownloadedFile {
        try validateDownload(
            remoteURL: remoteURL,
            destinationURL: destinationURL
        )
        return try await storageManager.download(
            remoteURL: remoteURL,
            destinationURL: destinationURL,
            progress: progress
        )
    }
}

private extension StorageService {
    /// 包含对象路径前缀和临时存储访问配置。
    struct TemporaryStorageConfiguration: Sendable {

        /// 上传配置
        let prefix: String
        let configuration: StorageConfiguration
    }

    /// 区分图片与视频的上传校验和元数据读取规则。
    enum StorageMediaType: String, Sendable {
        case image
        case video

        /// 类型名称
        var displayName: String {
            rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// 接收服务端返回的临时存储位置与凭证字段。
    struct TemporaryStoragePayload: Decodable, Sendable {

        /// 存储位置
        let bucket: String?
        let region: String?
        let endpoint: String?
        let prefix: String?

        /// 临时凭证
        let credentials: CredentialPayload?

        /// 定义服务端字段与本地属性的编码映射。
        enum CodingKeys: CodingKey {
            case bucket
            case region
            case endpoint
            case prefix
            case credentials
        }

        /// 解码临时存储配置响应，无法解析的字段保留为空。
        ///
        /// - Parameter decoder: 提供存储响应字段的解码器。
        /// - Throws: 字段解码容器创建失败时抛出解码错误。
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

    /// 接收对象存储的临时认证字段。
    struct CredentialPayload: Decodable, Sendable {

        /// 认证字段
        let accessKeyID: String?
        let secretAccessKey: String?
        let sessionToken: String?

        /// 定义服务端字段与本地属性的编码映射。
        enum CodingKeys: String, CodingKey {
            case accessKeyID = "accessKeyId"
            case secretAccessKey
            case sessionToken
        }

        /// 解码临时存储凭证，无法解析的字段保留为空。
        ///
        /// - Parameter decoder: 提供凭证字段的解码器。
        /// - Throws: 字段解码容器创建失败时抛出解码错误。
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

    /// 提交待检查图片的远端地址。
    struct ImageSafetyRequest: Encodable, Sendable {

        /// 检查请求
        let url: String
    }

    /// 接收图片安全检查结果及可使用的图片地址。
    struct ImageSafetyPayload: Decodable, Sendable {

        /// 检查结果
        let safe: Bool?
        let url: String?

        /// 定义服务端字段与本地属性的编码映射。
        enum CodingKeys: CodingKey {
            case safe
            case url
        }

        /// 解码图片安全检查结果。
        ///
        /// - Parameter decoder: 提供安全检查响应的解码器。
        /// - Throws: 字段解码容器创建失败时抛出解码错误。
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            safe = try? container.decode(Bool.self, forKey: .safe)
            url = try? container.decode(String.self, forKey: .url)
        }
    }

    /// 校验媒体、获取临时凭证并上传，按需完成图片安全检查。
    ///
    /// - Parameters:
    ///   - source: 待上传的数据或本地文件。
    ///   - fileName: 用于生成对象路径的原始文件名。
    ///   - contentType: 上传文件的 MIME 类型。
    ///   - mediaType: 用于校验内容类型和读取尺寸的媒体类型。
    ///   - checksSafety: 是否在上传完成后执行图片安全检查。
    ///   - progress: 字节进度回调；`nil` 不接收进度。
    /// - Returns: 上传成功且完成所需安全检查的远端文件信息。
    /// - Throws: 媒体参数无效、凭证获取或上传失败、安全检查失败及取消时抛出错误。
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
            XmaxLogger.storage.info(
                message: "开始上传 (Upload Started)\n" +
                    "├─ \(XmaxLogger.localized("类型：", "Type: "))\(mediaType.rawValue)\n" +
                    "├─ \(XmaxLogger.localized("分辨率：", "Resolution: "))\(resolution)\n" +
                    "├─ \(XmaxLogger.localized("大小：", "Size: "))\(formatByteCount(byteCount))\n" +
                    "└─ \(XmaxLogger.localized("安全检测：", "Safety Check: "))\(checksSafety)"
            )

            let temporary = try await fetchStorageConfiguration()
            let objectKey = makeObjectKey(
                prefix: temporary.prefix,
                fileName: safeName
            )
            let stored = try await storageManager.upload(
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

            XmaxLogger.storage.info(
                message: "上传完成 (Upload Completed)\n" +
                    "├─ \(XmaxLogger.localized("地址：", "URL: "))\(result.url.absoluteString)\n" +
                    "└─ \(XmaxLogger.localized("耗时：", "Duration: "))\(formatDuration(since: startedAt))"
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

    /// 获取并校验临时存储配置。
    ///
    /// - Returns: 对象路径前缀及完整临时访问配置。
    /// - Throws: 接口请求失败或必要凭证字段无效时抛出错误。
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

    /// 请求图片安全检查并返回通过检查的图片地址。
    ///
    /// - Parameter url: 已上传图片的远端地址。
    /// - Returns: 服务端确认可使用的图片地址。
    /// - Throws: 请求失败、检查结果无效或图片未通过安全检查时抛出错误。
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

    /// 检查上传源和媒体类型，并生成安全文件名。
    ///
    /// - Parameters:
    ///   - source: 待上传的数据或本地文件。
    ///   - fileName: 需要规范化的文件名。
    ///   - contentType: 需要匹配媒体类型的 MIME 类型。
    ///   - mediaType: 本次上传允许的媒体类型。
    /// - Returns: 可用于对象路径的安全文件名。
    /// - Throws: 上传源为空或无效、MIME 类型不符或文件名无有效字符时抛出配置错误。
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

    /// 校验远端下载地址和本地目标地址。
    ///
    /// - Parameters:
    ///   - remoteURL: 带主机名的 HTTP 或 HTTPS 地址。
    ///   - destinationURL: 本地目标文件 URL。
    /// - Throws: 下载地址或目标文件 URL 不合法时抛出配置错误。
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

    /// 根据图片文件扩展名推断 MIME 类型。
    ///
    /// - Parameter fileName: 包含图片扩展名的文件名。
    /// - Returns: 扩展名对应的图片 MIME 类型。
    /// - Throws: 扩展名不在支持列表内时抛出配置错误。
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

    /// 根据视频文件扩展名推断 MIME 类型。
    ///
    /// - Parameter fileName: 包含视频扩展名的文件名。
    /// - Returns: 扩展名对应的视频 MIME 类型。
    /// - Throws: 扩展名不在支持列表内时抛出配置错误。
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

    /// 从扩展名映射中查找文件的 MIME 类型。
    ///
    /// - Parameters:
    ///   - fileName: 包含扩展名的文件名。
    ///   - types: 小写扩展名与 MIME 类型的映射。
    ///   - mediaType: 用于错误信息的媒体类型名称。
    /// - Returns: 文件扩展名对应的 MIME 类型。
    /// - Throws: 无法在映射中找到扩展名时抛出配置错误。
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

    /// 将不支持的文件名字符替换为下划线，并去除边界分隔符。
    ///
    /// - Parameter value: 待规范化的原始文件名。
    /// - Returns: 仅包含字母、数字及允许分隔符的文件名；无有效字符时为空字符串。
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

    /// 组合服务端前缀、毫秒时间、随机标识和文件名形成对象路径。
    ///
    /// - Parameters:
    ///   - prefix: 服务端允许写入的对象路径前缀。
    ///   - fileName: 已校验的安全文件名。
    /// - Returns: 本次上传使用的完整对象路径。
    func makeObjectKey(prefix: String, fileName: String) -> String {
        let milliseconds = Int64(
            dateGenerator().timeIntervalSince1970 * 1_000
        )
        let identifier = identifierGenerator().lowercased()
        return "\(prefix)\(milliseconds)_\(identifier)_\(fileName)"
    }

    /// 读取上传源占用的字节数。
    ///
    /// - Parameter source: 待上传的数据或本地文件。
    /// - Returns: 数据长度或文件大小，单位为字节。
    /// - Throws: 读取本地文件属性失败时抛出文件系统错误。
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

    /// 读取用于上传日志的媒体显示尺寸，无法读取时使用占位文本。
    ///
    /// - Parameters:
    ///   - source: 待上传的数据或文件。
    ///   - mediaType: 决定图片或视频元数据读取方式的类型。
    /// - Returns: 宽高文本；无法读取时返回 `--`。
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

    /// 读取图片头中的像素尺寸。
    ///
    /// - Parameter source: 图片编码数据或本地图片文件。
    /// - Returns: 图片宽高文本；元数据缺失时返回 `--`。
    /// - Throws: 无；无法读取图片属性时返回占位文本。
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

    /// 读取本地视频应用旋转变换后的显示尺寸。
    ///
    /// - Parameter source: 视频上传源；内存数据不读取分辨率。
    /// - Returns: 视频显示宽高文本；不是文件或没有视频轨道时返回 `--`。
    /// - Throws: 视频轨道或变换信息加载失败时抛出媒体读取错误。
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

    /// 将有效宽高格式化为日志尺寸文本。
    ///
    /// - Parameters:
    ///   - width: 媒体宽度，单位为像素。
    ///   - height: 媒体高度，单位为像素。
    /// - Returns: 宽高文本；任一边长非正数时返回 `--`。
    func formatResolution(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else {
            return "--"
        }
        return "\(width) × \(height)"
    }

    /// 按文件大小选择可读单位并格式化。
    ///
    /// - Parameter byteCount: 文件大小，单位为字节。
    /// - Returns: 以 B、KB、MB 或 GB 表示的大小文本。
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

    /// 计算操作耗时并选择毫秒或秒作为显示单位。
    ///
    /// - Parameter startedAt: 操作开始时间。
    /// - Returns: 格式化后的耗时文本。
    func formatDuration(since startedAt: Date) -> String {
        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        if milliseconds < 1_000 {
            return "\(milliseconds) ms"
        }
        return String(format: "%.2f s", Double(milliseconds) / 1_000)
    }

    /// 输出上传错误码、原因和耗时日志。
    ///
    /// - Parameters:
    ///   - error: 需要记录的上传错误。
    ///   - startedAt: 本次上传操作的开始时间。
    func logUploadFailure(_ error: XmaxError, startedAt: Date) {
        XmaxLogger.storage.error(
            message: "上传失败 (Upload Failed)\n" +
                "├─ \(XmaxLogger.localized("错误码：", "Error Code: "))\(error.code.rawValue)\n" +
                "├─ \(XmaxLogger.localized("原因：", "Reason: "))\(error.message)\n" +
                "└─ \(XmaxLogger.localized("耗时：", "Duration: "))\(formatDuration(since: startedAt))"
        )
    }

    /// 去除可选字符串的首尾空白。
    ///
    /// - Parameter value: 需要规范化的可选字符串。
    /// - Returns: 规范化的字符串；原值为 `nil` 时仍返回 `nil`。
    func normalizedString(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 读取去除首尾空白后的非空字符串。
    ///
    /// - Parameter value: 需要校验的可选字段。
    /// - Returns: 非空字段值；缺失或仅包含空白时返回 `nil`。
    func requiredString(_ value: String?) -> String? {
        guard let value = normalizedString(value), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// 判断 URL 是否为具有有效主机名的 HTTP 或 HTTPS 地址。
    ///
    /// - Parameter url: 待检查的 URL。
    /// - Returns: 协议与主机名均符合要求时返回 `true`。
    func isHTTPURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return (scheme == "https" || scheme == "http")
            && url.host?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty == false
    }
}
