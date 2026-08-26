import PhotosUI
import SnapKit
import UIKit
import UniformTypeIdentifiers
import XmaxSDK

final class RealtimeViewController: UIViewController, UIGestureRecognizerDelegate {

    private enum ReferencePickerDestination {
        case category(String)
        case prompt
    }

    // 本地配置
    private static let apiKeyStorageKey = "xlab.realtime.apiKey"
    private static let filePreviewTopOffset: CGFloat = 60
    private static let cameraVideoFormat = RealtimeVideoFormat(
        width: 832,
        height: 1472,
        fps: 24
    )

    // 实时资源
    private let localInput: RealtimeLocalInput?
    private let realtimeManager: any XmaxRealtimeManaging
    private var localMediaStream: RealtimeMediaStream?
    private var remoteRealtimeStream: RealtimeMediaStream?
    private var selectedReference: RealtimeReferenceCatalog.Item?
    private var currentGenerationContext: RealtimeContext?
    private var isGenerationRequested = false

    // 参考图状态
    private var referencePickerDestination: ReferencePickerDestination?
    private var promptReference: RealtimeReferenceCatalog.Item?
    private var isPickingReference = false
    private var referenceUploadRequestIDs: [String: UUID] = [:]

    // 异步任务
    private var localMediaOperationTask: Task<Void, Never>?
    private var generationOperationTask: Task<Void, Never>?
    private var stateListenerTask: Task<Void, Never>?
    private var referenceUploadTasks: [String: Task<Void, Never>] = [:]

    // 布局约束
    private var promptKeyboardBottomConstraint: Constraint?

    // 交互手势
    private lazy var keyboardDismissTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(
            target: self,
            action: #selector(dismissKeyboard)
        )
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    private lazy var keyboardDismissSwipeGesture: UISwipeGestureRecognizer = {
        let gesture = UISwipeGestureRecognizer(
            target: self,
            action: #selector(dismissKeyboard)
        )
        gesture.direction = .down
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    // 界面组件
    private lazy var previewView = RealtimePreviewBackdropView(
        usesFileLayout: localInput != nil
    )

    private lazy var controlPanelView: RealtimeControlPanelView = {
        let view = RealtimeControlPanelView()
        view.onBeginPromptEditing = { [weak self] text in
            self?.showPromptKeyboard(text: text)
        }
        view.onReferenceSelectionChanged = { [weak self] reference in
            self?.handleReferenceSelection(reference)
        }
        view.onAddReference = { [weak self] categoryID in
            self?.presentReferencePhotoPicker(
                destination: .category(categoryID)
            )
        }
        view.onRetryReferenceUpload = { [weak self] reference in
            self?.startReferenceUpload(reference)
        }
        view.onPromptReferenceAction = { [weak self] in
            self?.handlePromptReferenceAction()
        }
        view.onDisableGeneration = { [weak self] in
            guard let self else { return }
            selectedReference = nil
            disconnectGeneration()
        }
        return view
    }()

    private lazy var promptKeyboardView: RealtimePromptKeyboardView = {
        let view = RealtimePromptKeyboardView()
        view.isHidden = true
        view.onTextChange = { [weak self] text in
            self?.controlPanelView.setPromptText(text)
        }
        view.onSubmit = { [weak self] text in
            guard let self else { return }
            controlPanelView.setPromptText(text)
            promptKeyboardView.endEditing()
            submitPrompt(text)
        }
        view.onReferenceAction = { [weak self] in
            self?.handlePromptReferenceAction()
        }
        return view
    }()

    private lazy var switchCameraButton: RealtimeCameraSwitchButton = {
        let button = RealtimeCameraSwitchButton()
        button.isEnabled = false
        button.isHidden = localInput != nil
        button.addTarget(
            self,
            action: #selector(switchCamera(_:)),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var loadingOverlay = RealtimeLoadingOverlay()

    init(localInput: RealtimeLocalInput? = nil) {
        self.localInput = localInput
        realtimeManager = Self.makeRealtimeManager()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .black
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configurePreview()
        configureTopControls()
        configureControlPanel()
        configurePromptKeyboard()
        configureKeyboardDismissal()
        observeKeyboard()
        observeRealtimeState()
        startLocalMedia()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            stopLocalMedia()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configurePreview() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        previewView.snp.makeConstraints { make in
            make.horizontalEdges.equalToSuperview()
            if localInput == nil {
                make.top.equalToSuperview()
            } else {
                make.top.equalTo(view.safeAreaLayoutGuide)
                    .offset(Self.filePreviewTopOffset)
            }
        }

        previewView.addSubview(loadingOverlay)
        loadingOverlay.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func configureTopControls() {
        let backButton = UIButton(type: .custom)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(named: "realtime_nav_back"), for: .normal)
        backButton.imageView?.contentMode = .scaleAspectFit
        backButton.accessibilityLabel = "返回首页"
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        view.addSubview(backButton)

        view.addSubview(switchCameraButton)

        backButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.equalToSuperview().offset(12)
            make.size.equalTo(44)
        }
        switchCameraButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(6)
            make.trailing.equalToSuperview().inset(8)
            make.width.equalTo(58)
            make.height.equalTo(62)
        }
    }

    private func configureControlPanel() {
        controlPanelView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlPanelView)

        controlPanelView.snp.makeConstraints { make in
            make.horizontalEdges.bottom.equalToSuperview()
        }
        previewView.snp.makeConstraints { make in
            make.bottom.equalTo(controlPanelView.snp.top)
        }

    }

