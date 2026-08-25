import Foundation
import XCTest
@testable import XmaxSDK

final class StorageServiceTests: XCTestCase {
    func testUploadImageFetchesCredentialAndBuildsSanitizedObjectKey() async throws {
        let apiService = StorageApiServiceStub(
            responses: [.success(Self.storageCredentialPayload())]
        )
        let storageProvider = StorageProviderStub()
        let service = makeService(
            apiService: apiService,
            storageProvider: storageProvider
        )

        let result = try await service.uploadImage(
            data: Data("image-data".utf8),
            fileName: " .示例 图_.png ",
            contentType: " image/png "
        )

        XCTAssertEqual(
            apiService.requests,
            [StorageApiRequest(method: .get, path: "/cos/sts", body: nil)]
        )
        let upload = try XCTUnwrap(storageProvider.uploads.first)
        XCTAssertEqual(upload.source, .data(Data("image-data".utf8)))
        XCTAssertEqual(
            upload.objectKey,
            "uploads/1700000000000_fixed-id_示例_图_.png"
        )
        XCTAssertEqual(upload.contentType, "image/png")
        XCTAssertEqual(
            upload.configuration,
            StorageConfiguration(
                bucket: "bucket-1250000000",
                region: "ap-shanghai",
                endpoint: "",
                credential: StorageCredential(
                    accessKeyID: "access-key",
                    secretAccessKey: "secret-key",
                    sessionToken: "session-token"
                )
            )
        )
        XCTAssertEqual(result.objectKey, upload.objectKey)
        XCTAssertEqual(result.etag, "etag")
    }

