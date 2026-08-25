import AVFoundation
import PhotosUI
import SnapKit
import UIKit
import UniformTypeIdentifiers
import XmaxSDK

final class StorageViewController: UIViewController {
    private enum MediaKind: Sendable {
        case image
        case video

        var title: String { self == .image ? "图片" : "视频" }
    }

    private static let apiKeyStorageKey = "xlab.realtime.apiKey"
    private let orange = FeedPalette.orange
    private let topBar = UIView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let pickerContainer = UIView()
    private let emptyPickerContent = UIView()
    private let imagePreview = UIImageView()
    private let videoPreview = StorageVideoPreviewView()
    private let pickerButton = UIButton(type: .custom)
    private let reselectButton = UIButton(type: .custom)
    private let selectHint = UILabel()
    private let videoSafetyHint = UILabel()
    private let typeValue = UILabel()
    private let resolutionValue = UILabel()
    private let sizeValue = UILabel()
    private let uploadProgressRow = UIStackView()
    private let uploadProgressLabel = UILabel()
    private let uploadModeLabel = UILabel()
    private let uploadProgressView = UIProgressView(progressViewStyle: .default)
    private let imageActions = UIStackView()
    private let safetyUploadButton = UIButton(type: .custom)
    private let normalUploadButton = UIButton(type: .custom)
    private let videoUploadButton = UIButton(type: .custom)
    private let errorContainer = UIView()
    private let errorLabel = UILabel()
    private let resultCard = FeedCardView(
        colors: [.feed(rgb: 0x1B1712, alpha: 0.93), .feed(rgb: 0x111216, alpha: 0.91)],
        cornerRadius: 18,
        borderColor: FeedPalette.orange.withAlphaComponent(0.35),
        shadowRadius: 18,
        shadowOffset: CGSize(width: 0, height: 8)
    )
    private let elapsedValue = UILabel()
    private let remoteURLLabel = UILabel()
    private let copyButton = UIButton(type: .custom)

    private var selectedFileURL: URL?
    private var selectedMediaKind: MediaKind = .image
    private var uploadedURL: URL?
    private var uploadTask: Task<Void, Never>?
    private var isPicking = false
    private var isUploading = false
    private var activeUploadUsesSafetyCheck = false

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .feed(rgb: 0x090A0C)
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureBackgroundGlow()
        configureTopBar()
        configureScrollView()
        populateContent()
        refreshState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    deinit { uploadTask?.cancel() }

    private func configureBackgroundGlow() {
        let primary = makeGlow(color: orange.withAlphaComponent(0.20), diameter: 280, blurRadius: 86)
        let secondary = makeGlow(color: .feed(rgb: 0xC67A35, alpha: 0.09), diameter: 180, blurRadius: 76)
        view.addSubview(primary)
        view.addSubview(secondary)
        primary.snp.makeConstraints { make in
            make.size.equalTo(280)
            make.trailing.equalToSuperview().offset(150)
            make.top.equalToSuperview().offset(-70)
        }
        secondary.snp.makeConstraints { make in
            make.size.equalTo(180)
            make.leading.equalToSuperview().offset(-130)
            make.top.equalToSuperview().offset(310)
        }
    }

