//
//  StorageService.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AVFoundation
import Foundation
import ImageIO

/// Coordinates media transfers, temporary credentials, and image safety checks.
final class StorageService: StorageServicing, Sendable {

    /// The credentials and safety-check API service.
    private let apiService: any ApiServicing

    /// The file transfer manager.
    private let storageManager: any StorageManaging

    /// The clock for object path generation.
    private let dateGenerator: @Sendable () -> Date

    /// The unique upload name generator.
    private let identifierGenerator: @Sendable () -> String

    /// Creates a media storage service.
    init(
        apiService: any ApiServicing,
        storageManager: any StorageManaging,
        dateGenerator: @escaping @Sendable () -> Date = {
            Date()
        },
        identifierGenerator: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.apiService = apiService
        self.storageManager = storageManager
        self.dateGenerator = dateGenerator
        self.identifierGenerator = identifierGenerator
    }

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

    /// The upload object prefix and temporary storage configuration.
    struct TemporaryStorageConfiguration: Sendable {

        /// The upload object key prefix.
        let prefix: String

        /// The upload destination and credentials.
        let configuration: StorageConfiguration
    }

    /// The media validation and metadata rules for an upload.
    enum StorageMediaType: String, Sendable {

        /// Image upload and safety verification.
        case image

        /// Video file upload.
        case video

        /// The media type name used in logs.
        var displayName: String {
            rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// The temporary storage configuration response.
    struct TemporaryStoragePayload: Decodable, Sendable {

        /// The COS bucket name.
        let bucket: String?

        /// The COS bucket region.
        let region: String?

        /// The object storage endpoint.
        let endpoint: String?

        /// The upload object key prefix.
        let prefix: String?

        /// The request's temporary authentication.
        let credentials: CredentialPayload?

        /// The encoded server field names.
        enum CodingKeys: CodingKey {

            /// The bucket name field.
            case bucket

            /// The storage region field.
            case region

            /// The storage endpoint field.
            case endpoint

            /// The object prefix field.
            case prefix

            /// The temporary credentials field.
            case credentials
        }

        /// Decodes storage configuration, allowing invalid fields to be absent.
        ///
        /// - Parameter decoder: The storage response decoder.
        ///
        /// - Throws: A decoding error if a keyed container cannot be created.
        init(
            from decoder: any Decoder
        ) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            bucket = try? container.decode(
                String.self,
                forKey: .bucket
            )
            region = try? container.decode(
                String.self,
                forKey: .region
            )
            endpoint = try? container.decode(
                String.self,
                forKey: .endpoint
            )
            prefix = try? container.decode(
                String.self,
                forKey: .prefix
            )
            credentials = try? container.decode(
                CredentialPayload.self,
                forKey: .credentials
            )
        }
    }

    /// The temporary object storage credentials response.
    struct CredentialPayload: Decodable, Sendable {

        /// The temporary access key identifier.
        let accessKeyID: String?

        /// The temporary secret access key.
        let secretAccessKey: String?

        /// The temporary session token.
        let sessionToken: String?

        /// The encoded server field names.
        enum CodingKeys: String, CodingKey {

            /// The temporary access key identifier field.
            case accessKeyID = "accessKeyId"

            /// The temporary secret key field.
            case secretAccessKey

            /// The session token field.
            case sessionToken
        }

        /// Decodes temporary credentials, allowing invalid fields to be absent.
        ///
        /// - Parameter decoder: The credentials decoder.
        ///
        /// - Throws: A decoding error if a keyed container cannot be created.
        init(
            from decoder: any Decoder
        ) throws {
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

    /// An image safety check request.
    struct ImageSafetyRequest: Encodable, Sendable {

        /// The image URL to verify.
        let url: String
    }

    /// The image safety result and usable image URL.
    struct ImageSafetyPayload: Decodable, Sendable {

        /// Whether the server approved the image.
        let safe: Bool?

        /// The server-provided image URL.
        let url: String?

        /// The encoded server field names.
        enum CodingKeys: CodingKey {

            /// The image safety result field.
            case safe

            /// The image URL field.
            case url
        }

        /// Decodes an image safety result.
        ///
        /// - Parameter decoder: The safety response decoder.
        ///
        /// - Throws: A decoding error if a keyed container cannot be created.
        init(
            from decoder: any Decoder
        ) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            safe = try? container.decode(
                Bool.self,
                forKey: .safe
            )
            url = try? container.decode(
                String.self,
                forKey: .url
            )
        }
    }

