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

    private enum Layout {
        static let cardContentInset: CGFloat = 17
        static let sectionTitleFontSize: CGFloat = 13.5
        static let compactControlHeight: CGFloat = 26
        static let compactControlHorizontalPadding: CGFloat = 8
        static let compactControlCornerRadius: CGFloat = 9
        static let resultURLInset: CGFloat = 10
    }

    private static let apiKeyStorageKey = "xlab.realtime.apiKey"
    private let orange = FeedPalette.orange

    // 媒体状态
    private var selectedFileURL: URL?
    private var selectedMediaKind: MediaKind = .image

    // 上传状态
    private var uploadedURL: URL?
    private var uploadTask: Task<Void, Never>?
    private var isPicking = false
    private var isUploading = false
    private var activeUploadUsesSafetyCheck = false

    // 界面组件
    private lazy var topBar = UIView()

    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceVertical = true
        return view
    }()

    private lazy var contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 0
        return stack
    }()

    private lazy var pickerContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .feed(rgb: 0x0B0C0F, alpha: 0.56)
        view.layer.cornerRadius = 14
        view.layer.borderWidth = 1
        view.layer.borderColor = orange.withAlphaComponent(0.15).cgColor
        view.clipsToBounds = true
        view.snp.makeConstraints { make in
            make.height.equalTo(176)
        }
        return view
    }()

    private lazy var emptyPickerContent = UIView()

    private lazy var imagePreview: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var videoPreview = StorageVideoPreviewView()

    private lazy var pickerButton: UIButton = {
        let button = UIButton(type: .custom)
        button.accessibilityLabel = "选择图片或视频"
        button.addTarget(self, action: #selector(selectMedia), for: .touchUpInside)
        return button
    }()

    private lazy var reselectButton: UIButton = {
        let button = UIButton(type: .custom)
        configureOutlineButton(
            button,
            title: "重新上传",
            height: Layout.compactControlHeight,
            fontSize: 8,
            horizontalPadding: Layout.compactControlHorizontalPadding
        )
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(self, action: #selector(selectMedia), for: .touchUpInside)
        return button
    }()

    private lazy var videoSafetyHint: UILabel = {
        let label = UILabel()
        label.font = feedFont(ofSize: 9)
        label.textColor = .feed(rgb: 0x596678)
        label.text = "视频生成暂不支持安全检测"
        return label
    }()

    private lazy var typeValue: UILabel = {
        let label = UILabel()
        configureMetadataValueLabel(label, fontSize: 10)
        return label
    }()

    private lazy var resolutionValue: UILabel = {
        let label = UILabel()
        configureMetadataValueLabel(label, fontSize: 9)
        return label
    }()

    private lazy var sizeValue: UILabel = {
        let label = UILabel()
        configureMetadataValueLabel(label, fontSize: 9)
        return label
    }()

    private lazy var uploadProgressRow: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        return stack
    }()

    private lazy var uploadProgressLabel: UILabel = {
        let label = UILabel()
        label.font = feedFont(ofSize: 10)
        label.textColor = orange
        return label
    }()

    private lazy var uploadModeLabel: UILabel = {
        let label = UILabel()
        label.font = feedFont(ofSize: 9)
        label.textColor = .feed(rgb: 0x657386)
        return label
    }()

    private lazy var uploadProgressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = orange
        progressView.trackTintColor = orange.withAlphaComponent(0.14)
        progressView.layer.cornerRadius = 2.5
        progressView.clipsToBounds = true
        progressView.snp.makeConstraints { make in
            make.height.equalTo(5)
        }
        return progressView
    }()

    private lazy var imageActions: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 10
        stack.distribution = .fillEqually
        return stack
    }()

    private lazy var safetyUploadButton: UIButton = {
        let button = UIButton(type: .custom)
        configureOutlineButton(button, title: "安全检测上传")
        button.addTarget(self, action: #selector(uploadWithSafetyCheck), for: .touchUpInside)
        return button
    }()

    private lazy var normalUploadButton: UIButton = {
        let button = UIButton(type: .custom)
        configureOutlineButton(button, title: "普通上传")
        button.addTarget(self, action: #selector(uploadNormally), for: .touchUpInside)
        return button
    }()

    private lazy var videoUploadButton: UIButton = {
        let button = UIButton(type: .custom)
        configureOutlineButton(button, title: "上传并获取地址")
        button.addTarget(self, action: #selector(uploadNormally), for: .touchUpInside)
        return button
    }()

    private lazy var errorContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .feed(rgb: 0xFF5F68, alpha: 0.16)
        view.layer.cornerRadius = 11
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.feed(rgb: 0xFF6B72, alpha: 0.22).cgColor
        view.clipsToBounds = true
        return view
    }()

    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 10)
        label.textColor = .feed(rgb: 0xFFB5B5)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private lazy var resultCard = FeedCardView(
        colors: [.feed(rgb: 0x1B1712, alpha: 0.93), .feed(rgb: 0x111216, alpha: 0.91)],
        cornerRadius: 18,
        borderColor: orange.withAlphaComponent(0.35),
        shadowRadius: 18,
        shadowOffset: CGSize(width: 0, height: 8)
    )

    private lazy var elapsedValue: UILabel = {
        let label = UILabel()
        label.font = feedFont(ofSize: 10, weight: .bold)
        label.textColor = orange
        return label
    }()

    private lazy var remoteURLContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .feed(rgb: 0x0B0C0F, alpha: 0.58)
        view.layer.cornerRadius = 11
        view.layer.borderWidth = 1
        view.layer.borderColor = orange.withAlphaComponent(0.13).cgColor
        view.clipsToBounds = true
        view.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(58)
        }
        return view
    }()

    private lazy var remoteURLLabel: UILabel = {
        let label = UILabel()
        label.font = feedFont(ofSize: 10)
        label.textColor = .feed(rgb: 0xCDBEAF)
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private lazy var copyButton: UIButton = {
        let button = UIButton(type: .custom)
        configureOutlineButton(button, title: "复制地址")
        button.addTarget(self, action: #selector(copyUploadedURL), for: .touchUpInside)
        return button
    }()

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
        view.addSubview(scrollView)
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
        let eyebrow = makeFeedLabel(
            "STORAGE PIPELINE",
            size: 9,
            weight: .bold,
            color: orange,
            letterSpacing: 1
        )
        let ready = FeedPillView(
            text: "READY", foregroundColor: orange, backgroundColor: orange.withAlphaComponent(0.13),
            borderColor: .clear, fontSize: 8, horizontalPadding: 9, height: 23
        )
        let header = feedHorizontalStack(
            [feedHorizontalStack([dot, eyebrow], spacing: 7), feedFlexibleSpacer(), ready]
        )
        let title = makeFeedLabel(
            "把本地媒体交给 XmaxSDK",
            size: 18,
            weight: .bold,
            color: .feed(rgb: 0xF4EEE6)
        )
        let subtitleText = "选择图片或视频，上传后获取可直接使用的远程地址。"
        let subtitle = makeFeedLabel(subtitleText, size: 10, color: .feed(rgb: 0x8E8377))
        subtitle.numberOfLines = 0
        subtitle.attributedText = feedAttributedText(
            subtitleText,
            font: subtitle.font,
            color: subtitle.textColor,
            lineHeight: 17
        )
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
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Layout.cardContentInset)
        }
        return card
    }

    private func makeFilePreviewCard() -> UIView {
        let card = FeedCardView(
            colors: [.feed(rgb: 0x1B1712, alpha: 0.93), .feed(rgb: 0x111216, alpha: 0.91)],
            cornerRadius: 18, borderColor: orange.withAlphaComponent(0.18),
            shadowRadius: 16, shadowOffset: CGSize(width: 0, height: 7)
        )
        let step = makeStepPill("01")
        let title = makeFeedLabel(
            "文件预览",
            size: Layout.sectionTitleFontSize,
            weight: .bold,
            color: .feed(rgb: 0xF2ECE4)
        )
        let header = feedHorizontalStack([step, title, feedFlexibleSpacer(), reselectButton], spacing: 9)
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
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Layout.cardContentInset)
        }
        return card
    }

    private func configurePicker() {
        let plusContainer = UIView()
        plusContainer.backgroundColor = orange.withAlphaComponent(0.09)
        plusContainer.layer.cornerRadius = 21
        plusContainer.layer.borderWidth = 1
        plusContainer.layer.borderColor = orange.withAlphaComponent(0.24).cgColor
        plusContainer.clipsToBounds = true
        plusContainer.snp.makeConstraints { make in make.size.equalTo(42) }
        let plusIcon = UIImageView(
            image: UIImage(
                systemName: "plus",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 17,
                    weight: .regular
                )
            )
        )
        plusIcon.tintColor = orange
        plusIcon.contentMode = .center
        plusContainer.addSubview(plusIcon)
        plusIcon.snp.makeConstraints { make in make.center.equalToSuperview() }
        let pickerTitle = makeFeedLabel(
            "点击选择图片或视频",
            size: 12,
            weight: .bold,
            color: .feed(rgb: 0x9D9185)
        )
        let pickerType = makeFeedLabel("IMAGE  /  VIDEO", size: 9, color: .feed(rgb: 0x62584E), letterSpacing: 0.8)
        let pickerStack = feedVerticalStack([plusContainer, pickerTitle, pickerType])
        pickerStack.alignment = .center
        pickerStack.setCustomSpacing(11, after: plusContainer)
        pickerStack.setCustomSpacing(5, after: pickerTitle)
        emptyPickerContent.addSubview(pickerStack)
        pickerStack.snp.makeConstraints { make in make.center.equalToSuperview() }
        pickerContainer.addSubview(emptyPickerContent)
        pickerContainer.addSubview(imagePreview)
        pickerContainer.addSubview(videoPreview)
        pickerContainer.addSubview(pickerButton)
        [emptyPickerContent, imagePreview, videoPreview, pickerButton].forEach { child in
            child.snp.makeConstraints { make in make.edges.equalToSuperview() }
        }
    }

    private func configureUploadControls() {
        uploadProgressRow.addArrangedSubview(uploadProgressLabel)
        uploadProgressRow.addArrangedSubview(feedFlexibleSpacer())
        uploadProgressRow.addArrangedSubview(uploadModeLabel)
        imageActions.addArrangedSubview(safetyUploadButton)
        imageActions.addArrangedSubview(normalUploadButton)
    }

    private func configureResultCard() {
        let step = makeStepPill("02")
        let title = makeFeedLabel(
            "上传结果",
            size: Layout.sectionTitleFontSize,
            weight: .bold,
            color: .feed(rgb: 0xF2ECE4)
        )
        let success = FeedPillView(
            text: "SUCCESS", foregroundColor: orange, backgroundColor: orange.withAlphaComponent(0.08),
            borderColor: orange.withAlphaComponent(0.28), fontSize: 8,
            horizontalPadding: Layout.compactControlHorizontalPadding,
            height: Layout.compactControlHeight,
            cornerRadius: Layout.compactControlCornerRadius
        )
        let header = feedHorizontalStack([step, title, feedFlexibleSpacer(), success], spacing: 9)
        let elapsedTitle = makeFeedLabel("上传耗时", size: 11, color: .feed(rgb: 0x718095))
        let elapsedRow = feedHorizontalStack([elapsedTitle, feedFlexibleSpacer(), elapsedValue])
        let urlTitle = makeFeedLabel(
            "REMOTE URL",
            size: 9,
            weight: .bold,
            color: .feed(rgb: 0x667589),
            letterSpacing: 0.8
        )
        remoteURLContainer.addSubview(remoteURLLabel)
        remoteURLLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Layout.resultURLInset)
        }
        let stack = feedVerticalStack([header, elapsedRow, urlTitle, remoteURLContainer, copyButton])
        stack.setCustomSpacing(15, after: header)
        stack.setCustomSpacing(14, after: elapsedRow)
        stack.setCustomSpacing(7, after: urlTitle)
        stack.setCustomSpacing(12, after: remoteURLContainer)
        resultCard.contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Layout.cardContentInset)
        }
    }

    private func makeStepPill(_ text: String) -> FeedPillView {
        FeedPillView(
            text: text,
            foregroundColor: orange,
            backgroundColor: orange.withAlphaComponent(0.13),
            borderColor: orange.withAlphaComponent(0.27),
            fontSize: 9,
            horizontalPadding: 8,
            height: 22,
            letterSpacing: 0
        )
    }

    private func makeMetadataView(label: String, valueLabel: UILabel) -> UIView {
        let container = UIView()
        container.backgroundColor = .feed(rgb: 0x0C0D10, alpha: 0.54)
        container.layer.cornerRadius = 10
        let labelView = makeFeedLabel(label, size: 9, color: .feed(rgb: 0x6E6257))
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

    private func configureMetadataValueLabel(
        _ label: UILabel,
        fontSize: CGFloat
    ) {
        label.font = feedFont(ofSize: fontSize, weight: .bold)
        label.textColor = .feed(rgb: 0xB9AA9B)
        label.text = "--"
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.72
    }

    private func configureOutlineButton(
        _ button: UIButton,
        title: String,
        height: CGFloat = 38,
        fontSize: CGFloat = 11,
        horizontalPadding: CGFloat = 16
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            incoming in
            var outgoing = incoming
            outgoing.font = feedFont(ofSize: fontSize, weight: .bold)
            return outgoing
        }
        configuration.baseForegroundColor = orange
        button.configuration = configuration
        button.setTitle(title, for: .normal)
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
        reselectButton.isHidden = !hasSelection
        videoSafetyHint.isHidden = !displaysVideo
        imageActions.isHidden = !displaysImage
        videoUploadButton.isHidden = !displaysVideo
        uploadProgressRow.isHidden = !isUploading
        uploadProgressView.isHidden = !isUploading
        resultCard.isHidden = uploadedURL == nil
        errorContainer.isHidden = errorLabel.text?.isEmpty != false
            && errorLabel.attributedText?.string.isEmpty != false
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
        guard !isPicking,
              !isUploading,
              presentedViewController == nil else {
            return
        }

        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
        picker.presentationController?.delegate = self
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
        uploadModeLabel.text = switch selectedMediaKind {
        case .video:
            "正在上传视频"
        case .image where withSafetyCheck:
            "包含内容安全检查"
        case .image:
            "正在上传图片"
        }
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
                    uploaded = try await storage.uploadImageWithSafetyCheck(
                        at: fileURL,
                        contentType: nil,
                        progress: progress
                    )
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
        elapsedValue.text = elapsed < 1
            ? "\(Int((elapsed * 1_000).rounded())) ms"
            : String(format: "%.2f s", elapsed)
        remoteURLLabel.text = url.absoluteString
        updateUploadButtonTitles()
        refreshState()
        view.layoutIfNeeded()
        let maximumOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.setContentOffset(CGPoint(x: 0, y: maximumOffset), animated: true)
    }

    private func updateUploadButtonTitles() {
        safetyUploadButton.setTitle(
            isUploading && activeUploadUsesSafetyCheck ? "正在检测上传" : "安全检测上传",
            for: .normal
        )
        normalUploadButton.setTitle(
            isUploading && !activeUploadUsesSafetyCheck ? "正在上传" : "普通上传",
            for: .normal
        )
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

    @objc private func copyUploadedURL() {
        guard let uploadedURL else { return }
        UIPasteboard.general.string = uploadedURL.absoluteString
        XLToast.show("地址已复制", in: view, duration: 2)
    }

    @objc private func goBack() { navigationController?.popViewController(animated: true) }
}

extension StorageViewController: PHPickerViewControllerDelegate,
    UIAdaptivePresentationControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else {
            finishPicking(error: nil)
            return
        }
        isPicking = true
        refreshState()
        loadSelectedMedia(from: result)
    }

    func presentationControllerDidDismiss(
        _ presentationController: UIPresentationController
    ) {
        finishPicking(error: nil)
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
