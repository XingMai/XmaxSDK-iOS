import PhotosUI
import SnapKit
import UIKit
import XmaxSDK

final class RealtimeViewController: UIViewController, UIGestureRecognizerDelegate {

    private enum ReferencePickerDestination {
        case category(String)
        case prompt
    }

    private static var initialFrameInterpolationEnabled: Bool {
        if #available(iOS 26.0, *) {
            true
        } else {
            false
        }
    }

    // 实时资源
    private var localInput: RealtimeLocalInput?
    private let trajectoryStyle: RealtimeTrajectoryStyle
    private let realtimeManager: any XmaxRealtimeManaging
    private var localMediaStream: RealtimeMediaStream?
    private var selectedReference: RealtimeReferenceCatalog.Item?
    private var currentGenerationContext: RealtimeContext?
    private var isGenerationRequested = false
    private var isTouchAnimationGenerationRequested = false
    private var hasDisplayedPreview = false
    private var isSuspendedForBackground = false

    // 音频状态
    private var localAudioVolume = RealtimeConst.defaultLocalAudioVolume
    private var remoteAudioVolume = RealtimeConst.defaultRemoteAudioVolume
    private var isAudioMuted = false

    // 触控动图
    private var touchAnimationReferencePath: String?

    // 参考图状态
    private var referencePickerDestination: ReferencePickerDestination?
    private var promptReference: RealtimeReferenceCatalog.Item?
    private var referenceUploadRequestIDs: [String: UUID] = [:]

    // 本地素材选择
    private lazy var localMediaPicker = RealtimeLocalMediaPicker()

    // 异步任务
    private var localMediaOperationTask: Task<Void, Never>?
    private var generationOperationTask: Task<Void, Never>?
    private var touchAnimationPreparationTask: Task<Void, Never>?
    private var realtimeListenerTask: Task<Void, Never>?
    private var mediaCleanupTask: Task<Void, Never>?
    private var localAudioVolumeTask: Task<Void, Never>?
    private var remoteAudioVolumeTask: Task<Void, Never>?
    private var frameInterpolationTask: Task<Void, Never>?
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
        usesFileLayout: localInput != nil,
        trajectoryRenderer: trajectoryStyle == .xLabCustom
            ? Self.makeCustomTrajectoryRenderer()
            : nil
    )

    private lazy var controlPanelView: RealtimeControlPanelView = {
        let initialMode: RealtimeControlPanelView.InitialMode =
            localInput?.kind == .image ? .touchAnimation : .standard
        let view = RealtimeControlPanelView(initialMode: initialMode)
        view.isUserInteractionEnabled = false
        view.onBeginPromptEditing = { [weak self] text in
            self?.showPromptKeyboard(text: text)
        }
        view.onPromptSubmit = { [weak self] text in
            self?.submitPrompt(text)
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
        view.onInstructionAction = { [weak self] in
            self?.startTouchAnimationGeneration()
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

    private lazy var cameraActionBar: RealtimeCameraActionBar = {
        let actionBar = RealtimeCameraActionBar()
        actionBar.isHidden = localInput != nil
        actionBar.setSwitchCameraEnabled(false)
        actionBar.onSwitchCamera = { [weak self] in
            self?.switchCamera()
        }
        actionBar.onFrameInterpolationChanged = { [weak self] enabled in
            self?.setFrameInterpolationEnabled(enabled)
        }
        actionBar.setFrameInterpolationEnabled(
            Self.initialFrameInterpolationEnabled
        )
        return actionBar
    }()

    private lazy var mediaTopBar: RealtimeMediaTopBar = {
        let topBar = RealtimeMediaTopBar(
            showsMute: localInput?.kind == .video
        )
        topBar.isHidden = localInput == nil
        topBar.onOpenGallery = { [weak self] in
            self?.presentLocalMediaPicker()
        }
        topBar.onOpenAudioVolume = { [weak self] sourceView in
            self?.presentAudioVolumeMenu(from: sourceView)
        }
        topBar.onMuteChanged = { [weak self] muted in
            self?.setAudioMuted(muted)
        }
        topBar.onFrameInterpolationChanged = { [weak self] enabled in
            self?.setFrameInterpolationEnabled(enabled)
        }
        topBar.setFrameInterpolationEnabled(
            Self.initialFrameInterpolationEnabled
        )
        return topBar
    }()

    private func setFrameInterpolationEnabled(_ enabled: Bool) {
        frameInterpolationTask?.cancel()
        frameInterpolationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await realtimeManager.setFrameInterpolationEnabled(
                    enabled
                )
                guard !Task.isCancelled else { return }
                cameraActionBar.setFrameInterpolationEnabled(enabled)
                mediaTopBar.setFrameInterpolationEnabled(enabled)
            } catch {
                guard !Task.isCancelled else { return }
                let currentValue =
                    await realtimeManager.isFrameInterpolationEnabled
                cameraActionBar.setFrameInterpolationEnabled(currentValue)
                mediaTopBar.setFrameInterpolationEnabled(currentValue)
            }
        }
    }

    private func presentAudioVolumeMenu(from sourceView: UIView) {
        guard presentedViewController == nil else { return }

        let menu = RealtimeAudioVolumeMenuViewController(
            localVolume: localAudioVolume,
            remoteVolume: remoteAudioVolume
        )
        menu.onLocalVolumeChanged = { [weak self] volume in
            self?.setLocalAudioVolume(volume)
        }
        menu.onRemoteVolumeChanged = { [weak self] volume in
            self?.setRemoteAudioVolume(volume)
        }
        if let popover = menu.popoverPresentationController {
            popover.delegate = menu
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
            popover.permittedArrowDirections = .up
        }
        present(menu, animated: true)
    }

    private func setAudioMuted(_ muted: Bool) {
        isAudioMuted = muted
        applyLocalAudioVolume(muted ? 0 : localAudioVolume)
        applyRemoteAudioVolume(muted ? 0 : remoteAudioVolume)
    }

    private func setLocalAudioVolume(_ volume: Float) {
        localAudioVolume = volume
        if isAudioMuted {
            isAudioMuted = false
            mediaTopBar.setMuted(false)
            applyRemoteAudioVolume(remoteAudioVolume)
        }
        applyLocalAudioVolume(volume)
    }

    private func setRemoteAudioVolume(_ volume: Float) {
        remoteAudioVolume = volume
        if isAudioMuted {
            isAudioMuted = false
            mediaTopBar.setMuted(false)
            applyLocalAudioVolume(localAudioVolume)
        }
        applyRemoteAudioVolume(volume)
    }

    private func applyLocalAudioVolume(_ volume: Float) {
        localAudioVolumeTask?.cancel()
        let realtimeManager = realtimeManager
        localAudioVolumeTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            try? await realtimeManager.setLocalAudioVolume(volume)
        }
    }

    private func applyRemoteAudioVolume(_ volume: Float) {
        remoteAudioVolumeTask?.cancel()
        let realtimeManager = realtimeManager
        remoteAudioVolumeTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            try? await realtimeManager.setRemoteAudioVolume(volume)
        }
    }

    private lazy var realtimeErrorAlert: UIAlertController = {
        let alert = UIAlertController(
            title: "实时服务异常",
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        return alert
    }()

    private lazy var loadingOverlay = RealtimeLoadingOverlay()

    init(
        localInput: RealtimeLocalInput? = nil,
        trajectoryStyle: RealtimeTrajectoryStyle = .sdkDefault
    ) {
        self.localInput = localInput
        self.trajectoryStyle = trajectoryStyle
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
        observeNotifications()
        setPreviewDisplayed(false)
        observeRealtimeEvents()
        startLocalMedia()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        resumeRealtimeAfterBackgroundIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            closeRealtime()
        }
    }

    deinit {
        localAudioVolumeTask?.cancel()
        remoteAudioVolumeTask?.cancel()
        frameInterpolationTask?.cancel()
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
                    .offset(RealtimeConst.mediaPreviewTopInset)
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

        view.addSubview(cameraActionBar)
        view.addSubview(mediaTopBar)

        backButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.equalToSuperview().offset(12)
            make.size.equalTo(44)
        }
        cameraActionBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(6)
            make.trailing.equalToSuperview().inset(8)
            make.width.equalTo(58)
            make.height.equalTo(124)
        }
        mediaTopBar.snp.makeConstraints { make in
            make.centerY.equalTo(backButton)
            make.trailing.equalToSuperview().inset(12)
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

    private func observeRealtimeEvents() {
        let pendingCleanup = mediaCleanupTask
        let realtimeManager = realtimeManager
        realtimeListenerTask?.cancel()
        realtimeListenerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await pendingCleanup?.value
            guard !Task.isCancelled else { return }
            await realtimeManager.setErrorListener { [weak self] error in
                self?.presentRealtimeError(error)
            }
            await realtimeManager.setStateListener { [weak self] state in
                self?.renderRealtimeState(state)
            }
        }
    }

    private func presentRealtimeError(_ error: XmaxError) {
        guard error.code != .cancelled else { return }
        if error.code == .frameInterpolationUnsupported {
            XLToast.show(error.localizedDescription, in: view)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let enabled =
                    await realtimeManager.isFrameInterpolationEnabled
                cameraActionBar.setFrameInterpolationEnabled(enabled)
                mediaTopBar.setFrameInterpolationEnabled(enabled)
            }
            return
        }
        guard
              presentedViewController == nil else {
            return
        }
        realtimeErrorAlert.message = error.localizedDescription
        present(realtimeErrorAlert, animated: true)
    }

    private func renderRealtimeState(_ state: RealtimeState) {
        switch state.connectionState {
        case .connecting, .connected:
            if isGenerationRequested {
                previewView.hideRealtime()
                loadingOverlay.startLoading()
            }
        case .generating:
            guard isGenerationRequested else { return }
            previewView.showRealtime()
            loadingOverlay.hideLoading()
        case .idle, .disconnecting, .disconnected, .error:
            renderPreviewLoadingState()
        }
    }

    private func setPreviewDisplayed(_ isDisplayed: Bool) {
        hasDisplayedPreview = isDisplayed
        controlPanelView.isUserInteractionEnabled = isDisplayed
        renderPreviewLoadingState()
    }

    private func renderPreviewLoadingState() {
        if !hasDisplayedPreview || isGenerationRequested {
            loadingOverlay.startLoading()
        } else {
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
            forKey: RealtimeConst.apiKeyStorageKey
        ) ?? ""
        let client = XmaxClient(
            configuration: XmaxConfiguration(
                apiKey: apiKey,
                loggerOptions: .business
            )
        )
        return client.createRealtimeManager(
            options: RealtimeConfiguration(
                model: .x2_0,
                isFrameInterpolationEnabled:
                    Self.initialFrameInterpolationEnabled
            )
        )
    }

    private func presentReferencePhotoPicker(
        destination: ReferencePickerDestination
    ) {
        guard referencePickerDestination == nil,
              presentedViewController == nil else {
            return
        }

        referencePickerDestination = destination
        view.endEditing(true)

        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
        picker.presentationController?.delegate = self
    }

    func finishReferencePicking(
        localURL: URL?,
        error: (any Error)? = nil
    ) {
        let destination = referencePickerDestination
        referencePickerDestination = nil

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

    private func startTouchAnimationGeneration() {
        guard !isGenerationRequested else { return }

        selectedReference = nil
        controlPanelView.clearReferenceSelection()
        isGenerationRequested = true
        isTouchAnimationGenerationRequested = true
        controlPanelView.setGenerationActive(true)
        loadingOverlay.startLoading()

        touchAnimationPreparationTask?.cancel()
        let input = localInput
        touchAnimationPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let referencePath = try await resolveTouchAnimationReferencePath(
                    for: input
                )
                try Task.checkCancellation()
                touchAnimationPreparationTask = nil
                startGeneration(
                    context: RealtimeContext(
                        prompt: RealtimeConst.defaultTouchAnimationPrompt,
                        referencePath: referencePath
                    ),
                    selectedReferenceID: nil,
                    isTouchAnimation: true
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                touchAnimationPreparationTask = nil
                isGenerationRequested = false
                isTouchAnimationGenerationRequested = false
                controlPanelView.setGenerationActive(false)
                renderPreviewLoadingState()
                XLToast.show(error.localizedDescription, in: view)
            }
        }
    }

    private func resolveTouchAnimationReferencePath(
        for input: RealtimeLocalInput?
    ) async throws -> String? {
        guard case let .image(image) = input else { return nil }
        if let touchAnimationReferencePath {
            return touchAnimationReferencePath
        }

        guard let imageData = image.jpegData(compressionQuality: 0.92) else {
            throw RealtimeDemoError.imageEncodingFailed
        }
        let apiKey = UserDefaults.standard.string(
            forKey: RealtimeConst.apiKeyStorageKey
        ) ?? ""
        let client = XmaxClient(
            configuration: XmaxConfiguration(
                apiKey: apiKey,
                loggerOptions: .business
            )
        )
        let storageManager = try client.createStorageManager()
        let uploaded = try await storageManager.uploadImage(
            imageData,
            fileName: "touch-animation-\(UUID().uuidString).jpg",
            contentType: "image/jpeg",
            progress: nil
        )
        try Task.checkCancellation()
        let referencePath = uploaded.url.absoluteString
        touchAnimationReferencePath = referencePath
        return referencePath
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
            forKey: RealtimeConst.apiKeyStorageKey
        ) ?? ""
        let fileURL = reference.iconURL
        referenceUploadTasks[reference.id] = Task { [weak self, reference] in
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
        let input = localInput
        let pendingCleanup = mediaCleanupTask
        let pendingRealtimeListener = realtimeListenerTask
        localMediaOperationTask?.cancel()
        localMediaOperationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await pendingCleanup?.value
            await pendingRealtimeListener?.value
            guard !Task.isCancelled else { return }
            if input == nil {
                await realtimeManager.setCameraPreviewReadyListener {
                    [weak self] in
                    self?.setPreviewDisplayed(true)
                }
            } else {
                await realtimeManager.setCameraPreviewReadyListener(nil)
            }
            do {
                let stream = try await createLocalMediaStream(for: input)
                guard !Task.isCancelled else {
                    await realtimeManager.close()
                    return
                }
                guard displayLocalPreview(stream) else {
                    await realtimeManager.close()
                    return
                }
                if input != nil {
                    setPreviewDisplayed(true)
                }
                cameraActionBar.setSwitchCameraEnabled(localInput == nil)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                await realtimeManager.close()
            }
        }
    }

    private func createLocalMediaStream(
        for input: RealtimeLocalInput?
    ) async throws -> RealtimeMediaStream {
        switch input {
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
                videoFormat: RealtimeConst.cameraVideoFormat,
                position: .front
            )
        }
    }

    private func displayLocalPreview(
        _ stream: RealtimeMediaStream
    ) -> Bool {
        guard let videoTrack = stream.videoTrack else {
            assertionFailure("Realtime media stream has no video track")
            return false
        }
        localMediaStream = stream
        previewView.displayLocal(videoTrack)
        return true
    }

    private func closeRealtime(
        cancelsReferenceUploads: Bool = true
    ) {
        if cancelsReferenceUploads {
            referenceUploadTasks.values.forEach { $0.cancel() }
            referenceUploadTasks.removeAll()
            referenceUploadRequestIDs.removeAll()
        }

        let previousCleanup = mediaCleanupTask
        let pendingLocalMediaOperation = localMediaOperationTask
        let pendingGenerationOperation = generationOperationTask
        let pendingRealtimeListener = realtimeListenerTask

        pendingLocalMediaOperation?.cancel()
        localMediaOperationTask = nil

        pendingGenerationOperation?.cancel()
        generationOperationTask = nil

        touchAnimationPreparationTask?.cancel()
        touchAnimationPreparationTask = nil

        frameInterpolationTask?.cancel()
        frameInterpolationTask = nil

        pendingRealtimeListener?.cancel()
        realtimeListenerTask = nil

        isGenerationRequested = false
        isTouchAnimationGenerationRequested = false
        selectedReference = nil
        currentGenerationContext = nil
        touchAnimationReferencePath = nil

        localMediaStream = nil

        controlPanelView.setGenerationActive(false)
        controlPanelView.clearReferenceSelection()
        cameraActionBar.setSwitchCameraEnabled(false)
        loadingOverlay.hideLoading()
        hasDisplayedPreview = false
        controlPanelView.isUserInteractionEnabled = false
        previewView.displayLocal(nil)

        let realtimeManager = realtimeManager
        mediaCleanupTask = Task {
            await previousCleanup?.value
            await pendingRealtimeListener?.value

            await realtimeManager.setErrorListener(nil)
            await realtimeManager.setStateListener(nil)
            await realtimeManager.setCameraPreviewReadyListener(nil)

            await pendingLocalMediaOperation?.value
            await pendingGenerationOperation?.value

            await realtimeManager.close()
        }
    }

    func suspendRealtimeForBackground() {
        guard !isSuspendedForBackground else { return }
        isSuspendedForBackground = true
        view.endEditing(true)
        closeRealtime(cancelsReferenceUploads: false)
    }

    func resumeRealtimeAfterBackgroundIfNeeded() {
        guard isSuspendedForBackground,
              UIApplication.shared.applicationState == .active,
              viewIfLoaded?.window != nil else {
            return
        }
        isSuspendedForBackground = false
        setPreviewDisplayed(false)
        observeRealtimeEvents()
        startLocalMedia()
    }

    private func replaceLocalMedia(with input: RealtimeLocalInput) {
        let pendingLocalOperation = localMediaOperationTask
        pendingLocalOperation?.cancel()
        let pendingGenerationOperation = generationOperationTask
        pendingGenerationOperation?.cancel()
        generationOperationTask = nil
        let pendingTouchAnimationPreparation = touchAnimationPreparationTask
        pendingTouchAnimationPreparation?.cancel()
        touchAnimationPreparationTask = nil

        let restartsTouchAnimation = isGenerationRequested
            && isTouchAnimationGenerationRequested
        let restartContext = isGenerationRequested && !restartsTouchAnimation
            ? currentGenerationContext
            : nil
        let selectedReferenceID = selectedReference?.id
        isGenerationRequested = false
        isTouchAnimationGenerationRequested = false
        controlPanelView.setGenerationActive(false)
        currentGenerationContext = nil
        touchAnimationReferencePath = nil
        localMediaStream = nil
        previewView.displayLocal(nil)
        setPreviewDisplayed(false)

        localMediaOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await pendingLocalOperation?.value
            await pendingGenerationOperation?.value
            await pendingTouchAnimationPreparation?.value
            guard !Task.isCancelled else { return }

            await realtimeManager.close()
            guard !Task.isCancelled else { return }

            localInput = input
            loadingOverlay.startLoading()
            do {
                let stream = try await createLocalMediaStream(for: input)
                guard !Task.isCancelled else {
                    await realtimeManager.close()
                    return
                }
                guard displayLocalPreview(stream) else {
                    await realtimeManager.close()
                    return
                }
                setPreviewDisplayed(true)

                if restartsTouchAnimation {
                    startTouchAnimationGeneration()
                } else if let restartContext {
                    startGeneration(
                        context: restartContext,
                        selectedReferenceID: selectedReferenceID
                    )
                } else {
                    renderPreviewLoadingState()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await realtimeManager.close()
                renderPreviewLoadingState()
            }
        }
    }

    private func startGeneration(
        context: RealtimeContext,
        selectedReferenceID: String?,
        isTouchAnimation: Bool = false
    ) {
        if !isTouchAnimation {
            touchAnimationPreparationTask?.cancel()
            touchAnimationPreparationTask = nil
        }
        isGenerationRequested = true
        isTouchAnimationGenerationRequested = isTouchAnimation
        controlPanelView.setGenerationActive(true)
        currentGenerationContext = context
        loadingOverlay.startLoading()
        guard let localMediaStream else {
            isGenerationRequested = false
            isTouchAnimationGenerationRequested = false
            controlPanelView.setGenerationActive(false)
            currentGenerationContext = nil
            renderPreviewLoadingState()
            if let selectedReferenceID {
                controlPanelView.clearReferenceSelection(
                    matching: selectedReferenceID
                )
            }
            XLToast.show("本地媒体尚未准备好，请稍后重试。", in: view)
            return
        }

        let previousOperation = generationOperationTask
        previousOperation?.cancel()
        generationOperationTask = Task { @MainActor [weak self] in
            await previousOperation?.value
            guard let self, !Task.isCancelled else { return }

            do {
                let remoteStream = try await realtimeManager.startGeneration(
                    localStream: localMediaStream,
                    context: context
                )
                guard !Task.isCancelled else {
                    await realtimeManager.disconnect()
                    return
                }
                previewView.prepareRealtime(remoteStream.videoTrack)
                previewView.showRealtime()
                loadingOverlay.hideLoading()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isGenerationRequested = false
                isTouchAnimationGenerationRequested = false
                controlPanelView.setGenerationActive(false)
                if currentGenerationContext == context {
                    currentGenerationContext = nil
                }
                loadingOverlay.hideLoading()
                previewView.displayLocal(localMediaStream.videoTrack)
                await realtimeManager.disconnect()
                if let selectedReferenceID {
                    controlPanelView.clearReferenceSelection(
                        matching: selectedReferenceID
                    )
                }
            }
        }
    }

    private func disconnectGeneration() {
        touchAnimationPreparationTask?.cancel()
        touchAnimationPreparationTask = nil
        isGenerationRequested = false
        isTouchAnimationGenerationRequested = false
        controlPanelView.setGenerationActive(false)
        currentGenerationContext = nil
        loadingOverlay.hideLoading()
        let previousOperation = generationOperationTask
        previousOperation?.cancel()
        generationOperationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await previewView.transitionToLocal(
                localMediaStream?.videoTrack
            )
            await previousOperation?.value
            guard !Task.isCancelled else { return }
            await realtimeManager.disconnect()
        }
    }

    @objc func keyboardWillShow(_ notification: Notification) {
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

    @objc func keyboardWillHide(_ notification: Notification) {
        view.layoutIfNeeded()
        promptKeyboardBottomConstraint?.update(
            offset: RealtimePromptKeyboardView.preferredHeight
        )
        animateAlongsideKeyboard(notification) {
            self.view.layoutIfNeeded()
        }
    }

    @objc func keyboardDidHide() {
        promptKeyboardView.isHidden = true
        promptKeyboardView.alpha = 0
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func presentLocalMediaPicker() {
        guard let kind = localInput?.kind,
              presentedViewController == nil else {
            return
        }

        view.endEditing(true)
        localMediaPicker.present(
            from: self,
            kind: kind
        ) { [weak self] result in
            guard let self else { return }

            switch result {
            case let .success(.some(input)):
                replaceLocalMedia(with: input)
            case .success(.none):
                break
            case let .failure(error):
                XLToast.show(error.localizedDescription, in: view)
            }
        }
    }

    private func switchCamera() {
        guard localInput == nil,
              localMediaStream != nil else {
            return
        }

        cameraActionBar.setSwitchCameraEnabled(false)
        previewView.setCameraSwitchTransitionActive(true)
        localMediaOperationTask?.cancel()
        localMediaOperationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                previewView.setCameraSwitchTransitionActive(false)
                cameraActionBar.setSwitchCameraEnabled(true)
            }
            guard let stream = try? await realtimeManager.switchCamera(),
                  !Task.isCancelled else {
                return
            }
            localMediaStream = stream
            previewView.updateLocal(stream.videoTrack)
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

private enum RealtimeDemoError: LocalizedError {
    case connectionTransitioning
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .connectionTransitioning:
            return "实时连接正在切换状态，请稍后重试。"
        case .imageEncodingFailed:
            return "图片处理失败，请重新选择图片。"
        }
    }
}
