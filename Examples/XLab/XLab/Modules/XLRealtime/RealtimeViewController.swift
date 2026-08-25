import AVFoundation
import ImageIO
import Kingfisher
import SnapKit
import UIKit
import XmaxSDK

enum RealtimeLocalInput: Sendable {
    case image(URL)
    case video(URL)
}

final class RealtimeViewController: UIViewController {

    // 本地配置
    private static let apiKeyStorageKey = "xlab.realtime.apiKey"
    private static let cameraVideoFormat = RealtimeVideoFormat(
        width: 832,
        height: 1472,
        fps: 24
    )

    // 界面组件
    private let previewView = RealtimePreviewBackdropView()
    private let controlPanelView = RealtimeControlPanelView()
    private let promptKeyboardView = RealtimePromptKeyboardView()
    private let switchCameraButton = RealtimeCameraSwitchButton()
    private let loadingOverlay = RealtimeLoadingOverlay()

    // 实时资源
    private let localInput: RealtimeLocalInput?
    private lazy var realtimeManager = makeRealtimeManager()
    private var localCameraStream: RealtimeMediaStream?
    private var remoteRealtimeStream: RealtimeMediaStream?
    private var isGenerationRequested = false

    // 异步任务
    private var cameraOperationTask: Task<Void, Never>?
    private var generationOperationTask: Task<Void, Never>?
    private var stateListenerTask: Task<Void, Never>?

    // 布局约束
    private var promptKeyboardBottomConstraint: Constraint?