    private func configurePromptKeyboard() {
        view.addSubview(promptKeyboardView)
        promptKeyboardView.snp.makeConstraints { make in
            make.horizontalEdges.equalToSuperview()
            make.height.equalTo(RealtimePromptKeyboardView.preferredHeight)
            promptKeyboardBottomConstraint = make.bottom.equalToSuperview()
                .offset(RealtimePromptKeyboardView.preferredHeight)
                .constraint
        }
    }

    private func configureKeyboardDismissal() {
        view.addGestureRecognizer(keyboardDismissTapGesture)
        view.addGestureRecognizer(keyboardDismissSwipeGesture)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var touchedView = touch.view
        while let currentView = touchedView, currentView !== view {
            if currentView === promptKeyboardView ||
                currentView is UIControl ||
                currentView is UIScrollView {
                return false
            }
            touchedView = currentView.superview
        }
        return true
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidHide),
            name: UIResponder.keyboardDidHideNotification,
            object: nil
        )
    }

    private func observeRealtimeState() {
        let realtimeManager = realtimeManager
        stateListenerTask?.cancel()
        stateListenerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await realtimeManager.setStateListener { [weak self] state in
                self?.renderRealtimeState(state)
            }
        }
    }

    private func renderRealtimeState(_ state: RealtimeState) {
        switch state.connectionState {
        case .connecting, .connected:
            if isGenerationRequested {
                loadingOverlay.startLoading()
            }
        case .generating:
            guard isGenerationRequested else { return }
            previewView.showRealtime()
            loadingOverlay.hideLoading()
        case .idle, .disconnecting, .disconnected, .error:
            loadingOverlay.hideLoading()
        }
    }

    private func showPromptKeyboard(text: String) {
        promptKeyboardView.isHidden = false
        promptKeyboardView.alpha = 0
        promptKeyboardView.beginEditing(text: text)
    }

    private static func makeRealtimeManager() -> any XmaxRealtimeManaging {
        let apiKey = UserDefaults.standard.string(
            forKey: Self.apiKeyStorageKey
        ) ?? ""
        let client = XmaxClient(
            configuration: XmaxConfiguration(apiKey: apiKey)
        )
        return client.createRealtimeManager(
            options: RealtimeConfiguration(model: .x2_0)
        )
    }

    private func presentReferencePhotoPicker(
        destination: ReferencePickerDestination
    ) {
        guard !isPickingReference, presentedViewController == nil else {
            return
        }

        isPickingReference = true
        referencePickerDestination = destination
        view.endEditing(true)

        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func finishReferencePicking(
        localURL: URL?,
        error: (any Error)? = nil
    ) {
        let destination = referencePickerDestination
        referencePickerDestination = nil
        isPickingReference = false

        if error != nil {
            XLToast.show("读取照片失败，请重试", in: view)
            return
        }
        guard let localURL, let destination else { return }

        switch destination {
        case let .category(categoryID):
            let reference = RealtimeReferenceCatalog.Item(
                categoryID: categoryID,
                iconURL: localURL,
                prompt: RealtimeReferenceCatalog.prompt(
                    for: categoryID
                )
            )
            controlPanelView.insertReference(reference)
            startReferenceUpload(reference)
        case .prompt:
            if let promptReference {
                cancelReferenceUpload(promptReference)
            }
            let reference = RealtimeReferenceCatalog.Item(
                categoryID: "free",
                iconURL: localURL,
                prompt: ""
            )
            promptReference = reference
            renderPromptReference()
            startReferenceUpload(reference)
        }
    }

    private func handleReferenceSelection(
        _ reference: RealtimeReferenceCatalog.Item?
    ) {
        let previousReference = selectedReference
        selectedReference = reference
        guard let reference else {
            if previousReference?.context == currentGenerationContext {
                disconnectGeneration()
            }
            return
        }

        switch reference.uploadState {
        case .ready:
            guard let context = reference.context else { return }
            startGeneration(
                context: context,
                selectedReferenceID: reference.id
            )
        case .uploading:
            break
        case .failed:
            startReferenceUpload(reference)
        }
    }

    private func handlePromptReferenceAction() {
        guard let promptReference else {
            presentReferencePhotoPicker(destination: .prompt)
            return
        }

        switch promptReference.uploadState {
        case .uploading:
            return
        case .failed:
            startReferenceUpload(promptReference)
        case .ready:
            cancelReferenceUpload(promptReference)
            self.promptReference = nil
            renderPromptReference()
        }
    }

    private func submitPrompt(_ text: String) {
        let prompt = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let canUsePromptReference = promptReference == nil
            || promptReference?.uploadState == .ready
        guard !prompt.isEmpty, canUsePromptReference else {
            return
        }
        selectedReference = nil
        controlPanelView.clearReferenceSelection()
        startGeneration(
            context: RealtimeContext(
                prompt: prompt,
                referencePath: promptReference?.referencePath
            ),
            selectedReferenceID: nil
        )
    }

    private func startReferenceUpload(
        _ reference: RealtimeReferenceCatalog.Item
    ) {
        cancelReferenceUpload(reference)

        reference.uploadState = .uploading
        let requestID = UUID()
        referenceUploadRequestIDs[reference.id] = requestID
        renderReference(reference)

        let apiKey = UserDefaults.standard.string(
            forKey: Self.apiKeyStorageKey
        ) ?? ""
        let fileURL = reference.iconURL
        referenceUploadTasks[reference.id] = Task { [weak self, reference] in
            do {
                let client = XmaxClient(
                    configuration: XmaxConfiguration(apiKey: apiKey)
                )
                let storageManager = try client.createStorageManager()
                let uploaded = try await storageManager.uploadImage(
                    at: fileURL,
                    contentType: nil,
                    progress: nil
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self, reference] in
                    self?.finishReferenceUpload(
                        reference,
                        requestID: requestID,
                        result: .success(uploaded.url)
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self, reference] in
                    self?.finishReferenceUpload(
                        reference,
                        requestID: requestID,
                        result: .failure(error)
                    )
                }
            }
        }
    }

    private func finishReferenceUpload(
        _ reference: RealtimeReferenceCatalog.Item,
        requestID: UUID,
        result: Result<URL, Error>
    ) {
        guard referenceUploadRequestIDs[reference.id] == requestID else {
            return
        }
        referenceUploadRequestIDs[reference.id] = nil
        referenceUploadTasks[reference.id] = nil

        switch result {
        case let .success(remoteURL):
            reference.referencePath = remoteURL.absoluteString
            reference.uploadState = .ready
            renderReference(reference)

            if reference === promptReference {
                return
            }
            if controlPanelView.isReferenceSelected(reference.id),
               let context = reference.context {
                startGeneration(
                    context: context,
                    selectedReferenceID: reference.id
                )
            }
        case .failure:
            reference.uploadState = .failed
            renderReference(reference)
            XLToast.show(
                "参考图上传失败，点击图片可重试",
                in: view
            )
        }
    }

    private func cancelReferenceUpload(
        _ reference: RealtimeReferenceCatalog.Item
    ) {
        referenceUploadTasks[reference.id]?.cancel()
        referenceUploadTasks[reference.id] = nil
        referenceUploadRequestIDs[reference.id] = nil
    }

    private func renderReference(
        _ reference: RealtimeReferenceCatalog.Item
    ) {
        if reference === promptReference {
            renderPromptReference()
        } else {
            controlPanelView.updateReference(reference)
        }
    }

    private func renderPromptReference() {
        controlPanelView.setPromptReference(promptReference)
        promptKeyboardView.setReference(promptReference)
    }

    private func startLocalMedia() {
        localMediaOperationTask?.cancel()
        localMediaOperationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let stream = try await createLocalMediaStream()
                guard !Task.isCancelled else {
                    await stopLocalMediaStream()
                    return
                }
                localMediaStream = stream
                previewView.displayLocal(stream.videoTrack)
                switchCameraButton.isEnabled = localInput == nil
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                showLocalMediaError(error)
            }
        }
    }

    private func createLocalMediaStream() async throws -> RealtimeMediaStream {
        switch localInput {
        case let .image(image):
            return try await realtimeManager.createLocalImageStream(
                image: image
            )
        case let .video(fileURL):
            return try await realtimeManager.createLocalVideoStream(
                fileURL: fileURL
            )
        case nil:
            return try await realtimeManager.createLocalCameraStream(
                videoFormat: Self.cameraVideoFormat,
                position: .front
            )
        }
    }

    private func stopLocalMedia() {
        referenceUploadTasks.values.forEach { $0.cancel() }
        referenceUploadTasks.removeAll()
        referenceUploadRequestIDs.removeAll()
        let pendingGenerationOperation = generationOperationTask
        pendingGenerationOperation?.cancel()
        generationOperationTask = nil
        let pendingStateListener = stateListenerTask
        pendingStateListener?.cancel()
        stateListenerTask = nil
        localMediaOperationTask?.cancel()
        localMediaOperationTask = nil
        isGenerationRequested = false
        controlPanelView.setGenerationActive(false)
        selectedReference = nil
        currentGenerationContext = nil
        localMediaStream = nil
        remoteRealtimeStream = nil
        switchCameraButton.isEnabled = false
        loadingOverlay.hideLoading()
        previewView.displayLocal(nil)
        let realtimeManager = realtimeManager
        Task { [localInput] in
            await pendingStateListener?.value
            await realtimeManager.setStateListener(nil)
            await pendingGenerationOperation?.value
            await realtimeManager.stopGeneration()
            await realtimeManager.disconnect()
            switch localInput {
            case .image:
                try? await realtimeManager.stopLocalImageStream()
            case .video:
                try? await realtimeManager.stopLocalVideoStream()
            case nil:
                try? await realtimeManager.stopLocalCameraStream()
            }
        }
    }

    private func stopLocalMediaStream() async {
        switch localInput {
        case .image:
            try? await realtimeManager.stopLocalImageStream()
        case .video:
            try? await realtimeManager.stopLocalVideoStream()
        case nil:
            try? await realtimeManager.stopLocalCameraStream()
        }
    }

    private func startGeneration(
        context: RealtimeContext,
        selectedReferenceID: String?
    ) {
        isGenerationRequested = true
        controlPanelView.setGenerationActive(true)
        currentGenerationContext = context
        loadingOverlay.startLoading()
        guard let localMediaStream else {
            isGenerationRequested = false
            controlPanelView.setGenerationActive(false)
            currentGenerationContext = nil
            loadingOverlay.hideLoading()
            if let selectedReferenceID {
                controlPanelView.clearReferenceSelection(
                    matching: selectedReferenceID
                )
            }
            showGenerationError(
                message: "本地媒体尚未准备好，请稍后重试。"
            )
            return
        }

        let previousOperation = generationOperationTask
        previousOperation?.cancel()
        generationOperationTask = Task { @MainActor [weak self] in
            await previousOperation?.value
            guard let self, !Task.isCancelled else { return }

            do {
                let state = await realtimeManager.currentState
                switch state.connectionState {
                case .idle, .disconnected, .error:
                    let remoteStream = try await realtimeManager.connect(
                        localStream: localMediaStream
                    )
                    guard !Task.isCancelled else {
                        await realtimeManager.disconnect()
                        return
                    }
                    remoteRealtimeStream = remoteStream
                    previewView.prepareRealtime(remoteStream.videoTrack)
                case .connected, .generating:
                    break
                case .connecting, .disconnecting:
                    throw RealtimeDemoError.connectionTransitioning
                }

                try Task.checkCancellation()
                try await realtimeManager.startGeneration(
                    context: context
                )
                guard !Task.isCancelled else { return }
                previewView.showRealtime()
                loadingOverlay.hideLoading()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isGenerationRequested = false
                controlPanelView.setGenerationActive(false)
                if currentGenerationContext == context {
                    currentGenerationContext = nil
                }
                loadingOverlay.hideLoading()
                remoteRealtimeStream = nil
                previewView.displayLocal(localMediaStream.videoTrack)
                await realtimeManager.disconnect()
                if let selectedReferenceID {
                    controlPanelView.clearReferenceSelection(
                        matching: selectedReferenceID
                    )
                }
                showGenerationError(error)
            }
        }
    }

    private func disconnectGeneration() {
        isGenerationRequested = false
        controlPanelView.setGenerationActive(false)
        currentGenerationContext = nil
        loadingOverlay.hideLoading()
        remoteRealtimeStream = nil
        previewView.displayLocal(localMediaStream?.videoTrack)
        let previousOperation = generationOperationTask
        previousOperation?.cancel()
        generationOperationTask = Task { [realtimeManager] in
            await previousOperation?.value
            await realtimeManager.stopGeneration()
            await realtimeManager.disconnect()
        }
    }

    private func showGenerationError(_ error: any Error) {
        showGenerationError(message: error.localizedDescription)
    }

    private func showGenerationError(message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "实时生成失败",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func showLocalMediaError(_ error: any Error) {
        guard presentedViewController == nil else {
            return
        }
        let alert = UIAlertController(
            title: "本地媒体读取失败",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[
            UIResponder.keyboardFrameEndUserInfoKey
        ] as? CGRect else { return }
        let convertedFrame = view.convert(keyboardFrame, from: nil)
        let keyboardOverlap = max(0, view.bounds.maxY - convertedFrame.minY)
        view.layoutIfNeeded()
        promptKeyboardBottomConstraint?.update(offset: -keyboardOverlap)
        promptKeyboardView.alpha = 1
        animateAlongsideKeyboard(notification) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        view.layoutIfNeeded()
        promptKeyboardBottomConstraint?.update(
            offset: RealtimePromptKeyboardView.preferredHeight
        )
        animateAlongsideKeyboard(notification) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardDidHide() {
        promptKeyboardView.isHidden = true
        promptKeyboardView.alpha = 0
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func switchCamera(_ sender: UIControl) {
        guard localInput == nil,
              localMediaStream != nil else {
            return
        }

        sender.isEnabled = false
        localMediaOperationTask?.cancel()
        localMediaOperationTask = Task { @MainActor [weak self, weak sender] in
            guard let self else {
                return
            }
            defer {
                sender?.isEnabled = true
            }
            do {
                let stream = try await realtimeManager.switchCamera()
                guard !Task.isCancelled else {
                    return
                }
                localMediaStream = stream
                previewView.updateLocal(stream.videoTrack)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                showLocalMediaError(error)
            }
        }
    }

    private func animateAlongsideKeyboard(
        _ notification: Notification,
        animations: @escaping () -> Void
    ) {
        let duration = (notification.userInfo?[
            UIResponder.keyboardAnimationDurationUserInfoKey
        ] as? NSNumber)?.doubleValue ?? 0.25
        let curve = (notification.userInfo?[
            UIResponder.keyboardAnimationCurveUserInfoKey
        ] as? NSNumber)?.uintValue ?? 7
        let options = UIView.AnimationOptions(rawValue: curve << 16)
            .union([.beginFromCurrentState, .allowUserInteraction])
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: options,
            animations: animations
        )
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }
}

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

private enum RealtimeDemoError: LocalizedError {
    case connectionTransitioning

    var errorDescription: String? {
        switch self {
        case .connectionTransitioning:
            return "实时连接正在切换状态，请稍后重试。"
        }
    }
}

private enum RealtimeReferenceImportError: Error {
    case missingFile
}