    private func configureTopBar() {
        view.addSubview(topBar)
        let backButton = UIButton(type: .custom)
        backButton.setImage(UIImage(named: "realtime_nav_back"), for: .normal)
        backButton.imageView?.contentMode = .scaleAspectFit
        backButton.accessibilityLabel = "返回首页"
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        let title = makeFeedLabel("存储服务", size: 20, weight: .bold, color: FeedPalette.primaryText)
        let subtitle = makeFeedLabel("EXAMPLE / IOS", size: 8, color: orange.withAlphaComponent(0.72), letterSpacing: 1)
        let titleStack = feedVerticalStack([title, subtitle], spacing: 3)
        let version = FeedPillView(
            text: "v\(XmaxSDKInfo.version)", foregroundColor: orange,
            backgroundColor: orange.withAlphaComponent(0.14), borderColor: orange.withAlphaComponent(0.29),
            fontSize: 8, horizontalPadding: 9, height: 25
        )
        topBar.addSubview(backButton)
        topBar.addSubview(titleStack)
        topBar.addSubview(version)
        topBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.horizontalEdges.equalToSuperview()
            make.height.equalTo(72)
        }
        backButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(44)
        }
        titleStack.snp.makeConstraints { make in
            make.leading.equalTo(backButton.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
        }
        version.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-18)
            make.centerY.equalToSuperview()
        }
    }

    private func configureScrollView() {
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 0
        scrollView.addSubview(contentStack)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(topBar.snp.bottom)
            make.horizontalEdges.bottom.equalToSuperview()
        }
        contentStack.snp.makeConstraints { make in
            make.leading.equalTo(scrollView.contentLayoutGuide).offset(18)
            make.trailing.equalTo(scrollView.contentLayoutGuide).offset(-18)
            make.top.equalTo(scrollView.contentLayoutGuide).offset(12)
            make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-32)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-36)
        }
    }

    private func populateContent() {
        contentStack.addArrangedSubview(makePipelineOverviewCard())
        contentStack.addArrangedSubview(feedFixedSpacer(height: 14))
        contentStack.addArrangedSubview(makeFilePreviewCard())
        errorContainer.backgroundColor = .feed(rgb: 0xFF5F68, alpha: 0.16)
        errorContainer.layer.cornerRadius = 11
        errorContainer.layer.borderWidth = 1
        errorContainer.layer.borderColor = UIColor.feed(rgb: 0xFF6B72, alpha: 0.22).cgColor
        errorContainer.clipsToBounds = true
        errorLabel.font = .systemFont(ofSize: 10)
        errorLabel.textColor = .feed(rgb: 0xFFB5B5)
        errorLabel.numberOfLines = 0
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.setContentHuggingPriority(.required, for: .vertical)
        errorLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        errorContainer.addSubview(errorLabel)
        errorLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 11, left: 12, bottom: 11, right: 12))
        }
        contentStack.addArrangedSubview(errorContainer)
        contentStack.setCustomSpacing(12, after: contentStack.arrangedSubviews[2])
        configureResultCard()
        contentStack.addArrangedSubview(resultCard)
        contentStack.setCustomSpacing(14, after: errorContainer)
    }

    private func makePipelineOverviewCard() -> UIView {
        let card = FeedCardView(
            colors: [.feed(rgb: 0x1D1711, alpha: 0.94), .feed(rgb: 0x0F1115, alpha: 0.91)],
            cornerRadius: 18, borderColor: orange.withAlphaComponent(0.24),
            shadowRadius: 20, shadowOffset: CGSize(width: 0, height: 9)
        )
        let dot = feedDot(color: orange, size: 6, glows: false)
        let eyebrow = makeFeedLabel("STORAGE PIPELINE", size: 9, weight: .bold, color: orange, letterSpacing: 1)
        let ready = FeedPillView(
            text: "READY", foregroundColor: orange, backgroundColor: orange.withAlphaComponent(0.13),
            borderColor: .clear, fontSize: 8, horizontalPadding: 9, height: 23
        )
        let header = feedHorizontalStack([feedHorizontalStack([dot, eyebrow], spacing: 7), feedFlexibleSpacer(), ready])
        let title = makeFeedLabel("把本地媒体交给 XmaxSDK", size: 18, weight: .bold, color: .feed(rgb: 0xF4EEE6))
        let subtitleText = "选择图片或视频，上传后获取可直接使用的远程地址。"
        let subtitle = makeFeedLabel(subtitleText, size: 10, color: .feed(rgb: 0x8E8377))
        subtitle.numberOfLines = 0
        subtitle.attributedText = feedAttributedText(subtitleText, font: subtitle.font, color: subtitle.textColor, lineHeight: 17)
        let localFile = makeFeedLabel("LOCAL FILE", size: 8, weight: .bold, color: .feed(rgb: 0x9A8B7A))
        let firstSeparator = makeFeedLabel("—", size: 9, color: .feed(rgb: 0x66513A))
        let sdk = makeFeedLabel("XMAX SDK", size: 8, weight: .bold, color: orange)
        let secondSeparator = makeFeedLabel("—", size: 9, color: .feed(rgb: 0x66513A))
        let remoteURL = makeFeedLabel("REMOTE URL", size: 8, weight: .bold, color: .feed(rgb: 0x9A8B7A))
        let pipeline = feedHorizontalStack([
            localFile,
            firstSeparator,
            sdk,
            secondSeparator,
            remoteURL,
            feedFlexibleSpacer()
        ], spacing: 8)
        pipeline.setCustomSpacing(0, after: remoteURL)
        let stack = feedVerticalStack([header, title, subtitle, pipeline])
        stack.setCustomSpacing(13, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(15, after: subtitle)
        card.contentView.addSubview(stack)
        stack.snp.makeConstraints { make in make.edges.equalToSuperview().inset(17) }
        return card
    }

    private func makeFilePreviewCard() -> UIView {
        let card = FeedCardView(
            colors: [.feed(rgb: 0x1B1712, alpha: 0.93), .feed(rgb: 0x111216, alpha: 0.91)],
            cornerRadius: 18, borderColor: orange.withAlphaComponent(0.18),
            shadowRadius: 16, shadowOffset: CGSize(width: 0, height: 7)
        )
        let step = FeedPillView(
            text: "01", foregroundColor: orange, backgroundColor: orange.withAlphaComponent(0.13),
            borderColor: orange.withAlphaComponent(0.27), fontSize: 8,
            horizontalPadding: 8, height: 22, letterSpacing: 0
        )
        step.snp.makeConstraints { make in make.width.equalTo(28) }
        let title = makeFeedLabel("文件预览", size: 13, weight: .bold, color: .feed(rgb: 0xF2ECE4))
        selectHint.font = .systemFont(ofSize: 9, weight: .bold)
        selectHint.textColor = .feed(rgb: 0x6E6257)
        selectHint.text = "点击选择"
        configureOutlineButton(reselectButton, title: "重新上传", height: 28)
        reselectButton.titleLabel?.font = .systemFont(ofSize: 9, weight: .bold)
        reselectButton.addTarget(self, action: #selector(selectMedia), for: .touchUpInside)
        reselectButton.snp.makeConstraints { make in make.width.equalTo(66) }
        let trailingHeader = UIView()
        trailingHeader.addSubview(selectHint)
        trailingHeader.addSubview(reselectButton)
        selectHint.snp.makeConstraints { make in make.edges.equalToSuperview() }
        reselectButton.snp.makeConstraints { make in make.edges.equalToSuperview() }
        let header = feedHorizontalStack([step, title, feedFlexibleSpacer(), trailingHeader], spacing: 9)
        videoSafetyHint.font = .systemFont(ofSize: 9)
        videoSafetyHint.textColor = .feed(rgb: 0x596678)
        videoSafetyHint.text = "视频生成暂不支持安全检测"
        configurePicker()
        let typeMetric = makeMetadataView(label: "type", valueLabel: typeValue)
        let resolutionMetric = makeMetadataView(label: "resolution", valueLabel: resolutionValue)
        let sizeMetric = makeMetadataView(label: "size", valueLabel: sizeValue)
        let metadata = feedHorizontalStack([typeMetric, resolutionMetric, sizeMetric], spacing: 8)
        typeMetric.snp.makeConstraints { make in make.width.equalTo(resolutionMetric) }
        resolutionMetric.snp.makeConstraints { make in make.width.equalTo(sizeMetric) }
        configureUploadControls()
        let stack = feedVerticalStack([
            header, videoSafetyHint, pickerContainer, metadata,
            uploadProgressRow, uploadProgressView, imageActions, videoUploadButton
        ])
        stack.setCustomSpacing(10, after: header)
        stack.setCustomSpacing(10, after: videoSafetyHint)
        stack.setCustomSpacing(10, after: pickerContainer)
        stack.setCustomSpacing(16, after: metadata)
        stack.setCustomSpacing(7, after: uploadProgressRow)
        stack.setCustomSpacing(16, after: uploadProgressView)
        card.contentView.addSubview(stack)
        stack.snp.makeConstraints { make in make.edges.equalToSuperview().inset(17) }
        return card
    }

    private func configurePicker() {
        pickerContainer.backgroundColor = .feed(rgb: 0x0B0C0F, alpha: 0.56)
        pickerContainer.layer.cornerRadius = 14
        pickerContainer.layer.borderWidth = 1
        pickerContainer.layer.borderColor = orange.withAlphaComponent(0.15).cgColor
        pickerContainer.clipsToBounds = true
        pickerContainer.snp.makeConstraints { make in make.height.equalTo(176) }
        let plus = makeFeedLabel("+", size: 22, color: orange)
        plus.textAlignment = .center
        plus.backgroundColor = orange.withAlphaComponent(0.09)
        plus.layer.cornerRadius = 21
        plus.layer.borderWidth = 1
        plus.layer.borderColor = orange.withAlphaComponent(0.24).cgColor
        plus.clipsToBounds = true
        plus.snp.makeConstraints { make in make.size.equalTo(42) }
        let pickerTitle = makeFeedLabel("点击选择图片或视频", size: 11, weight: .bold, color: .feed(rgb: 0x9D9185))
        let pickerType = makeFeedLabel("IMAGE  /  VIDEO", size: 8, color: .feed(rgb: 0x62584E), letterSpacing: 0.8)
        let pickerStack = feedVerticalStack([plus, pickerTitle, pickerType])
        pickerStack.alignment = .center
        pickerStack.setCustomSpacing(11, after: plus)
        pickerStack.setCustomSpacing(5, after: pickerTitle)
        emptyPickerContent.addSubview(pickerStack)
        pickerStack.snp.makeConstraints { make in make.center.equalToSuperview() }
        imagePreview.contentMode = .scaleAspectFit
        pickerContainer.addSubview(emptyPickerContent)
        pickerContainer.addSubview(imagePreview)
        pickerContainer.addSubview(videoPreview)
        pickerContainer.addSubview(pickerButton)
        [emptyPickerContent, imagePreview, videoPreview, pickerButton].forEach { child in
            child.snp.makeConstraints { make in make.edges.equalToSuperview() }
        }
        pickerButton.accessibilityLabel = "选择图片或视频"
        pickerButton.addTarget(self, action: #selector(selectMedia), for: .touchUpInside)
    }

    private func configureUploadControls() {
        uploadProgressRow.axis = .horizontal
        uploadProgressRow.alignment = .center
        uploadProgressLabel.font = .systemFont(ofSize: 10)
        uploadProgressLabel.textColor = orange
        uploadModeLabel.font = .systemFont(ofSize: 9)
        uploadModeLabel.textColor = .feed(rgb: 0x657386)
        uploadProgressRow.addArrangedSubview(uploadProgressLabel)
        uploadProgressRow.addArrangedSubview(feedFlexibleSpacer())
        uploadProgressRow.addArrangedSubview(uploadModeLabel)
        uploadProgressView.progressTintColor = orange
        uploadProgressView.trackTintColor = orange.withAlphaComponent(0.14)
        uploadProgressView.layer.cornerRadius = 2.5
        uploadProgressView.clipsToBounds = true
        uploadProgressView.snp.makeConstraints { make in make.height.equalTo(5) }
        configureOutlineButton(safetyUploadButton, title: "安全检测上传")
        configureOutlineButton(normalUploadButton, title: "普通上传")
        configureOutlineButton(videoUploadButton, title: "上传并获取地址")
        safetyUploadButton.addTarget(self, action: #selector(uploadWithSafetyCheck), for: .touchUpInside)
        normalUploadButton.addTarget(self, action: #selector(uploadNormally), for: .touchUpInside)
        videoUploadButton.addTarget(self, action: #selector(uploadNormally), for: .touchUpInside)
        imageActions.axis = .horizontal
        imageActions.spacing = 10
        imageActions.distribution = .fillEqually
        imageActions.addArrangedSubview(safetyUploadButton)
        imageActions.addArrangedSubview(normalUploadButton)
    }

    private func configureResultCard() {
        let step = FeedPillView(
            text: "02", foregroundColor: orange, backgroundColor: orange.withAlphaComponent(0.13),
            borderColor: orange.withAlphaComponent(0.27), fontSize: 8,
            horizontalPadding: 8, height: 22, letterSpacing: 0
        )
        step.snp.makeConstraints { make in make.width.equalTo(28) }
        let title = makeFeedLabel("上传结果", size: 13, weight: .bold, color: .feed(rgb: 0xF2ECE4))
        let success = FeedPillView(
            text: "SUCCESS", foregroundColor: orange, backgroundColor: orange.withAlphaComponent(0.07),
            borderColor: orange.withAlphaComponent(0.22), fontSize: 9, horizontalPadding: 10, height: 28
        )
        success.snp.makeConstraints { make in make.width.equalTo(66) }
        let header = feedHorizontalStack([step, title, feedFlexibleSpacer(), success], spacing: 9)
        let elapsedTitle = makeFeedLabel("上传耗时", size: 10, color: .feed(rgb: 0x718095))
        elapsedValue.font = .systemFont(ofSize: 10, weight: .bold)
        elapsedValue.textColor = orange
        let elapsedRow = feedHorizontalStack([elapsedTitle, feedFlexibleSpacer(), elapsedValue])
        let urlTitle = makeFeedLabel("REMOTE URL", size: 8, weight: .bold, color: .feed(rgb: 0x667589), letterSpacing: 0.8)
        remoteURLLabel.font = .systemFont(ofSize: 9)
        remoteURLLabel.textColor = .feed(rgb: 0xCDBEAF)
        remoteURLLabel.numberOfLines = 0
        remoteURLLabel.backgroundColor = .feed(rgb: 0x0B0C0F, alpha: 0.58)
        remoteURLLabel.layer.cornerRadius = 11
        remoteURLLabel.layer.borderWidth = 1
        remoteURLLabel.layer.borderColor = orange.withAlphaComponent(0.13).cgColor
        remoteURLLabel.clipsToBounds = true
        remoteURLLabel.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(52) }
        configureOutlineButton(copyButton, title: "复制地址")
        copyButton.addTarget(self, action: #selector(copyUploadedURL), for: .touchUpInside)
        let stack = feedVerticalStack([header, elapsedRow, urlTitle, remoteURLLabel, copyButton])
        stack.setCustomSpacing(15, after: header)
        stack.setCustomSpacing(14, after: elapsedRow)
        stack.setCustomSpacing(7, after: urlTitle)
        stack.setCustomSpacing(12, after: remoteURLLabel)
        resultCard.contentView.addSubview(stack)
        stack.snp.makeConstraints { make in make.edges.equalToSuperview().inset(17) }
    }

    private func makeMetadataView(label: String, valueLabel: UILabel) -> UIView {
        let container = UIView()
        container.backgroundColor = .feed(rgb: 0x0C0D10, alpha: 0.54)
        container.layer.cornerRadius = 10
        let labelView = makeFeedLabel(label, size: 8, color: .feed(rgb: 0x6E6257))
        valueLabel.font = .systemFont(ofSize: label == "type" ? 10 : 9, weight: .bold)
        valueLabel.textColor = .feed(rgb: 0xB9AA9B)
        valueLabel.text = "--"
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.72
        let stack = feedVerticalStack([labelView, valueLabel], spacing: 4)
        container.addSubview(stack)
        container.snp.makeConstraints { make in make.height.equalTo(51) }
        stack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(11)
            make.trailing.lessThanOrEqualToSuperview().offset(-6)
            make.centerY.equalToSuperview()
        }
        return container
    }

    private func configureOutlineButton(_ button: UIButton, title: String, height: CGFloat = 38) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(orange, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        button.backgroundColor = orange.withAlphaComponent(0.08)
        button.layer.cornerRadius = height == 38 ? 12 : 9
        button.layer.borderWidth = 1
        button.layer.borderColor = orange.withAlphaComponent(0.28).cgColor
        button.snp.makeConstraints { make in make.height.equalTo(height) }
    }

    private func makeGlow(color: UIColor, diameter: CGFloat, blurRadius: CGFloat) -> UIView {
        let glow = UIView()
        glow.backgroundColor = color
        glow.layer.cornerRadius = diameter / 2
        glow.layer.shadowColor = color.cgColor
        glow.layer.shadowOpacity = 1
        glow.layer.shadowRadius = blurRadius
        glow.layer.shadowOffset = .zero
        return glow
    }

    private func refreshState() {
        let hasSelection = selectedFileURL != nil
        let displaysImage = hasSelection && selectedMediaKind == .image
        let displaysVideo = hasSelection && selectedMediaKind == .video
        emptyPickerContent.isHidden = hasSelection
        imagePreview.isHidden = !displaysImage
        videoPreview.isHidden = !displaysVideo
        pickerButton.isHidden = hasSelection
        selectHint.isHidden = hasSelection
        reselectButton.isHidden = !hasSelection
        videoSafetyHint.isHidden = !displaysVideo
        imageActions.isHidden = !displaysImage
        videoUploadButton.isHidden = !displaysVideo
        uploadProgressRow.isHidden = !isUploading
        uploadProgressView.isHidden = !isUploading
        resultCard.isHidden = uploadedURL == nil
        errorContainer.isHidden = errorLabel.text?.isEmpty != false && errorLabel.attributedText?.string.isEmpty != false
        let enabled = !isPicking && !isUploading
        pickerButton.isEnabled = enabled
        reselectButton.isEnabled = enabled
        safetyUploadButton.isEnabled = enabled
        normalUploadButton.isEnabled = enabled
        videoUploadButton.isEnabled = enabled
        [reselectButton, safetyUploadButton, normalUploadButton, videoUploadButton].forEach {
            $0.alpha = $0.isEnabled ? 1 : 0.6
        }
    }

    @objc private func selectMedia() {
        guard !isPicking, !isUploading else { return }
        isPicking = true
        refreshState()
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func loadSelectedMedia(from result: PHPickerResult) {
        let provider = result.itemProvider
        let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        let kind: MediaKind = isVideo ? .video : .image
        let type = isVideo ? UTType.movie : UTType.image
        let registeredType = provider.registeredTypeIdentifiers.compactMap(UTType.init).first { registeredType in
            kind == .video ? registeredType.conforms(to: .movie) : registeredType.conforms(to: .image)
        }
        let loadingTypeIdentifier = registeredType?.identifier ?? type.identifier
        let preferredExtension = registeredType?.preferredFilenameExtension
        provider.loadFileRepresentation(forTypeIdentifier: loadingTypeIdentifier) { [weak self] sourceURL, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.finishPicking(error: error) }
                return
            }
            guard let sourceURL else {
                DispatchQueue.main.async { self.finishPicking(error: StoragePageError.unreadableSelection) }
                return
            }
            do {
                let localURL = try Self.copyToCache(sourceURL, kind: kind, preferredExtension: preferredExtension)
                let metadata = Self.readMetadata(at: localURL, kind: kind)
                DispatchQueue.main.async { self.applySelection(url: localURL, kind: kind, metadata: metadata) }
            } catch {
                DispatchQueue.main.async { self.finishPicking(error: error) }
            }
        }
    }

    private nonisolated static func copyToCache(
        _ sourceURL: URL,
        kind: MediaKind,
        preferredExtension: String?
    ) throws -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = cachesDirectory.appendingPathComponent("storage_playground", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var fileExtension = sourceURL.pathExtension
        if fileExtension.isEmpty {
            fileExtension = preferredExtension ?? (kind == .video ? "mp4" : "jpg")
        }
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private nonisolated static func readMetadata(
        at url: URL,
        kind: MediaKind
    ) -> (resolution: String, size: String) {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let resolution: String
        switch kind {
        case .image:
            if let cgImage = UIImage(contentsOfFile: url.path)?.cgImage {
                resolution = "\(cgImage.width) × \(cgImage.height)"
            } else {
                resolution = ""
            }
        case .video:
            let asset = AVURLAsset(url: url)
            if let track = asset.tracks(withMediaType: .video).first {
                let transformed = track.naturalSize.applying(track.preferredTransform)
                resolution = "\(Int(abs(transformed.width).rounded())) × \(Int(abs(transformed.height).rounded()))"
            } else {
                resolution = ""
            }
        }
        return (resolution, ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
    }

    private func applySelection(url: URL, kind: MediaKind, metadata: (resolution: String, size: String)) {
        selectedFileURL = url
        selectedMediaKind = kind
        uploadedURL = nil
        isPicking = false
        errorLabel.text = nil
        errorLabel.attributedText = nil
        uploadProgressView.progress = 0
        typeValue.text = kind.title
        typeValue.textColor = .feed(rgb: 0xE7DED4)
        resolutionValue.text = metadata.resolution.isEmpty ? "--" : metadata.resolution
        sizeValue.text = metadata.size
        if kind == .image {
            videoPreview.stop()
            imagePreview.image = UIImage(contentsOfFile: url.path)
        } else {
            imagePreview.image = nil
            videoPreview.play(url: url)
        }
        refreshState()
    }

    private func finishPicking(error: Error?) {
        isPicking = false
        if let error { showError(error, fallback: "读取文件失败，请重试") }
        refreshState()
    }

    @objc private func uploadWithSafetyCheck() { uploadSelectedFile(withSafetyCheck: true) }
    @objc private func uploadNormally() { uploadSelectedFile(withSafetyCheck: false) }

    private func uploadSelectedFile(withSafetyCheck: Bool) {
        guard let fileURL = selectedFileURL, !isUploading else { return }
        isUploading = true
        activeUploadUsesSafetyCheck = withSafetyCheck
        uploadedURL = nil
        errorLabel.text = nil
        errorLabel.attributedText = nil
        uploadProgressView.progress = 0
        uploadProgressLabel.text = "上传中 0%"
        uploadModeLabel.text = selectedMediaKind == .video ? "正在上传视频" : (withSafetyCheck ? "包含内容安全检查" : "正在上传图片")
        updateUploadButtonTitles()
        refreshState()
        let apiKey = UserDefaults.standard.string(forKey: Self.apiKeyStorageKey) ?? ""
        let kind = selectedMediaKind
        let startedAt = Date()
        uploadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let client = XmaxClient(configuration: XmaxConfiguration(apiKey: apiKey))
                let storage = try client.createStorageManager()
                let progress: XmaxStorageProgressHandler = { [weak self] value in
                    let fraction = Float(value.fractionCompleted)
                    DispatchQueue.main.async { self?.applyUploadProgress(fraction) }
                }
                let uploaded: XmaxUploadedFile
                switch kind {
                case .image where withSafetyCheck:
                    uploaded = try await storage.uploadImageWithSafetyCheck(at: fileURL, contentType: nil, progress: progress)
                case .image:
                    uploaded = try await storage.uploadImage(at: fileURL, contentType: nil, progress: progress)
                case .video:
                    uploaded = try await storage.uploadVideo(at: fileURL, contentType: nil, progress: progress)
                }
                await MainActor.run {
                    self.finishUpload(url: uploaded.url, elapsed: Date().timeIntervalSince(startedAt))
                }
            } catch {
                await MainActor.run {
                    self.isUploading = false
                    self.updateUploadButtonTitles()
                    self.showError(error, fallback: "上传失败，请检查 API Key 和网络后重试")
                    self.refreshState()
                }
            }
        }
    }

    private func applyUploadProgress(_ fraction: Float) {
        let clamped = min(max(fraction, 0), 1)
        uploadProgressView.setProgress(clamped, animated: true)
        uploadProgressLabel.text = "上传中 \(Int((clamped * 100).rounded()))%"
    }

    private func finishUpload(url: URL, elapsed: TimeInterval) {
        isUploading = false
        uploadedURL = url
        uploadProgressView.progress = 1
        elapsedValue.text = elapsed < 1 ? "\(Int((elapsed * 1_000).rounded())) ms" : String(format: "%.2f s", elapsed)
        remoteURLLabel.attributedText = paddedText(url.absoluteString)
        updateUploadButtonTitles()
        refreshState()
        view.layoutIfNeeded()
        let maximumOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.setContentOffset(CGPoint(x: 0, y: maximumOffset), animated: true)
    }

    private func updateUploadButtonTitles() {
        safetyUploadButton.setTitle(isUploading && activeUploadUsesSafetyCheck ? "正在检测上传" : "安全检测上传", for: .normal)
        normalUploadButton.setTitle(isUploading && !activeUploadUsesSafetyCheck ? "正在上传" : "普通上传", for: .normal)
        videoUploadButton.setTitle(isUploading ? "正在上传" : "上传并获取地址", for: .normal)
    }

    private func showError(_ error: Error, fallback: String) {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = message.isEmpty ? fallback : message
        let font = UIFont.systemFont(ofSize: 10)
        errorLabel.attributedText = feedAttributedText(
            text,
            font: font,
            color: .feed(rgb: 0xFFB5B5),
            lineHeight: 16
        )
    }

    private func paddedText(
        _ text: String, horizontal: CGFloat = 11, vertical: CGFloat = 8,
        color: UIColor = .feed(rgb: 0xCDBEAF)
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = horizontal
        paragraph.headIndent = horizontal
        paragraph.tailIndent = -horizontal
        paragraph.paragraphSpacingBefore = vertical
        paragraph.paragraphSpacing = vertical
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 9), .foregroundColor: color, .paragraphStyle: paragraph
        ])
    }

    @objc private func copyUploadedURL() {
        guard let uploadedURL else { return }
        UIPasteboard.general.string = uploadedURL.absoluteString
        copyButton.setTitle("地址已复制", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.setTitle("复制地址", for: .normal)
        }
    }

    @objc private func goBack() { navigationController?.popViewController(animated: true) }
}

extension StorageViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else {
            finishPicking(error: nil)
            return
        }
        loadSelectedMedia(from: result)
    }
}

private enum StoragePageError: LocalizedError {
    case unreadableSelection
    var errorDescription: String? { "无法读取所选文件，请重试" }
}

private final class StorageVideoPreviewView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func play(url: URL) {
        stop()
        let player = AVQueuePlayer()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        self.player = player
        playerLayer.player = player
        player.isMuted = true
        player.play()
    }

    func stop() {
        player?.pause()
        playerLayer.player = nil
        looper = nil
        player = nil
    }
}