    init(localInput: RealtimeLocalInput? = nil) {
        self.localInput = localInput
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
        observeKeyboard()
        observeRealtimeState()
        startCameraIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            stopCamera()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configurePreview() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        previewView.display(localInput)

        previewView.snp.makeConstraints { make in
            make.top.horizontalEdges.equalToSuperview()
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
        previewView.addSubview(backButton)

        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false
        switchCameraButton.isEnabled = false
        switchCameraButton.isHidden = localInput != nil
        switchCameraButton.addTarget(
            self,
            action: #selector(switchCamera(_:)),
            for: .touchUpInside
        )
        previewView.addSubview(switchCameraButton)

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

        controlPanelView.onBeginPromptEditing = { [weak self] text in
            self?.showPromptKeyboard(text: text)
        }
        controlPanelView.onReferenceSelectionChanged = { [weak self] reference in
            guard let self else { return }
            if let reference {
                startGeneration(with: reference)
            } else {
                disconnectGeneration()
            }
        }
    }

    private func configurePromptKeyboard() {
        promptKeyboardView.isHidden = true
        promptKeyboardView.onTextChange = { [weak self] text in
            self?.controlPanelView.setPromptText(text)
        }
        promptKeyboardView.onSubmit = { [weak self] text in
            self?.controlPanelView.setPromptText(text)
            self?.promptKeyboardView.endEditing()
        }
        view.addSubview(promptKeyboardView)
        promptKeyboardView.snp.makeConstraints { make in
            make.horizontalEdges.equalToSuperview()
            make.height.equalTo(RealtimePromptKeyboardView.preferredHeight)
            promptKeyboardBottomConstraint = make.bottom.equalToSuperview()
                .offset(RealtimePromptKeyboardView.preferredHeight)
                .constraint
        }
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
            previewView.displayRealtime(
                remoteRealtimeStream?.videoTrack
            )
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

    private func makeRealtimeManager() -> any XmaxRealtimeManaging {
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

    private func startCameraIfNeeded() {
        guard localInput == nil else {
            return
        }

        cameraOperationTask?.cancel()
        cameraOperationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let stream = try await realtimeManager.createLocalCameraStream(
                    videoFormat: Self.cameraVideoFormat,
                    position: .front
                )
                guard !Task.isCancelled else {
                    try? await realtimeManager.stopLocalCameraStream()
                    return
                }
                localCameraStream = stream
                previewView.displayCamera(stream.videoTrack)
                switchCameraButton.isEnabled = true
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                showCameraError(error)
            }
        }
    }

    private func stopCamera() {
        guard localInput == nil else {
            return
        }

        let pendingGenerationOperation = generationOperationTask
        pendingGenerationOperation?.cancel()
        generationOperationTask = nil
        let pendingStateListener = stateListenerTask
        pendingStateListener?.cancel()
        stateListenerTask = nil
        cameraOperationTask?.cancel()
        cameraOperationTask = nil
        isGenerationRequested = false
        localCameraStream = nil
        remoteRealtimeStream = nil
        switchCameraButton.isEnabled = false
        loadingOverlay.hideLoading()
        previewView.displayCamera(nil)
        let realtimeManager = realtimeManager
        Task {
            await pendingStateListener?.value
            await realtimeManager.setStateListener(nil)
            await pendingGenerationOperation?.value
            await realtimeManager.stopGeneration()
            await realtimeManager.disconnect()
            try? await realtimeManager.stopLocalCameraStream()
        }
    }

    private func startGeneration(
        with reference: RealtimeReferenceCatalog.Item
    ) {
        isGenerationRequested = true
        loadingOverlay.startLoading()
        guard let localCameraStream else {
            isGenerationRequested = false
            loadingOverlay.hideLoading()
            controlPanelView.clearReferenceSelection(
                matching: reference.id
            )
            showGenerationError(
                message: "摄像头尚未准备好，请稍后重试。"
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
                        localStream: localCameraStream
                    )
                    guard !Task.isCancelled else {
                        await realtimeManager.disconnect()
                        return
                    }
                    remoteRealtimeStream = remoteStream
                case .connected, .generating:
                    break
                case .connecting, .disconnecting:
                    throw RealtimeDemoError.connectionTransitioning
                }

                try Task.checkCancellation()
                try await realtimeManager.startGeneration(
                    context: reference.context
                )
                guard !Task.isCancelled else { return }
                previewView.displayRealtime(
                    remoteRealtimeStream?.videoTrack
                )
                loadingOverlay.hideLoading()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isGenerationRequested = false
                loadingOverlay.hideLoading()
                remoteRealtimeStream = nil
                previewView.displayCamera(localCameraStream.videoTrack)
                await realtimeManager.disconnect()
                controlPanelView.clearReferenceSelection(
                    matching: reference.id
                )
                showGenerationError(error)
            }
        }
    }

    private func disconnectGeneration() {
        isGenerationRequested = false
        loadingOverlay.hideLoading()
        remoteRealtimeStream = nil
        previewView.displayCamera(localCameraStream?.videoTrack)
        let previousOperation = generationOperationTask
        previousOperation?.cancel()
        generationOperationTask = Task { [realtimeManager] in
            await previousOperation?.value
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

    private func showCameraError(_ error: any Error) {
        guard presentedViewController == nil else {
            return
        }
        let alert = UIAlertController(
            title: "摄像头操作失败",
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

    @objc private func switchCamera(_ sender: UIControl) {
        guard localInput == nil,
              localCameraStream != nil else {
            return
        }

        sender.isEnabled = false
        cameraOperationTask?.cancel()
        cameraOperationTask = Task { @MainActor [weak self, weak sender] in
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
                localCameraStream = stream
                previewView.displayCamera(stream.videoTrack)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                showCameraError(error)
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

private enum RealtimeDemoError: LocalizedError {
    case connectionTransitioning

    var errorDescription: String? {
        switch self {
        case .connectionTransitioning:
            return "实时连接正在切换状态，请稍后重试。"
        }
    }
}

private final class RealtimeLoadingOverlay: UIView {
    private let loadingImageView = UIImageView()
    private let fallbackIndicator = UIActivityIndicatorView(style: .medium)
    private var isLoading = false
    private var transitionVersion: UInt64 = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.72)
        isHidden = true
        alpha = 0
        isUserInteractionEnabled = false

        loadingImageView.image = RealtimeLoadingImageLoader.animatedImage()
        loadingImageView.contentMode = .scaleAspectFit
        fallbackIndicator.color = UIColor.white.withAlphaComponent(0.86)
        fallbackIndicator.hidesWhenStopped = true

        addSubview(loadingImageView)
        addSubview(fallbackIndicator)
        loadingImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(54)
            make.height.equalTo(50)
        }
        fallbackIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startLoading() {
        guard !isLoading else { return }
        isLoading = true
        transitionVersion &+= 1
        layer.removeAllAnimations()
        isHidden = false

        if loadingImageView.image == nil {
            fallbackIndicator.startAnimating()
        } else {
            fallbackIndicator.stopAnimating()
            loadingImageView.startAnimating()
        }

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.alpha = 1
        }
    }

    func hideLoading() {
        guard isLoading || !isHidden else { return }
        isLoading = false
        transitionVersion &+= 1
        let version = transitionVersion
        layer.removeAllAnimations()
        loadingImageView.stopAnimating()
        fallbackIndicator.stopAnimating()

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.alpha = 0
        } completion: { _ in
            guard version == self.transitionVersion else { return }
            self.isHidden = true
        }
    }
}

private enum RealtimeLoadingImageLoader {
    static func animatedImage() -> UIImage? {
        guard let data = NSDataAsset(name: "RealtimeLoading")?.data,
              let source = CGImageSourceCreateWithData(
                data as CFData,
                nil
              ) else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }
        var images: [UIImage] = []
        var duration: TimeInterval = 0

        for index in 0..<frameCount {
            guard let image = CGImageSourceCreateImageAtIndex(
                source,
                index,
                nil
            ) else { continue }
            images.append(UIImage(cgImage: image))
            duration += frameDuration(source: source, index: index)
        }

        guard !images.isEmpty else { return nil }
        return UIImage.animatedImage(
            with: images,
            duration: duration > 0 ? duration : 0.1 * Double(images.count)
        )
    }

    private static func frameDuration(
        source: CGImageSource,
        index: Int
    ) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            index,
            nil
        ) as? [String: Any],
        let gifProperties = properties[
            kCGImagePropertyGIFDictionary as String
        ] as? [String: Any] else {
            return 0.1
        }

        return gifProperties[
            kCGImagePropertyGIFUnclampedDelayTime as String
        ] as? TimeInterval
            ?? gifProperties[
                kCGImagePropertyGIFDelayTime as String
            ] as? TimeInterval
            ?? 0.1
    }
}