    /// Uploads validated media and optionally verifies image safety.
    ///
    /// - Parameters:
    ///   - source: The data or local file to upload.
    ///   - fileName: The original filename for object naming.
    ///   - contentType: The upload MIME type.
    ///   - mediaType: The media validation and metadata type.
    ///   - checksSafety: Whether to verify image safety after upload.
    ///   - progress: The byte progress handler, or `nil` to omit notifications.
    ///
    /// - Returns: The uploaded file after any required safety check.
    ///
    /// - Throws: An error if media validation, credentials, uploading, or safety verification
    ///   fails, or the call is cancelled.
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
                message: "开始上传 (Upload Started)\n"
                    + "├─ \(XmaxLogger.localized("类型：", "Type: "))\(mediaType.rawValue)\n"
                    + "├─ \(XmaxLogger.localized("分辨率：", "Resolution: "))\(resolution)\n"
                    + "├─ \(XmaxLogger.localized("大小：", "Size: "))\(formatByteCount(byteCount))\n"
                    + "└─ \(XmaxLogger.localized("安全检测：", "Safety Check: "))\(checksSafety)"
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
                message: "上传完成 (Upload Completed)\n"
                    + "├─ \(XmaxLogger.localized("地址：", "URL: "))\(result.url.absoluteString)\n"
                    + "└─ \(XmaxLogger.localized("耗时：", "Duration: "))\(formatDuration(since: startedAt))"
            )
            return result
        } catch let error as XmaxError {
            if error.code != .uploadError {
                logUploadFailure(
                    error,
                    startedAt: startedAt
                )
            }
            throw error
        } catch is CancellationError {
            let error = XmaxError(
                code: .cancelled,
                message: "Storage upload was cancelled"
            )
            logUploadFailure(
                error,
                startedAt: startedAt
            )
            throw error
        } catch {
            let uploadError = XmaxError(
                code: .uploadError,
                message: ErrorMessageFormatter.format(error)
            )
            throw uploadError
        }
    }

    /// Fetches and validates temporary storage configuration.
    ///
    /// - Returns: The object prefix and complete temporary configuration.
    ///
    /// - Throws: An error if the request fails or required credential fields are invalid.
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
            let sessionToken = requiredString(credentials.sessionToken)
        else {
            throw XmaxError(
                code: .apiError,
                message: message
            )
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

    /// Verifies image safety and returns the approved URL.
    ///
    /// - Parameter url: The uploaded image URL.
    ///
    /// - Returns: The server-approved image URL.
    ///
    /// - Throws: An error if the request or response is invalid or the image is rejected.
    func checkImage(
        _ url: URL
    ) async throws -> URL {
        let payload = try await apiService.post(
            "/cos/image/check",
            body: ImageSafetyRequest(url: url.absoluteString),
            as: ImageSafetyPayload.self
        )
        let message = "Invalid image safety check payload"
        guard let safe = payload.safe else {
            throw XmaxError(
                code: .apiError,
                message: message
            )
        }
        guard safe else {
            throw XmaxError(
                code: .unsafeImage,
                message: "The image did not pass the safety check"
            )
        }
        guard let value = normalizedString(payload.url),
            let checkedURL = URL(string: value),
            isHTTPURL(checkedURL)
        else {
            throw XmaxError(
                code: .apiError,
                message: message
            )
        }

        return checkedURL
    }

    /// Validates an upload source and media type and resolves its filename.
    ///
    /// - Parameters:
    ///   - source: The data or local file to upload.
    ///   - fileName: The filename to normalize.
    ///   - contentType: The MIME type to validate against the media type.
    ///   - mediaType: The allowed media type.
    ///
    /// - Returns: A filename safe for an object path.
    ///
    /// - Throws: A configuration error if the source, MIME type, or filename is invalid.
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
                !isDirectory.boolValue
            else {
                throw XmaxError(
                    code: .invalidConfiguration,
                    message: "\(mediaType.displayName) file URL must reference an existing file"
                )
            }
        }

        let normalizedContentType =
            contentType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedContentType.hasPrefix("\(mediaType.rawValue)/") else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "\(mediaType.displayName) content type must begin with \(mediaType.rawValue)/"
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

    /// Validates remote and destination file URLs.
    ///
    /// - Parameters:
    ///   - remoteURL: An HTTP or HTTPS URL with a host.
    ///   - destinationURL: The destination local file URL.
    ///
    /// - Throws: A configuration error if either URL is invalid.
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

    /// Infers an image MIME type from its extension.
    ///
    /// - Parameter fileName: The image filename.
    ///
    /// - Returns: The MIME type for the image extension.
    ///
    /// - Throws: A configuration error if the extension is unsupported.
    func inferImageContentType(
        _ fileName: String
    ) throws -> String {
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

    /// Infers a video MIME type from its extension.
    ///
    /// - Parameter fileName: The video filename.
    ///
    /// - Returns: The MIME type for the video extension.
    ///
    /// - Throws: A configuration error if the extension is unsupported.
    func inferVideoContentType(
        _ fileName: String
    ) throws -> String {
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

    /// Resolves a MIME type from a filename extension map.
    ///
    /// - Parameters:
    ///   - fileName: The filename, including its extension.
    ///   - types: The lowercase extension-to-MIME map.
    ///   - mediaType: The media type name for error messages.
    ///
    /// - Returns: The filename extension's MIME type.
    ///
    /// - Throws: A configuration error if the extension is not mapped.
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
                message: "Unable to infer \(mediaType) content type from file extension"
            )
        }
        return contentType
    }

    /// Normalizes a filename for object storage.
    ///
    /// - Parameter value: The original filename.
    ///
    /// - Returns: A filename with allowed characters, or an empty string if none remain.
    func sanitizeFileName(
        _ value: String
    ) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.formUnion(CharacterSet(charactersIn: "._-"))
        let components =
            value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(
                separatedBy: allowed.inverted
            )
        var result = components.joined(separator: "_")
        while result.contains("__") {
            result = result.replacingOccurrences(
                of: "__",
                with: "_"
            )
        }

        return result.trimmingCharacters(
            in: CharacterSet(charactersIn: "._-")
        )
    }

    /// Creates a unique object path under the server-provided prefix.
    ///
    /// - Parameters:
    ///   - prefix: The server-authorized object prefix.
    ///   - fileName: The validated filename.
    ///
    /// - Returns: The complete upload object path.
    func makeObjectKey(
        prefix: String,
        fileName: String
    ) -> String {
        let milliseconds = Int64(
            dateGenerator().timeIntervalSince1970 * 1_000
        )
        let identifier = identifierGenerator().lowercased()
        return "\(prefix)\(milliseconds)_\(identifier)_\(fileName)"
    }

    /// Returns an upload source's byte count.
    ///
    /// - Parameter source: The data or local file to upload.
    ///
    /// - Returns: The data or file size, in bytes.
    ///
    /// - Throws: A file system error if local file attributes cannot be read.
    func sourceByteCount(
        _ source: StorageUploadSource
    ) throws -> Int64 {
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

    /// Returns display dimensions for upload logging.
    ///
    /// - Parameters:
    ///   - source: The upload data or file.
    ///   - mediaType: The image or video metadata type.
    ///
    /// - Returns: The dimensions, or `--` if unavailable.
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

    /// Reads image dimensions from metadata.
    ///
    /// - Parameter source: The encoded image data or local image file.
    ///
    /// - Returns: The image dimensions, or `--` if metadata is unavailable.
    func readImageResolution(
        _ source: StorageUploadSource
    ) throws -> String {
        let imageSource: CGImageSource?
        switch source {
        case .data(let data):
            imageSource = CGImageSourceCreateWithData(
                data as CFData,
                nil
            )
        case .file(let fileURL):
            imageSource = CGImageSourceCreateWithURL(
                fileURL as CFURL,
                nil
            )
        }

        guard let imageSource,
            let properties = CGImageSourceCopyPropertiesAtIndex(
                imageSource,
                0,
                nil
            ) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            return "--"
        }

        return formatResolution(
            width: width.intValue,
            height: height.intValue
        )
    }

    /// Reads a video's oriented display dimensions.
    ///
    /// - Parameter source: The video upload source. In-memory video dimensions are not read.
    ///
    /// - Returns: The dimensions, or `--` for nonfiles or missing video.
    ///
    /// - Throws: A media error if video metadata or transforms cannot be loaded.
    func readVideoResolution(
        _ source: StorageUploadSource
    ) async throws -> String {
        guard case .file(let fileURL) = source else {
            return "--"
        }

        let asset = AVURLAsset(url: fileURL)
        guard
            let track = try await asset.loadTracks(
                withMediaType: .video
            ).first
        else {
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

    /// Formats valid media dimensions for logging.
    ///
    /// - Parameters:
    ///   - width: The width, in pixels.
    ///   - height: The height, in pixels.
    ///
    /// - Returns: The dimensions, or `--` if either dimension is nonpositive.
    func formatResolution(
        width: Int,
        height: Int
    ) -> String {
        guard width > 0, height > 0 else {
            return "--"
        }
        return "\(width) × \(height)"
    }

    /// Formats a file size with readable units.
    ///
    /// - Parameter byteCount: The file size, in bytes.
    ///
    /// - Returns: The size in B, KB, MB, or GB.
    func formatByteCount(
        _ byteCount: Int64
    ) -> String {
        let count = Double(byteCount)
        if byteCount < 1_024 {
            return "\(byteCount) B"
        }
        if byteCount < 1_024 * 1_024 {
            return String(
                format: "%.1f KB",
                count / 1_024
            )
        }
        if byteCount < 1_024 * 1_024 * 1_024 {
            return String(
                format: "%.2f MB",
                count / (1_024 * 1_024)
            )
        }
        return String(
            format: "%.2f GB",
            count / (1_024 * 1_024 * 1_024)
        )
    }

    /// Formats an operation duration in milliseconds or seconds.
    ///
    /// - Parameter startedAt: The operation start time.
    ///
    /// - Returns: The formatted duration.
    func formatDuration(
        since startedAt: Date
    ) -> String {
        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        if milliseconds < 1_000 {
            return "\(milliseconds) ms"
        }
        return String(
            format: "%.2f s",
            Double(milliseconds) / 1_000
        )
    }

    /// Logs an upload failure and its duration.
    ///
    /// - Parameters:
    ///   - error: The upload error to log.
    ///   - startedAt: The upload operation's start time.
    func logUploadFailure(
        _ error: XmaxError,
        startedAt: Date
    ) {
        XmaxLogger.storage.error(
            message: "上传失败 (Upload Failed)\n"
                + "├─ \(XmaxLogger.localized("错误码：", "Error Code: "))\(error.code.rawValue)\n"
                + "├─ \(XmaxLogger.localized("原因：", "Reason: "))\(error.message)\n"
                + "└─ \(XmaxLogger.localized("耗时：", "Duration: "))\(formatDuration(since: startedAt))"
        )
    }

    /// Trims surrounding whitespace from optional text.
    ///
    /// - Parameter value: The optional text to normalize.
    ///
    /// - Returns: The trimmed string, preserving `nil`.
    func normalizedString(
        _ value: String?
    ) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns nonempty text after trimming.
    ///
    /// - Parameter value: The optional field to validate.
    ///
    /// - Returns: The nonempty field, or `nil` if missing or whitespace-only.
    func requiredString(
        _ value: String?
    ) -> String? {
        guard let value = normalizedString(value), !value.isEmpty else {
            return nil
        }
        return value
    }

    /// Checks for an HTTP or HTTPS URL with a valid host.
    ///
    /// - Parameter url: The URL to check.
    ///
    /// - Returns: `true` if scheme and host are valid.
    func isHTTPURL(
        _ url: URL
    ) -> Bool {
        let scheme = url.scheme?.lowercased()
        return (scheme == "https" || scheme == "http")
            && url.host?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty == false
    }
}
