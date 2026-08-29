import Combine
import Foundation
import XmaxSDK

@MainActor
final class RealtimeReferenceStore: ObservableObject {

    // 参考图数据
    @Published private(set) var referencesByCategory: [
        String: [RealtimeReferenceCatalog.Item]
    ]
    @Published var selectedReferenceID: String?
    @Published private(set) var promptReference: RealtimeReferenceCatalog.Item?

    // 错误状态
    @Published private(set) var errorMessage: String?

    // 上传任务
    private var uploadRequestIDs: [String: UUID] = [:]
    private var uploadTasks: [String: Task<Void, Never>] = [:]

    init() {
        referencesByCategory = Dictionary(
            grouping: RealtimeReferenceCatalog.load().items,
            by: \.categoryID
        )
    }

    deinit {
        uploadTasks.values.forEach { $0.cancel() }
    }

    func references(
        for categoryID: String
    ) -> [RealtimeReferenceCatalog.Item] {
        referencesByCategory[categoryID] ?? []
    }

    func addReference(localURL: URL, categoryID: String) {
        let reference = RealtimeReferenceCatalog.Item(
            categoryID: categoryID,
            iconURL: localURL,
            prompt: RealtimeReferenceCatalog.prompt(for: categoryID)
        )
        referencesByCategory[categoryID, default: []].insert(reference, at: 0)
        selectedReferenceID = reference.id
        startUpload(reference)
    }

    func setPromptReference(localURL: URL) {
        if let promptReference {
            cancelUpload(promptReference)
        }
        let reference = RealtimeReferenceCatalog.Item(
            categoryID: "free",
            iconURL: localURL,
            prompt: ""
        )
        promptReference = reference
        startUpload(reference)
    }

    func select(_ reference: RealtimeReferenceCatalog.Item) {
        if reference.uploadState == .failed {
            startUpload(reference)
            return
        }
        selectedReferenceID = selectedReferenceID == reference.id
            ? nil
            : reference.id
    }

    func handlePromptReferenceAction() -> Bool {
        guard let promptReference else {
            return true
        }

        switch promptReference.uploadState {
        case .ready:
            cancelUpload(promptReference)
            self.promptReference = nil
        case .uploading:
            break
        case .failed:
            startUpload(promptReference)
        }
        return false
    }

    func clearError() {
        errorMessage = nil
    }

    func showImportError() {
        errorMessage = "读取照片失败，请重试"
    }

    func cancelUploads() {
        uploadTasks.values.forEach { $0.cancel() }
        uploadTasks.removeAll()
        uploadRequestIDs.removeAll()
    }

    private func startUpload(
        _ reference: RealtimeReferenceCatalog.Item
    ) {
        cancelUpload(reference)

        reference.uploadState = .uploading
        let requestID = UUID()
        uploadRequestIDs[reference.id] = requestID

        let apiKey = UserDefaults.standard.string(
            forKey: RealtimeConst.apiKeyStorageKey
        ) ?? ""
        let fileURL = reference.iconURL
        uploadTasks[reference.id] = Task { [weak self, reference] in
            do {
                let client = XmaxClient(
                    configuration: XmaxConfiguration(
                        apiKey: apiKey,
                        loggerOptions: .business
                    )
                )
                let storageManager = try client.createStorageManager()
                let uploaded = try await storageManager.uploadImage(
                    at: fileURL,
                    contentType: nil,
                    progress: nil
                )
                try Task.checkCancellation()
                self?.finishUpload(
                    reference,
                    requestID: requestID,
                    result: .success(uploaded.url)
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishUpload(
                    reference,
                    requestID: requestID,
                    result: .failure(error)
                )
            }
        }
    }

    private func finishUpload(
        _ reference: RealtimeReferenceCatalog.Item,
        requestID: UUID,
        result: Result<URL, Error>
    ) {
        guard uploadRequestIDs[reference.id] == requestID else {
            return
        }
        uploadRequestIDs[reference.id] = nil
        uploadTasks[reference.id] = nil

        switch result {
        case let .success(remoteURL):
            reference.referencePath = remoteURL.absoluteString
            reference.uploadState = .ready
        case .failure:
            reference.uploadState = .failed
            errorMessage = "参考图上传失败，点击图片可重试"
        }
        if reference === promptReference {
            promptReference = reference
        }
    }

    private func cancelUpload(
        _ reference: RealtimeReferenceCatalog.Item
    ) {
        uploadTasks[reference.id]?.cancel()
        uploadTasks[reference.id] = nil
        uploadRequestIDs[reference.id] = nil
    }
}