private final class RealtimePreviewBackdropView: UIView {

    // 媒体视图
    private let realtimeVideoView = XmaxVideoView()
    private let mediaImageView = UIImageView()
    private let mediaPlayerLayer = AVPlayerLayer()

    // 播放资源
    private var mediaPlayer: AVQueuePlayer?
    private var mediaLooper: AVPlayerLooper?

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        gradientLayer.colors = [
            UIColor.feed(rgb: 0x171719).cgColor,
            UIColor.feed(rgb: 0x0D0D0F).cgColor,
            UIColor.feed(rgb: 0x050506).cgColor
        ]
        gradientLayer.locations = [0, 0.48, 1]
        gradientLayer.startPoint = CGPoint(x: 0.25, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.75, y: 1)

        mediaPlayerLayer.videoGravity = .resizeAspect
        layer.addSublayer(mediaPlayerLayer)

        realtimeVideoView.translatesAutoresizingMaskIntoConstraints = false
        realtimeVideoView.videoContentMode = .fill
        realtimeVideoView.isHidden = true
        addSubview(realtimeVideoView)

        mediaImageView.contentMode = .scaleAspectFit
        mediaImageView.backgroundColor = .black
        mediaImageView.isHidden = true
        addSubview(mediaImageView)
        realtimeVideoView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        mediaImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        mediaPlayerLayer.frame = bounds
    }

    func display(_ input: RealtimeLocalInput?) {
        stopVideo()
        realtimeVideoView.track = nil
        realtimeVideoView.isHidden = true
        mediaImageView.image = nil
        mediaImageView.isHidden = true

        switch input {
        case let .image(url):
            mediaImageView.image = UIImage(contentsOfFile: url.path)
            mediaImageView.isHidden = false
        case let .video(url):
            let player = AVQueuePlayer()
            mediaLooper = AVPlayerLooper(
                player: player,
                templateItem: AVPlayerItem(url: url)
            )
            mediaPlayer = player
            mediaPlayerLayer.player = player
            player.isMuted = true
            player.play()
        case nil:
            break
        }
    }

    func displayCamera(_ track: RealtimeVideoTrack?) {
        stopVideo()
        mediaImageView.image = nil
        mediaImageView.isHidden = true
        realtimeVideoView.isHidden = false
        realtimeVideoView.track = track
    }

    func displayRealtime(_ track: RealtimeVideoTrack?) {
        displayCamera(track)
    }

    private func stopVideo() {
        mediaPlayer?.pause()
        mediaPlayerLayer.player = nil
        mediaLooper = nil
        mediaPlayer = nil
    }
}

private final class RealtimeCameraSwitchButton: UIControl {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(named: "realtime_camera_rotate")?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "翻转"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textAlignment = .center

        [iconView, titleLabel].forEach {
            $0.layer.shadowColor = UIColor.black.cgColor
            $0.layer.shadowOpacity = 0.5
            $0.layer.shadowRadius = 2
            $0.layer.shadowOffset = CGSize(width: 0, height: 1)
        }

        addSubview(iconView)
        addSubview(titleLabel)
        accessibilityLabel = "翻转摄像头"
        accessibilityTraits = .button

