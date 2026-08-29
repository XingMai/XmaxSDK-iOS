import Foundation
import PhotosUI
import UniformTypeIdentifiers

extension RealtimeViewController: PHPickerViewControllerDelegate,
    UIAdaptivePresentationControllerDelegate {
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
                let localURL = try RealtimeReferenceFileImporter.copyToCache(
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

    func presentationControllerDidDismiss(
        _ presentationController: UIPresentationController
    ) {
        finishReferencePicking(localURL: nil)
    }

}
