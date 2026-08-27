import Foundation
import PhotosUI
import UniformTypeIdentifiers

extension RealtimeViewController: PHPickerViewControllerDelegate {
    func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        picker.dismiss(animated: true)
        guard let result = results.first else {
            finishReferencePicking(localURL: nil)
            return
        }

        let provider = result.itemProvider
        let typeIdentifier = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .image) == true
        } ?? UTType.image.identifier
        let preferredExtension = UTType(typeIdentifier)?
            .preferredFilenameExtension

        provider.loadFileRepresentation(
            forTypeIdentifier: typeIdentifier
        ) { [weak self] sourceURL, error in
            guard let self else { return }
            guard let sourceURL else {
                DispatchQueue.main.async {
                    self.finishReferencePicking(
                        localURL: nil,
                        error: error ?? RealtimeReferenceImportError.missingFile
                    )
                }
                return
            }

            do {
                let localURL = try Self.copyReferenceToCache(
                    sourceURL,
                    preferredExtension: preferredExtension
                )
                DispatchQueue.main.async {
                    self.finishReferencePicking(localURL: localURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.finishReferencePicking(
                        localURL: nil,
                        error: error
                    )
                }
            }
        }
    }

    private nonisolated static func copyReferenceToCache(
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

private enum RealtimeReferenceImportError: Error {
    case missingFile
}