        iconView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(10)
            make.centerX.equalToSuperview()
            make.size.equalTo(22)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(iconView.snp.bottom).offset(6)
            make.centerX.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct RealtimeReferenceCatalog: Decodable {
    struct Item: Decodable {
        let id: String
        let categoryID: String
        let title: String
        let iconURL: URL
        let prompt: String
        let referencePath: String

        var context: RealtimeContext {
            RealtimeContext(
                prompt: prompt,
                referencePath: referencePath
            )
        }
    }

    let items: [Item]

    static func load() -> RealtimeReferenceCatalog {
        guard
            let data = NSDataAsset(name: "RealtimeReferenceCatalog")?.data,
            let catalog = try? JSONDecoder().decode(
                RealtimeReferenceCatalog.self,
                from: data
            )
        else {
            return RealtimeReferenceCatalog(items: [])
        }
        return catalog
    }
}

private final class RealtimeControlPanelView: UIView {
    var onBeginPromptEditing: ((String) -> Void)?
    var onReferenceSelectionChanged: ((RealtimeReferenceCatalog.Item?) -> Void)?

    private enum Layout {
        static let topSpacing: CGFloat = 6
        static let categoryHeight: CGFloat = 36
        static let categoryLeadingSpacing: CGFloat = 11
        static let categoryItemSpacing: CGFloat = 14
        static let clearButtonLeadingSpacing: CGFloat = 14
        static let clearButtonWidth: CGFloat = 28
        static let rowSpacing: CGFloat = 4
        static let referenceHeight: CGFloat = 50
        static let promptInputHeight: CGFloat = 50
        static let bottomSpacing: CGFloat = 10
    }

    private enum Content {
        case references(categoryID: String)
        case instruction
        case prompt
    }

    private struct Category {
        let id: String
        let name: String
        let content: Content
    }

    private let categories = [
        Category(id: "charx", name: "换形象", content: .references(categoryID: "charx")),
        Category(id: "clothx", name: "换装", content: .references(categoryID: "clothx")),
        Category(id: "vibex", name: "换风格", content: .references(categoryID: "vibex")),
        Category(id: "mox", name: "触控动图", content: .instruction),
        Category(id: "dimx", name: "虚拟召唤", content: .references(categoryID: "dimx")),
        Category(id: "free", name: "自由", content: .prompt)
    ]
    private let referencesByCategory = Dictionary(
        grouping: RealtimeReferenceCatalog.load().items,
        by: \.categoryID
    )

    private let disabledActionButton = UIButton(type: .custom)
    private let categoryScrollView = RealtimeCategoryScrollView()
    private let categoryStackView = UIStackView()
    private let contentContainerView = UIView()
    private let referenceListView = RealtimeReferenceListView()
    private let instructionButton = UIButton(type: .custom)
    private let promptInputView = RealtimePromptFieldView()
    private var categoryButtons: [UIButton] = []
    private var selectedCategoryIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feed(rgb: 0x101010)
        configureCategoryRow()
        configureContentArea()
        promptInputView.onBeginEditing = { [weak self] text in
            self?.onBeginPromptEditing?(text)
        }
        updateCategorySelection()
        updateVisibleContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCategoryRow() {
        disabledActionButton.translatesAutoresizingMaskIntoConstraints = false
        disabledActionButton.setImage(
            UIImage(
                systemName: "nosign",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 11,
                    weight: .regular
                )
            ),
            for: .normal
        )
        disabledActionButton.tintColor = .white
        disabledActionButton.addTarget(
            self,
            action: #selector(disableGeneration),
            for: .touchUpInside
        )
        disabledActionButton.accessibilityLabel = "停止生成"
        addSubview(disabledActionButton)

        categoryScrollView.translatesAutoresizingMaskIntoConstraints = false
        categoryScrollView.showsHorizontalScrollIndicator = false
        categoryScrollView.alwaysBounceHorizontal = true
        categoryScrollView.delaysContentTouches = true
        categoryScrollView.canCancelContentTouches = true
        categoryScrollView.isDirectionalLockEnabled = true
        categoryScrollView.contentInsetAdjustmentBehavior = .never
        addSubview(categoryScrollView)

        categoryStackView.translatesAutoresizingMaskIntoConstraints = false
        categoryStackView.axis = .horizontal
        categoryStackView.alignment = .fill
        categoryStackView.spacing = Layout.categoryItemSpacing
        categoryScrollView.addSubview(categoryStackView)

        for (index, category) in categories.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.setTitle(category.name, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .regular)
            button.addTarget(
                self,
                action: #selector(selectCategory(_:)),
                for: .touchUpInside
            )
            button.accessibilityIdentifier = category.id
            button.snp.makeConstraints { make in
                let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
                let textWidth = ceil(
                    (category.name as NSString).size(
                        withAttributes: [.font: font]
                    ).width
                )
                make.width.equalTo(textWidth + 10)
                make.height.equalTo(Layout.categoryHeight)
            }
            categoryStackView.addArrangedSubview(button)
            categoryButtons.append(button)
        }

