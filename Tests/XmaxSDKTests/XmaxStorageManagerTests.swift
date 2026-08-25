import Foundation
import XCTest
@testable import XmaxSDK

final class XmaxStorageManagerTests: XCTestCase {
    func testUploadImageDelegatesDataAndConvertsProgressAndResult() async throws {
        let service = XmaxStorageServiceStub()
        let manager = XmaxStorageManager(storageService: service)
        let progressRecorder = XmaxStorageProgressRecorder()
        let data = Data("image".utf8)

        let result = try await manager.uploadImage(
            data,
            fileName: "image.png",
            contentType: "image/png",
            progress: progressRecorder.handler
        )

        XCTAssertEqual(
            service.calls,
            [
                .uploadImage(
                    data: data,
                    fileName: "image.png",
                    contentType: "image/png",
                    hasProgress: true
                )
            ]
        )
        XCTAssertEqual(
            progressRecorder.values,
            [XmaxStorageProgressValue(completed: 25, total: 100)]
        )
        XCTAssertEqual(
            result,
            XmaxUploadedFile(
                url: URL(string: "https://example.com/file")!,
                objectKey: "uploads/file",
                etag: "etag"
            )
        )
    }

    func testUploadImageFileWithSafetyCheckUsesNativeURL() async throws {
        let service = XmaxStorageServiceStub()
        let manager = XmaxStorageManager(storageService: service)
        let fileURL = URL(fileURLWithPath: "/tmp/image.heic")

        _ = try await manager.uploadImageWithSafetyCheck(
            at: fileURL,
            contentType: nil
        )

        XCTAssertEqual(
            service.calls,
            [
                .uploadImageFileWithSafetyCheck(
                    fileURL: fileURL,
                    contentType: nil,
                    hasProgress: false
                )
            ]
        )
    }

    func testUploadVideoFileDelegatesOptionalContentType() async throws {
        let service = XmaxStorageServiceStub()
        let manager = XmaxStorageManager(storageService: service)
        let fileURL = URL(fileURLWithPath: "/tmp/video.mov")

        _ = try await manager.uploadVideo(
            at: fileURL,
            contentType: "video/quicktime"
        )

        XCTAssertEqual(
            service.calls,
            [
                .uploadVideoFile(
                    fileURL: fileURL,
                    contentType: "video/quicktime",
                    hasProgress: false
                )
            ]
        )
    }

    func testDownloadImageDelegatesURLsAndConvertsResult() async throws {
        let service = XmaxStorageServiceStub()
        let manager = XmaxStorageManager(storageService: service)
        let remoteURL = URL(string: "https://example.com/image.png")!
        let destinationURL = URL(fileURLWithPath: "/tmp/image.png")

        let result = try await manager.downloadImage(
            from: remoteURL,
            to: destinationURL
        )

        XCTAssertEqual(
            service.calls,
            [
                .downloadImage(
                    remoteURL: remoteURL,
                    destinationURL: destinationURL,
                    hasProgress: false
                )
            ]
        )
        XCTAssertEqual(
            result,
            XmaxDownloadedFile(
                fileURL: destinationURL,
                byteCount: 512
            )
        )
    }

    func testManagerMapsUnknownServiceErrorToXmaxError() async {
        let service = XmaxStorageServiceStub(
            error: NSError(
                domain: "XmaxStorageManagerTests",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected failure"]
            )
        )
        let manager = XmaxStorageManager(storageService: service)

        do {
            _ = try await manager.uploadVideo(
                Data("video".utf8),
                fileName: "video.mp4",
                contentType: "video/mp4"
            )
            XCTFail("Expected storage manager operation to fail")
        } catch {
            XCTAssertEqual(
                error as? XmaxError,
                XmaxError(
                    code: .internalError,
                    message: "Unexpected failure"
                )
            )
        }
    }
}

private enum XmaxStorageServiceCall: Equatable, Sendable {
    case uploadImage(
        data: Data,
        fileName: String,
        contentType: String,
        hasProgress: Bool
    )
    case uploadImageFile(
        fileURL: URL,
        contentType: String?,
        hasProgress: Bool
    )
    case uploadImageWithSafetyCheck(
        data: Data,
        fileName: String,
        contentType: String,
        hasProgress: Bool
    )
    case uploadImageFileWithSafetyCheck(
        fileURL: URL,
        contentType: String?,
        hasProgress: Bool
    )
    case uploadVideo(
        data: Data,
        fileName: String,
        contentType: String,
        hasProgress: Bool
    )
    case uploadVideoFile(
        fileURL: URL,
        contentType: String?,
        hasProgress: Bool
    )
    case downloadImage(
        remoteURL: URL,
        destinationURL: URL,
        hasProgress: Bool
    )
    case downloadVideo(
        remoteURL: URL,
        destinationURL: URL,
        hasProgress: Bool
    )
}

