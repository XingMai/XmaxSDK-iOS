import Foundation

enum RealtimeReferenceFileImporter {
    nonisolated static func copyToCache(
        _ sourceURL: URL,
        preferredExtension: String?
    ) throws -> URL {
        let fileManager = FileManager.default
        let cacheRoot = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = cacheRoot.appendingPathComponent(
            "RealtimeReferences",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let fileExtension = sourceURL.pathExtension.isEmpty
            ? preferredExtension ?? "jpg"
            : sourceURL.pathExtension
        let destinationURL = directoryURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
}

enum RealtimeReferenceImportError: Error {
    case missingFile
}