        disabledActionButton.snp.makeConstraints { make in
            make.leading.equalToSuperview()
                .offset(Layout.clearButtonLeadingSpacing)
            make.centerY.equalTo(categoryScrollView)
            make.width.equalTo(Layout.clearButtonWidth)
            make.height.equalTo(Layout.categoryHeight)
        }
        categoryScrollView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Layout.topSpacing)
            make.leading.equalTo(disabledActionButton.snp.trailing)
                .offset(Layout.categoryLeadingSpacing)
            make.trailing.equalToSuperview()
            make.height.equalTo(Layout.categoryHeight)
        }
        categoryStackView.snp.makeConstraints { make in
            make.leading.equalTo(categoryScrollView.contentLayoutGuide)
            make.trailing.equalTo(categoryScrollView.contentLayoutGuide)
                .offset(-14)
            make.verticalEdges.equalTo(categoryScrollView.contentLayoutGuide)
            make.height.equalTo(categoryScrollView.frameLayoutGuide)
        }
    }

    private func configureContentArea() {
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainerView)

        contentContainerView.addSubview(referenceListView)
        referenceListView.onSelectionChanged = { [weak self] reference in
            self?.onReferenceSelectionChanged?(reference)
        }

        instructionButton.translatesAutoresizingMaskIntoConstraints = false
        instructionButton.setTitle("点击开始生成", for: .normal)
        instructionButton.setTitleColor(.white.withAlphaComponent(0.85), for: .normal)
        instructionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        instructionButton.backgroundColor = .white.withAlphaComponent(0.14)
        instructionButton.layer.cornerRadius = 20
        instructionButton.layer.borderWidth = 1
        instructionButton.layer.borderColor = UIColor.white.withAlphaComponent(0.19).cgColor
        instructionButton.accessibilityLabel = "点击开始生成"
        contentContainerView.addSubview(instructionButton)

        promptInputView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(promptInputView)

        contentContainerView.snp.makeConstraints { make in
            make.top.equalTo(categoryScrollView.snp.bottom)
                .offset(Layout.rowSpacing)
            make.horizontalEdges.equalToSuperview()
            make.height.equalTo(Layout.referenceHeight)
            make.bottom.equalTo(safeAreaLayoutGuide)
                .offset(-Layout.bottomSpacing)
        }
        referenceListView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        instructionButton.snp.makeConstraints { make in
            make.horizontalEdges.equalToSuperview().inset(14)
            make.centerY.equalToSuperview()
            make.height.equalTo(Layout.referenceHeight)
        }
        promptInputView.snp.makeConstraints { make in
            make.horizontalEdges.equalToSuperview().inset(14)
            make.centerY.equalToSuperview()
            make.height.equalTo(Layout.promptInputHeight)
        }
    }

    @objc private func selectCategory(_ sender: UIButton) {
        guard sender.tag != selectedCategoryIndex else { return }
        selectedCategoryIndex = sender.tag
        updateCategorySelection()
        updateVisibleContent()

        categoryScrollView.scrollRectToVisible(
            sender.convert(
                sender.bounds.insetBy(dx: -18, dy: 0),
                to: categoryScrollView
            ),
            animated: true
        )
    }

    private func updateCategorySelection() {
        for (index, button) in categoryButtons.enumerated() {
            let isSelected = index == selectedCategoryIndex
            button.setTitleColor(
                isSelected ? .white : .white.withAlphaComponent(0.48),
                for: .normal
            )
            button.titleLabel?.font = .systemFont(
                ofSize: 13,
                weight: isSelected ? .semibold : .regular
            )
            button.accessibilityTraits =
                isSelected ? [.button, .selected] : .button
        }
    }

    private func updateVisibleContent() {
        referenceListView.isHidden = true
        instructionButton.isHidden = true
        promptInputView.isHidden = true

        switch categories[selectedCategoryIndex].content {
        case let .references(categoryID):
            referenceListView.isHidden = false
            referenceListView.apply(
                references: referencesByCategory[categoryID] ?? []
            )
        case .instruction:
            instructionButton.isHidden = false
        case .prompt:
            promptInputView.isHidden = false
        }
    }

    func setPromptText(_ text: String) {
        promptInputView.setText(text)
    }

    func clearReferenceSelection(matching referenceID: String? = nil) {
        referenceListView.clearSelection(matching: referenceID)
    }

    @objc private func disableGeneration() {
        referenceListView.clearSelection()
        onReferenceSelectionChanged?(nil)
    }

}

private final class RealtimeCategoryScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }
}

private final class RealtimeReferenceListView: UIView {
    var onSelectionChanged: ((RealtimeReferenceCatalog.Item?) -> Void)?

