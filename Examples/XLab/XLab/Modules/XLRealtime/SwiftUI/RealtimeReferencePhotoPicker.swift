import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum RealtimeReferencePhotoPickerResult: Sendable {
    case selected(URL)
    case cancelled
    case failed
}

struct RealtimeReferencePhotoPicker: UIViewControllerRepresentable {
    typealias Completion = @MainActor @Sendable (
        RealtimeReferencePhotoPickerResult
    ) -> Void

    let completion: Completion

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(
        context: Context
    ) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: PHPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let completion: Completion

        init(completion: @escaping Completion) {
            self.completion = completion
        }

        func picker(
            _ picker: PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            guard let result = results.first else {
                Task { @MainActor in
                    completion(.cancelled)
                }
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
            ) { [completion] sourceURL, error in
                let result: RealtimeReferencePhotoPickerResult
                do {
                    guard let sourceURL else {
                        throw error ?? RealtimeReferenceImportError.missingFile
                    }
                    let localURL = try RealtimeReferenceFileImporter.copyToCache(
                        sourceURL,
                        preferredExtension: preferredExtension
                    )
                    result = .selected(localURL)
                } catch {
                    result = .failed
                }
                Task { @MainActor in
                    completion(result)
                }
            }
        }
    }
}
