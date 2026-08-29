import PhotosUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class RealtimeLocalMediaPicker: NSObject {
    typealias Completion = (Result<RealtimeLocalInput?, Error>) -> Void

    private var completion: Completion?
    private var selectedKind: RealtimeLocalInput.Kind?

    func present(
        from viewController: UIViewController,
        kind: RealtimeLocalInput.Kind,
        completion: @escaping Completion
    ) {
        guard viewController.presentedViewController == nil else {
            completion(.success(nil))
            return
        }

        self.completion = completion
        selectedKind = kind

        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = kind == .image ? .images : .videos
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        viewController.present(picker, animated: true)
        picker.presentationController?.delegate = self
    }

    private func finishAfterInteractiveDismissal() {
        let completion = completion
        self.completion = nil
        selectedKind = nil
        completion?(.success(nil))
    }

    private func loadImage(
        from provider: NSItemProvider,
        picker: PHPickerViewController
    ) {
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            let image = object as? UIImage
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    finish(.failure(error), dismissing: picker)
                    return
                }
                guard let image else {
                    finish(
                        .failure(
                            RealtimeLocalMediaPickerError.unreadableImage
                        ),
                        dismissing: picker
                    )
                    return
                }
                finish(.success(.image(image)), dismissing: picker)
            }
        }
    }

    private func loadVideo(
        from provider: NSItemProvider,
        picker: PHPickerViewController
    ) {
        let typeIdentifier = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .movie) == true
        } ?? UTType.movie.identifier
        let preferredExtension = UTType(typeIdentifier)?
            .preferredFilenameExtension

        provider.loadFileRepresentation(
            forTypeIdentifier: typeIdentifier
        ) { [weak self] sourceURL, error in
            guard let self else { return }
            guard let sourceURL else {
                Task { @MainActor [weak self] in
                    self?.finish(
                        .failure(
                            error ?? RealtimeLocalMediaPickerError.unreadableVideo
                        ),
                        dismissing: picker
                    )
                }
                return
            }

            do {
                let localURL = try Self.copyVideoToCache(
                    sourceURL,
                    preferredExtension: preferredExtension
                )
                Task { @MainActor [weak self] in
                    self?.finish(
                        .success(.video(localURL)),
                        dismissing: picker
                    )
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.finish(
                        .failure(error),
                        dismissing: picker
                    )
                }
            }
        }
    }

    private func finish(
        _ result: Result<RealtimeLocalInput?, Error>,
        dismissing picker: PHPickerViewController
    ) {
        let completion = completion
        self.completion = nil
        selectedKind = nil
        picker.dismiss(animated: true) {
            completion?(result)
        }
    }

    private nonisolated static func copyVideoToCache(
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
            "RealtimeInputs",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let fileExtension = sourceURL.pathExtension.isEmpty
            ? preferredExtension ?? "mov"
            : sourceURL.pathExtension
        let destinationURL = directoryURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
}

extension RealtimeLocalMediaPicker: PHPickerViewControllerDelegate {
    func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        guard let result = results.first else {
            finish(.success(nil), dismissing: picker)
            return
        }

        switch selectedKind {
        case .image:
            loadImage(
                from: result.itemProvider,
                picker: picker
            )
        case .video:
            loadVideo(
                from: result.itemProvider,
                picker: picker
            )
        case nil:
            finish(
                .failure(
                    RealtimeLocalMediaPickerError.missingSelectionKind
                ),
                dismissing: picker
            )
        }
    }
}

extension RealtimeLocalMediaPicker: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(
        _ presentationController: UIPresentationController
    ) {
        finishAfterInteractiveDismissal()
    }
}

private enum RealtimeLocalMediaPickerError: LocalizedError {
    case missingSelectionKind
    case unreadableImage
    case unreadableVideo

    var errorDescription: String? {
        switch self {
        case .missingSelectionKind:
            "无法识别本地素材类型，请重试"
        case .unreadableImage:
            "读取图片失败，请重试"
        case .unreadableVideo:
            "读取视频失败，请重试"
        }
    }
}