    private enum Layout {
        static let itemLength: CGFloat = 50
        static let itemSpacing: CGFloat = 10
        static let edgeFadeWidth: CGFloat = 32
        static let selectionBorderWidth: CGFloat = 2
        static let edgeFadeTransitionDuration: CFTimeInterval = 0.3
    }

    private let collectionView: UICollectionView
    private let addReferenceButton = UIButton(type: .custom)
    private let edgeFadeMaskLayer = CAGradientLayer()
    private let feedbackGenerator = UISelectionFeedbackGenerator()
    private var references: [RealtimeReferenceCatalog.Item] = []
    private var selectedReferenceID: String?
    private var hasConfiguredEdgeFadeMask = false
    private var isShowingLeftFade = false
    private var isShowingRightFade = false

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(
            width: Layout.itemLength,
            height: Layout.itemLength
        )
        layout.minimumLineSpacing = Layout.itemSpacing
        layout.sectionInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: 0,
            right: 14
        )
        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )

        super.init(frame: frame)

        addReferenceButton.setImage(
            UIImage(named: "realtime_add_reference"),
            for: .normal
        )
        addReferenceButton.imageView?.contentMode = .scaleAspectFill
        addReferenceButton.backgroundColor = .feed(rgb: 0x303032)
        addReferenceButton.layer.cornerRadius = 10
        addReferenceButton.layer.cornerCurve = .continuous
        addReferenceButton.clipsToBounds = true
        addReferenceButton.accessibilityLabel = "添加参考图"

        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.alwaysBounceVertical = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(
            RealtimeReferenceCell.self,
            forCellWithReuseIdentifier: RealtimeReferenceCell.reuseIdentifier
        )

        addSubview(addReferenceButton)
        addSubview(collectionView)

        addReferenceButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.size.equalTo(Layout.itemLength)
        }
        collectionView.snp.makeConstraints { make in
            make.verticalEdges.trailing.equalToSuperview()
            make.leading.equalTo(addReferenceButton.snp.trailing)
                .offset(Layout.itemSpacing)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateEdgeFadeMask()
    }

    func apply(references: [RealtimeReferenceCatalog.Item]) {
        self.references = references
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
        collectionView.layoutIfNeeded()
        updateEdgeFadeMask()
    }

    func clearSelection(matching referenceID: String? = nil) {
        guard let selectedReferenceID,
              referenceID == nil || referenceID == selectedReferenceID else {
            return
        }
        self.selectedReferenceID = nil
        guard let index = references.firstIndex(where: {
            $0.id == selectedReferenceID
        }) else { return }
        collectionView.reloadItems(
            at: [IndexPath(item: index, section: 0)]
        )
    }

    private func updateEdgeFadeMask() {
        let inset = collectionView.adjustedContentInset
        let minimumOffsetX = -inset.left
        let maximumOffsetX = max(
            minimumOffsetX,
            collectionView.contentSize.width
                - collectionView.bounds.width
                + inset.right
        )
        let threshold: CGFloat = 0.5
        let showsLeftFade =
            collectionView.contentOffset.x > minimumOffsetX + threshold
        let showsRightFade =
            collectionView.contentOffset.x < maximumOffsetX - threshold

        let maskBounds = collectionView.bounds.insetBy(
            dx: -Layout.selectionBorderWidth,
            dy: -Layout.selectionBorderWidth
        )
        let width = maskBounds.width
        guard width > 0 else { return }

        let fadeLocation = NSNumber(
            value: min(Layout.edgeFadeWidth, width / 2) / width
        )
        let trailingFadeLocation = NSNumber(
            value: 1 - fadeLocation.doubleValue
        )
        let transparent = UIColor.clear.cgColor
        let opaque = UIColor.black.cgColor
        let colors = [
            showsLeftFade ? transparent : opaque,
            opaque,
            opaque,
            showsRightFade ? transparent : opaque
        ]
        let visibilityChanged =
            showsLeftFade != isShowingLeftFade
            || showsRightFade != isShowingRightFade
        let shouldAnimate = hasConfiguredEdgeFadeMask && visibilityChanged
        let currentColors =
            edgeFadeMaskLayer.presentation()?.colors
            ?? edgeFadeMaskLayer.colors

        isShowingLeftFade = showsLeftFade
        isShowingRightFade = showsRightFade
        hasConfiguredEdgeFadeMask = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeFadeMaskLayer.colors = colors
        edgeFadeMaskLayer.locations = [
            0,
            fadeLocation,
            trailingFadeLocation,
            1
        ]
        edgeFadeMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        edgeFadeMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        edgeFadeMaskLayer.frame = maskBounds
        collectionView.layer.mask = edgeFadeMaskLayer
        CATransaction.commit()

        guard shouldAnimate else { return }

        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = currentColors
        animation.toValue = colors
        animation.duration = Layout.edgeFadeTransitionDuration
        animation.timingFunction = CAMediaTimingFunction(
            name: .easeInEaseOut
        )
        edgeFadeMaskLayer.add(animation, forKey: "edgeFadeTransition")
    }
}