    func testUploadImageSafetyCheckUsesCheckedURL() async throws {
        let apiService = StorageApiServiceStub(
            responses: [
                .success(Self.storageCredentialPayload()),
                .success(
                    Data(
                        #"{"safe":true,"url":" https://safe.example.com/image.png "}"#.utf8
                    )
                )
            ]
        )
        let storageProvider = StorageProviderStub()
        let service = makeService(
            apiService: apiService,
            storageProvider: storageProvider
        )

        let result = try await service.uploadImageWithSafetyCheck(
            data: Data("image-data".utf8),
            fileName: "image.png",
            contentType: "image/png"
        )

        XCTAssertEqual(
            result.url.absoluteString,
            "https://safe.example.com/image.png"
        )
        XCTAssertEqual(apiService.requests.count, 2)
        let checkRequest = apiService.requests[1]
        XCTAssertEqual(checkRequest.method, .post)
        XCTAssertEqual(checkRequest.path, "/cos/image/check")
        let body = try XCTUnwrap(checkRequest.body)
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: body) as? [String: String],
            ["url": "https://upload.example.com/file"]
        )
    }

    func testUploadImageRejectsUnsafeResult() async {
        let apiService = StorageApiServiceStub(
            responses: [
                .success(Self.storageCredentialPayload()),
                .success(Data(#"{"safe":false}"#.utf8))
            ]
        )
        let service = makeService(
            apiService: apiService,
            storageProvider: StorageProviderStub()
        )

        do {
            _ = try await service.uploadImageWithSafetyCheck(
                data: Data("image-data".utf8),
                fileName: "image.png",
                contentType: "image/png"
            )
            XCTFail("Expected unsafe image to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .unsafeImage,
                    message: "The image did not pass the safety check"
                )
            )
        }
    }

    func testUploadRejectsInvalidCredentialPayload() async {
        let apiService = StorageApiServiceStub(
            responses: [
                .success(
                    Data(
                        #"""
                        {
                            "bucket": "bucket",
                            "region": "region",
                            "endpoint": "",
                            "prefix": "uploads/",
                            "credentials": { "accessKeyId": "" }
                        }
                        """#.utf8
                    )
                )
            ]
        )
        let storageProvider = StorageProviderStub()
        let service = makeService(
            apiService: apiService,
            storageProvider: storageProvider
        )

        do {
            _ = try await service.uploadVideo(
                data: Data("video-data".utf8),
                fileName: "video.mp4",
                contentType: "video/mp4"
            )
            XCTFail("Expected invalid credential payload to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .apiError,
                    message: "Invalid storage credential payload"
                )
            )
            XCTAssertTrue(storageProvider.uploads.isEmpty)
        }
    }

    func testUploadVideoFileInfersContentType() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("MOV")
        try Data("video-data".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiService = StorageApiServiceStub(
            responses: [.success(Self.storageCredentialPayload())]
        )
        let storageProvider = StorageProviderStub()
        let service = makeService(
            apiService: apiService,
            storageProvider: storageProvider
        )

        _ = try await service.uploadVideoFile(fileURL: fileURL)

        let upload = try XCTUnwrap(storageProvider.uploads.first)
        XCTAssertEqual(upload.source, .file(fileURL))
        XCTAssertEqual(upload.contentType, "video/quicktime")
    }

    func testUploadValidatesInputBeforeRequestingCredential() async {
        let apiService = StorageApiServiceStub(responses: [])
        let storageProvider = StorageProviderStub()
        let service = makeService(
            apiService: apiService,
            storageProvider: storageProvider
        )

        do {
            _ = try await service.uploadImage(
                data: Data(),
                fileName: "image.png",
                contentType: "image/png"
            )
            XCTFail("Expected empty image data to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Image data cannot be empty"
                )
            )
            XCTAssertTrue(apiService.requests.isEmpty)
            XCTAssertTrue(storageProvider.uploads.isEmpty)
        }
    }

    func testUploadFileRejectsUnknownExtensionBeforeCredentialRequest() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("unknown")
        try Data("value".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let apiService = StorageApiServiceStub(responses: [])
        let service = makeService(
            apiService: apiService,
            storageProvider: StorageProviderStub()
        )

        do {
            _ = try await service.uploadImageFile(fileURL: fileURL)
            XCTFail("Expected content type inference to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .invalidConfiguration,
                    message: "Unable to infer image content type from file extension"
                )
            )
            XCTAssertTrue(apiService.requests.isEmpty)
        }
    }

    func testDownloadDelegatesValidatedURLsAndProgress() async throws {
        let apiService = StorageApiServiceStub(responses: [])
        let storageProvider = StorageProviderStub()
        let service = makeService(
            apiService: apiService,
            storageProvider: storageProvider
        )
        let remoteURL = URL(string: "https://example.com/video.mp4")!
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("video.mp4")
        let progress: StorageProgressListener = { _, _ in }

        let result = try await service.downloadVideo(
            remoteURL: remoteURL,
            destinationURL: destinationURL,
            progress: progress
        )

        XCTAssertEqual(
            storageProvider.downloads,
            [
                StorageDownloadRecord(
                    remoteURL: remoteURL,
                    destinationURL: destinationURL,
                    hasProgress: true
                )
            ]
        )
        XCTAssertEqual(result.fileURL, destinationURL)
    }
}

private extension StorageServiceTests {
    static func storageCredentialPayload() -> Data {
        Data(
            #"""
            {
                "bucket": " bucket-1250000000 ",
                "region": " ap-shanghai ",
                "endpoint": " ",
                "prefix": " uploads/ ",
                "credentials": {
                    "accessKeyId": " access-key ",
                    "secretAccessKey": " secret-key ",
                    "sessionToken": " session-token "
                }
            }
            """#.utf8
        )
    }

    func makeService(
        apiService: StorageApiServiceStub,
        storageProvider: StorageProviderStub
    ) -> StorageService {
        StorageService(
            apiService: apiService,
            storageProvider: storageProvider,
            dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) },
            identifierProvider: { "fixed-id" }
        )
    }
}

private struct StorageApiRequest: Equatable, Sendable {
    let method: ApiMethod
    let path: String
    let body: Data?
}

private final class StorageApiServiceStub: ApiServicing, @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var storedResponses: [Result<Data, XmaxError>]
    private var storedRequests: [StorageApiRequest] = []

    init(responses: [Result<Data, XmaxError>]) {
        storedResponses = responses
    }

    var requests: [StorageApiRequest] {
        lock.withLock { storedRequests }
    }

    func request<Response: Decodable & Sendable>(
        _ method: ApiMethod,
        path: String,
        body: Data?,
        as responseType: Response.Type
    ) async throws -> Response {
        let result: Result<Data, XmaxError> = try lock.withLock {
            storedRequests.append(
                StorageApiRequest(method: method, path: path, body: body)
            )
            guard !storedResponses.isEmpty else {
                throw XmaxError(
                    code: .internalError,
                    message: "Missing test API response"
                )
            }
            return storedResponses.removeFirst()
        }
        return try JSONDecoder().decode(responseType, from: result.get())
    }
}

private struct StorageUploadRecord: Equatable, Sendable {
    let source: StorageUploadSource
    let objectKey: String
    let contentType: String
    let configuration: StorageConfiguration
    let hasProgress: Bool
}

private struct StorageDownloadRecord: Equatable, Sendable {
    let remoteURL: URL
    let destinationURL: URL
    let hasProgress: Bool
}

private final class StorageProviderStub: StorageProviding, @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var storedUploads: [StorageUploadRecord] = []
    private var storedDownloads: [StorageDownloadRecord] = []

    var uploads: [StorageUploadRecord] {
        lock.withLock { storedUploads }
    }

    var downloads: [StorageDownloadRecord] {
        lock.withLock { storedDownloads }
    }

    func upload(
        source: StorageUploadSource,
        objectKey: String,
        contentType: String,
        configuration: StorageConfiguration,
        progress: StorageProgressListener?
    ) async throws -> StoredFile {
        lock.withLock {
            storedUploads.append(
                StorageUploadRecord(
                    source: source,
                    objectKey: objectKey,
                    contentType: contentType,
                    configuration: configuration,
                    hasProgress: progress != nil
                )
            )
        }
        return StoredFile(
            url: URL(string: "https://upload.example.com/file")!,
            objectKey: objectKey,
            etag: "etag"
        )
    }

    func download(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile {
        lock.withLock {
            storedDownloads.append(
                StorageDownloadRecord(
                    remoteURL: remoteURL,
                    destinationURL: destinationURL,
                    hasProgress: progress != nil
                )
            )
        }
        return DownloadedFile(fileURL: destinationURL, byteCount: 100)
    }
}