private final class XmaxStorageServiceStub:
    StorageServicing,
    @unchecked Sendable {

    // 测试配置
    private let error: (any Error)?

    // 并发状态
    private let lock = NSLock()
    private var storedCalls: [XmaxStorageServiceCall] = []

    init(error: (any Error)? = nil) {
        self.error = error
    }

    var calls: [XmaxStorageServiceCall] {
        lock.withLock { storedCalls }
    }

    func uploadImage(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile {
        try uploadResult(
            call: .uploadImage(
                data: data,
                fileName: fileName,
                contentType: contentType,
                hasProgress: progress != nil
            ),
            progress: progress
        )
    }

    func uploadImageFile(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile {
        try uploadResult(
            call: .uploadImageFile(
                fileURL: fileURL,
                contentType: contentType,
                hasProgress: progress != nil
            ),
            progress: progress
        )
    }

    func uploadImageWithSafetyCheck(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile {
        try uploadResult(
            call: .uploadImageWithSafetyCheck(
                data: data,
                fileName: fileName,
                contentType: contentType,
                hasProgress: progress != nil
            ),
            progress: progress
        )
    }

    func uploadImageFileWithSafetyCheck(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile {
        try uploadResult(
            call: .uploadImageFileWithSafetyCheck(
                fileURL: fileURL,
                contentType: contentType,
                hasProgress: progress != nil
            ),
            progress: progress
        )
    }

    func uploadVideo(
        data: Data,
        fileName: String,
        contentType: String,
        progress: StorageProgressListener?
    ) async throws -> StoredFile {
        try uploadResult(
            call: .uploadVideo(
                data: data,
                fileName: fileName,
                contentType: contentType,
                hasProgress: progress != nil
            ),
            progress: progress
        )
    }

    func uploadVideoFile(
        fileURL: URL,
        contentType: String?,
        progress: StorageProgressListener?
    ) async throws -> StoredFile {
        try uploadResult(
            call: .uploadVideoFile(
                fileURL: fileURL,
                contentType: contentType,
                hasProgress: progress != nil
            ),
            progress: progress
        )
    }

    func downloadImage(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile {
        try downloadResult(
            call: .downloadImage(
                remoteURL: remoteURL,
                destinationURL: destinationURL,
                hasProgress: progress != nil
            ),
            destinationURL: destinationURL,
            progress: progress
        )
    }

    func downloadVideo(
        remoteURL: URL,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) async throws -> DownloadedFile {
        try downloadResult(
            call: .downloadVideo(
                remoteURL: remoteURL,
                destinationURL: destinationURL,
                hasProgress: progress != nil
            ),
            destinationURL: destinationURL,
            progress: progress
        )
    }
}

private extension XmaxStorageServiceStub {
    func uploadResult(
        call: XmaxStorageServiceCall,
        progress: StorageProgressListener?
    ) throws -> StoredFile {
        try record(call)
        progress?(25, 100)
        return StoredFile(
            url: URL(string: "https://example.com/file")!,
            objectKey: "uploads/file",
            etag: "etag"
        )
    }

    func downloadResult(
        call: XmaxStorageServiceCall,
        destinationURL: URL,
        progress: StorageProgressListener?
    ) throws -> DownloadedFile {
        try record(call)
        progress?(512, 512)
        return DownloadedFile(
            fileURL: destinationURL,
            byteCount: 512
        )
    }

    func record(_ call: XmaxStorageServiceCall) throws {
        try lock.withLock {
            storedCalls.append(call)
            if let error {
                throw error
            }
        }
    }
}

private struct XmaxStorageProgressValue: Equatable, Sendable {
    let completed: Int64
    let total: Int64
}

private final class XmaxStorageProgressRecorder: @unchecked Sendable {

    // 并发状态
    private let lock = NSLock()
    private var storedValues: [XmaxStorageProgressValue] = []

    var values: [XmaxStorageProgressValue] {
        lock.withLock { storedValues }
    }

    var handler: XmaxStorageProgressHandler {
        { [weak self] progress in
            self?.lock.withLock {
                self?.storedValues.append(
                    XmaxStorageProgressValue(
                        completed: progress.completedUnitCount,
                        total: progress.totalUnitCount
                    )
                )
            }
        }
    }
}