extension RealtimeReferenceListView: UICollectionViewDataSource,
    UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        references.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: RealtimeReferenceCell.reuseIdentifier,
                for: indexPath
            ) as? RealtimeReferenceCell
        else {
            return UICollectionViewCell()
        }

        let reference = references[indexPath.item]
        cell.configure(
            reference: reference,
            isSelected: reference.id == selectedReferenceID
        )
        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateEdgeFadeMask()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        let previousReferenceID = selectedReferenceID
        let reference = references[indexPath.item]
        let isCancellingSelection = previousReferenceID == reference.id
        selectedReferenceID = isCancellingSelection ? nil : reference.id
        feedbackGenerator.selectionChanged()

        let changedIndexPaths = references.enumerated().compactMap {
            index, item -> IndexPath? in
            guard
                item.id == previousReferenceID
                || item.id == selectedReferenceID
            else {
                return nil
            }
            return IndexPath(item: index, section: 0)
        }
        collectionView.reloadItems(at: changedIndexPaths)
        if isCancellingSelection {
            onSelectionChanged?(nil)
        } else {
            collectionView.scrollToItem(
                at: indexPath,
                at: .centeredHorizontally,
                animated: true
            )
            onSelectionChanged?(reference)
        }
    }
}

private final class RealtimeReferenceCell: UICollectionViewCell {
    static let reuseIdentifier = "RealtimeReferenceCell"

    private let selectionBorderView = UIView()
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false

        selectionBorderView.backgroundColor = .clear
        selectionBorderView.layer.borderWidth = Layout.selectionBorderWidth
        selectionBorderView.layer.borderColor = UIColor.feed(rgb: 0xFF2E88).cgColor
        selectionBorderView.layer.cornerRadius = 12
        selectionBorderView.isHidden = true
        selectionBorderView.isUserInteractionEnabled = false

        contentView.backgroundColor = .feed(rgb: 0x303032)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        insertSubview(selectionBorderView, belowSubview: contentView)
        contentView.addSubview(imageView)

        selectionBorderView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
                .inset(-Layout.selectionBorderWidth)
        }
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        selectionBorderView.isHidden = true
    }

    func configure(
        reference: RealtimeReferenceCatalog.Item,
        isSelected: Bool
    ) {
        accessibilityLabel = reference.title
        selectionBorderView.isHidden = !isSelected
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        loadImage(from: reference.iconURL)
    }

    private func loadImage(from url: URL) {
        let scale = max(traitCollection.displayScale, 1)
        imageView.kf.setImage(
            with: url,
            options: [
                .processor(
                    DownsamplingImageProcessor(
                        size: CGSize(width: 75, height: 75)
                    )
                ),
                .scaleFactor(scale),
                .transition(.fade(0.2)),
                .cacheOriginalImage
            ]
        )
    }

    private enum Layout {
        static let selectionBorderWidth: CGFloat = 2
    }
}

private final class RealtimePromptFieldView: UIView, UITextFieldDelegate {
    var onBeginEditing: ((String) -> Void)?

