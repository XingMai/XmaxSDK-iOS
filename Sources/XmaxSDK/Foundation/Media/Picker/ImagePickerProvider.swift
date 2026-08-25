import Foundation
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// 使用系统 PHPicker 选择单张图片。
@MainActor
final class ImagePickerProvider: ImagePicking {
    func pickImage(
        from presentingViewController: UIViewController
    ) async throws -> Data {
        guard presentingViewController.viewIfLoaded?.window != nil else {
            throw XmaxError(
                code: .invalidConfiguration,
                message: "Image picker presenter must be visible"
            )
        }

        let operation = ImagePickerOperation(
            presentingViewController: presentingViewController
        )
        return try await operation.value()
    }
}

/// 持有一次系统图片选择流程并桥接为异步调用。
@MainActor
private final class ImagePickerOperation: NSObject,
    PHPickerViewControllerDelegate {

    // 平台资源
    private weak var presentingViewController: UIViewController?
    private let picker: PHPickerViewController
    private var loadingProgress: Progress?

    // 运行状态
    private var continuation: CheckedContinuation<Data, Error>?
    private var completed = false

    init(presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        picker = PHPickerViewController(configuration: configuration)
        super.init()
        picker.delegate = self
    }

    func value() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                presentingViewController?.present(
                    picker,
                    animated: true
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            finish(.failure(XmaxError(
                code: .apiError,
                message: "No image was selected"
            )))
            return
        }

        loadingProgress = provider.loadDataRepresentation(
            forTypeIdentifier: UTType.image.identifier
        ) { [weak self] data, error in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if let error {
                    self.finish(.failure(XmaxError.from(error)))
                } else if let data, !data.isEmpty {
                    self.finish(.success(data))
                } else {
                    self.finish(.failure(XmaxError(
                        code: .mediaError,
                        message: "Selected image contains no data"
                    )))
                }
            }
        }
    }
}

private extension ImagePickerOperation {
    func cancel() {
        loadingProgress?.cancel()
        picker.dismiss(animated: true)
        finish(.failure(XmaxError(
            code: .cancelled,
            message: "Image selection was cancelled"
        )))
    }

    func finish(_ result: Result<Data, Error>) {
        guard !completed else {
            return
        }
        completed = true
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
