import Foundation

/// 文件存储公共入口，负责将服务层能力转换为公开 API。
final class XmaxStorageManager: XmaxStorageManaging, Sendable {

    // 服务层组件
    private let storageService: any StorageServicing

    init(storageService: any StorageServicing) {
        self.storageService = storageService
    }

    convenience init(apiService: any ApiServicing) {
        self.init(
            storageService: StorageService(
                apiService: apiService,
                storageManager: StorageManager()
            )
        )
    }

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