    private let textField = UITextField()
    private let submitControl = RealtimePromptCircleView(
        imageName: "realtime_prompt_submit",
        imageSize: CGSize(width: 13, height: 14),
        backgroundColor: .feed(rgb: 0xFF2E88)
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feed(rgb: 0x272728)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.attributedPlaceholder = NSAttributedString(
            string: "输入你想要的效果",
            attributes: [
                .foregroundColor: UIColor.white.withAlphaComponent(0.5),
                .font: UIFont.systemFont(ofSize: 14)
            ]
        )
        textField.textColor = .white
        textField.font = .systemFont(ofSize: 14)
        textField.returnKeyType = .send
        textField.delegate = self
        textField.addTarget(
            self,
            action: #selector(textDidChange),
            for: .editingChanged
        )

        let addControl = RealtimePromptCircleView(
            imageName: "realtime_prompt_add",
            imageSize: CGSize(width: 14, height: 14),
            backgroundColor: .white.withAlphaComponent(0.12)
        )

        addSubview(textField)
        addSubview(addControl)
        addSubview(submitControl)
        submitControl.alpha = 0.2

        textField.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(11)
            make.verticalEdges.equalToSuperview()
            make.trailing.equalTo(addControl.snp.leading).offset(-10)
        }
        addControl.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.size.equalTo(32)
        }
        submitControl.snp.makeConstraints { make in
            make.leading.equalTo(addControl.snp.trailing).offset(8)
            make.trailing.equalToSuperview().offset(-8)
            make.centerY.equalToSuperview()
            make.size.equalTo(32)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func textDidChange() {
        let hasText = !(textField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        submitControl.alpha = hasText ? 1 : 0.2
    }

    func setText(_ text: String) {
        textField.text = text
        textDidChange()
    }

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        onBeginEditing?(textField.text ?? "")
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

private final class RealtimePromptKeyboardView: UIView, UITextViewDelegate {
    static let preferredHeight: CGFloat = 138

    var onTextChange: ((String) -> Void)?
    var onSubmit: ((String) -> Void)?

    private let contentView = UIView()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let addButton = UIButton(type: .custom)
    private let submitButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feed(rgb: 0x101010)

        contentView.backgroundColor = .feed(rgb: 0x252525)
        contentView.layer.cornerRadius = 15
        contentView.layer.cornerCurve = .continuous

        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = .systemFont(ofSize: 14)
        textView.keyboardAppearance = .dark
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.showsVerticalScrollIndicator = false
        textView.delegate = self

        placeholderLabel.text = "输入你想要的效果"
        placeholderLabel.textColor = .white.withAlphaComponent(0.5)
        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.isUserInteractionEnabled = false

        configureButton(
            addButton,
            imageName: "realtime_prompt_add",
            imageSize: CGSize(width: 12, height: 12),
            backgroundColor: .white.withAlphaComponent(0.10)
        )
        addButton.accessibilityLabel = "添加自定义模式参考图"

        configureButton(
            submitButton,
            imageName: "realtime_prompt_submit",
            imageSize: CGSize(width: 11, height: 12),
            backgroundColor: .feed(rgb: 0xFF2E88)
        )
        submitButton.accessibilityLabel = "提交自定义模式描述"
        submitButton.addTarget(
            self,
            action: #selector(submitPrompt),
            for: .touchUpInside
        )

        addSubview(contentView)
        contentView.addSubview(textView)
        contentView.addSubview(placeholderLabel)
        contentView.addSubview(addButton)
        contentView.addSubview(submitButton)

        contentView.snp.makeConstraints { make in
            make.horizontalEdges.equalToSuperview().inset(14)
            make.verticalEdges.equalToSuperview().inset(14)
        }
        textView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.horizontalEdges.equalToSuperview().inset(12)
            make.bottom.equalTo(addButton.snp.top).offset(-8)
        }
        placeholderLabel.snp.makeConstraints { make in
            make.top.leading.equalTo(textView)
            make.trailing.lessThanOrEqualTo(textView)
        }
        submitButton.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(8)
            make.size.equalTo(28)
        }
        addButton.snp.makeConstraints { make in
            make.trailing.equalTo(submitButton.snp.leading).offset(-8)
            make.centerY.equalTo(submitButton)
            make.size.equalTo(28)
        }
        updateState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginEditing(text: String) {
        textView.text = text
        updateState()
        DispatchQueue.main.async { [weak self] in
            self?.textView.becomeFirstResponder()
        }
    }

    func endEditing() {
        textView.resignFirstResponder()
    }

    func textViewDidChange(_ textView: UITextView) {
        updateState()
        onTextChange?(textView.text)
    }

    private func configureButton(
        _ button: UIButton,
        imageName: String,
        imageSize: CGSize,
        backgroundColor: UIColor
    ) {
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 14
        button.clipsToBounds = true
        button.tintColor = .white
        button.setImage(
            UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        button.imageView?.contentMode = .scaleAspectFit
        button.imageView?.snp.makeConstraints { make in
            make.size.equalTo(imageSize)
        }
    }

    private func normalizedPrompt() -> String {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateState() {
        placeholderLabel.isHidden = !textView.text.isEmpty
        let isEnabled = !normalizedPrompt().isEmpty
        submitButton.isEnabled = isEnabled
        submitButton.alpha = isEnabled ? 1 : 0.2
    }

    @objc private func submitPrompt() {
        let prompt = normalizedPrompt()
        guard !prompt.isEmpty else { return }
        onSubmit?(prompt)
    }
}

private final class RealtimePromptCircleView: UIView {
    init(
        imageName: String,
        imageSize: CGSize,
        backgroundColor: UIColor
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = backgroundColor
        layer.cornerRadius = 16
        clipsToBounds = true

        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(imageSize)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
