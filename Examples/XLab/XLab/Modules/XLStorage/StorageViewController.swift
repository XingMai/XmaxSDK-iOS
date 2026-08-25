import SnapKit
import UIKit
import XmaxSDK

final class StorageViewController: UIViewController {
    private let orange = FeedPalette.orange
    private let topBar = UIView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func configureBackgroundGlow() {
        let orangeGlow = makeGlow(
            color: orange.withAlphaComponent(0.20),
            diameter: 280,
            blurRadius: 86
        )
        let secondaryGlow = makeGlow(
            color: .feed(rgb: 0xC67A35, alpha: 0.09),
            diameter: 180,
            blurRadius: 76
        )
        view.addSubview(orangeGlow)
        view.addSubview(secondaryGlow)

        orangeGlow.snp.makeConstraints { make in
            make.size.equalTo(280)
            make.trailing.equalToSuperview().offset(150)
            make.top.equalToSuperview().offset(-70)
        }
        secondaryGlow.snp.makeConstraints { make in
            make.size.equalTo(180)
            make.leading.equalToSuperview().offset(-130)
            make.top.equalToSuperview().offset(310)
        }
    }

    private func configureTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        let backButton = UIButton(type: .custom)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(named: "realtime_nav_back"), for: .normal)
        backButton.imageView?.contentMode = .scaleAspectFit
        backButton.accessibilityLabel = "返回首页"
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)

        let title = makeFeedLabel("存储服务", size: 20, weight: .bold, color: FeedPalette.primaryText)
        let subtitle = makeFeedLabel(
            "EXAMPLE / IOS",
            size: 8,
            color: orange.withAlphaComponent(0.72),
            letterSpacing: 1
        )
        let titleStack = feedVerticalStack([title, subtitle], spacing: 3)
        let version = FeedPillView(
            text: "v\(XmaxSDKInfo.version)",
            foregroundColor: orange,
            backgroundColor: orange.withAlphaComponent(0.14),
            borderColor: orange.withAlphaComponent(0.29),
            fontSize: 8,
            horizontalPadding: 9,
            height: 25
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
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
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
    }

    private func makePipelineOverviewCard() -> UIView {
        let card = FeedCardView(
            colors: [.feed(rgb: 0x1D1711, alpha: 0.94), .feed(rgb: 0x0F1115, alpha: 0.91)],
            cornerRadius: 18,
            borderColor: orange.withAlphaComponent(0.24),
            shadowRadius: 20,
            shadowOffset: CGSize(width: 0, height: 9)
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
            text: "READY",
            foregroundColor: orange,
            backgroundColor: orange.withAlphaComponent(0.13),
            borderColor: .clear,
            fontSize: 8,
            horizontalPadding: 9,
            height: 23
        )
        let header = feedHorizontalStack([
            feedHorizontalStack([dot, eyebrow], spacing: 7),
            feedFlexibleSpacer(),
            ready
        ])

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

        let local = makeFeedLabel("LOCAL FILE", size: 8, weight: .bold, color: .feed(rgb: 0x9A8B7A))
        let firstDash = makeFeedLabel("—", size: 9, color: .feed(rgb: 0x66513A))
        let sdk = makeFeedLabel("XMAX SDK", size: 8, weight: .bold, color: orange)
        let secondDash = makeFeedLabel("—", size: 9, color: .feed(rgb: 0x66513A))
        let remote = makeFeedLabel("REMOTE URL", size: 8, weight: .bold, color: .feed(rgb: 0x9A8B7A))
        let pipeline = feedHorizontalStack([local, firstDash, sdk, secondDash, remote], spacing: 8)

        let stack = feedVerticalStack([header, title, subtitle, pipeline])
        stack.setCustomSpacing(13, after: header)
        stack.setCustomSpacing(7, after: title)
        stack.setCustomSpacing(15, after: subtitle)
        card.contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(17)
        }
        return card
    }

    private func makeFilePreviewCard() -> UIView {
        let card = FeedCardView(
            colors: [.feed(rgb: 0x1B1712, alpha: 0.93), .feed(rgb: 0x111216, alpha: 0.91)],
            cornerRadius: 18,
            borderColor: orange.withAlphaComponent(0.18),
            shadowRadius: 16,
            shadowOffset: CGSize(width: 0, height: 7)
        )

        let step = FeedPillView(
            text: "01",
            foregroundColor: orange,
            backgroundColor: orange.withAlphaComponent(0.13),
            borderColor: orange.withAlphaComponent(0.27),
            fontSize: 8,
            horizontalPadding: 8,
            height: 22,
            letterSpacing: 0
        )
        step.snp.makeConstraints { make in
            make.width.equalTo(28)
        }
        let title = makeFeedLabel("文件预览", size: 13, weight: .bold, color: .feed(rgb: 0xF2ECE4))
        let selectHint = makeFeedLabel("点击选择", size: 9, weight: .bold, color: .feed(rgb: 0x6E6257))
        let header = feedHorizontalStack([step, title, feedFlexibleSpacer(), selectHint], spacing: 9)

        let picker = UIView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.backgroundColor = .feed(rgb: 0x0B0C0F, alpha: 0.56)
        picker.layer.cornerRadius = 14
        picker.layer.borderWidth = 1
        picker.layer.borderColor = orange.withAlphaComponent(0.15).cgColor

        let plus = makeFeedLabel("+", size: 22, color: orange)
        plus.textAlignment = .center
        plus.backgroundColor = orange.withAlphaComponent(0.09)
        plus.layer.cornerRadius = 21
        plus.layer.borderWidth = 1
        plus.layer.borderColor = orange.withAlphaComponent(0.24).cgColor
        plus.clipsToBounds = true
        let pickerTitle = makeFeedLabel("点击选择图片或视频", size: 11, weight: .bold, color: .feed(rgb: 0x9D9185))
        pickerTitle.textAlignment = .center
        let pickerType = makeFeedLabel(
            "IMAGE  /  VIDEO",
            size: 8,
            color: .feed(rgb: 0x62584E),
            letterSpacing: 0.8
        )
        pickerType.textAlignment = .center
        let pickerStack = feedVerticalStack([plus, pickerTitle, pickerType])
        pickerStack.alignment = .center
        pickerStack.setCustomSpacing(11, after: plus)
        pickerStack.setCustomSpacing(5, after: pickerTitle)
        picker.addSubview(pickerStack)

        picker.snp.makeConstraints { make in
            make.height.equalTo(176)
        }
        plus.snp.makeConstraints { make in
            make.size.equalTo(42)
        }
        pickerStack.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        let typeMetric = makeMetadataView(label: "type", value: "--")
        let resolutionMetric = makeMetadataView(label: "resolution", value: "--")
        let sizeMetric = makeMetadataView(label: "size", value: "--")
        let metadata = feedHorizontalStack([typeMetric, resolutionMetric, sizeMetric], spacing: 8)
        typeMetric.snp.makeConstraints { make in
            make.width.equalTo(resolutionMetric)
        }
        resolutionMetric.snp.makeConstraints { make in
            make.width.equalTo(sizeMetric)
        }

        let stack = feedVerticalStack([header, picker, metadata])
        stack.setCustomSpacing(10, after: header)
        stack.setCustomSpacing(10, after: picker)
        card.contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(17)
        }
        return card
    }

    private func makeMetadataView(label: String, value: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .feed(rgb: 0x0C0D10, alpha: 0.54)
        container.layer.cornerRadius = 10

        let labelView = makeFeedLabel(label, size: 8, color: .feed(rgb: 0x6E6257))
        let valueView = makeFeedLabel(value, size: 9, weight: .bold, color: .feed(rgb: 0x5C534A))
        let stack = feedVerticalStack([labelView, valueView], spacing: 4)
        container.addSubview(stack)

        container.snp.makeConstraints { make in
            make.height.equalTo(51)
        }
        stack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(11)
            make.trailing.lessThanOrEqualToSuperview().offset(-6)
            make.centerY.equalToSuperview()
        }
        return container
    }

    private func makeGlow(color: UIColor, diameter: CGFloat, blurRadius: CGFloat) -> UIView {
        let glow = UIView()
        glow.translatesAutoresizingMaskIntoConstraints = false
        glow.backgroundColor = color
        glow.layer.cornerRadius = diameter / 2
        glow.layer.shadowColor = color.cgColor
        glow.layer.shadowOpacity = 1
        glow.layer.shadowRadius = blurRadius
        glow.layer.shadowOffset = .zero
        return glow
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }
}
