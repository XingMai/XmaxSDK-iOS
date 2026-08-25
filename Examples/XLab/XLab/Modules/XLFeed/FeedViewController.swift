import SnapKit
import UIKit
import XmaxSDK

final class FeedViewController: UIViewController, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func loadView() {
        view = FeedGradientView(
            colors: [
                .feed(rgb: 0x0C121B),
                .feed(rgb: 0x070A0F),
                .feed(rgb: 0x090D13)
            ],
            startPoint: CGPoint(x: 0.1, y: 0),
            endPoint: CGPoint(x: 0.9, y: 1)
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureBackgroundGlow()
        configureScrollView()
        populateFeed()
        configureKeyboardDismissal()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func configureBackgroundGlow() {
        let blueGlow = makeGlow(color: .feed(rgb: 0x4B7BFF, alpha: 0.14), diameter: 260, blurRadius: 70)
        view.addSubview(blueGlow)
        let mintGlow = makeGlow(color: .feed(rgb: 0x4DF0B5, alpha: 0.12), diameter: 220, blurRadius: 75)
        view.addSubview(mintGlow)

        blueGlow.snp.makeConstraints { make in
            make.size.equalTo(260)
            make.trailing.equalToSuperview().offset(135)
            make.top.equalToSuperview().offset(-55)
        }
        mintGlow.snp.makeConstraints { make in
            make.size.equalTo(220)
            make.leading.equalToSuperview().offset(-145)
            make.top.equalToSuperview().offset(330)
        }
    }

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.contentInsetAdjustmentBehavior = .always
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 0
        scrollView.addSubview(contentStack)

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentStack.snp.makeConstraints { make in
            make.leading.equalTo(scrollView.contentLayoutGuide).offset(18)
            make.trailing.equalTo(scrollView.contentLayoutGuide).offset(-18)
            make.top.equalTo(scrollView.contentLayoutGuide).offset(20)
            make.bottom.equalTo(scrollView.contentLayoutGuide).offset(-32)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-36)
        }
    }

    private func populateFeed() {
        contentStack.addArrangedSubview(makeHeader())
        contentStack.addArrangedSubview(feedFixedSpacer(height: 34))
        contentStack.addArrangedSubview(makeHero())
        contentStack.addArrangedSubview(feedFixedSpacer(height: 12))
        contentStack.addArrangedSubview(makeMetrics())
        contentStack.addArrangedSubview(feedFixedSpacer(height: 14))
        contentStack.addArrangedSubview(FeedModelRegistryCardView())
        contentStack.addArrangedSubview(feedFixedSpacer(height: 30))
        contentStack.addArrangedSubview(makeSectionHeader(title: "GENERATION PIPELINES", subtitle: "选择一种内容输入方式"))
        contentStack.addArrangedSubview(feedFixedSpacer(height: 14))

        let realtimeCard = FeedPipelineCardView(
            sequence: "01",
            modeID: "MODE_01 / CAMERA",
            statusColor: FeedPalette.mint,
            title: "摄像头实时流",
            subtitle: "实时采集摄像头画面，持续驱动视频生成。",
            capability: "createLocalCameraStream()"
        )
        realtimeCard.isUserInteractionEnabled = true
        realtimeCard.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(openRealtime))
        )
        contentStack.addArrangedSubview(realtimeCard)
        contentStack.addArrangedSubview(feedFixedSpacer(height: 14))
        contentStack.addArrangedSubview(FeedPipelineCardView(
            sequence: "02",
            modeID: "MODE_02 / VIDEO.FILE",
            statusColor: FeedPalette.blue,
            title: "视频生成管线",
            subtitle: "选择本地视频，将连续画面逐帧送入生成链路。",
            capability: "createLocalVideoStream()"
        ))
        contentStack.addArrangedSubview(feedFixedSpacer(height: 14))
        contentStack.addArrangedSubview(FeedPipelineCardView(
            sequence: "03",
            modeID: "MODE_03 / IMAGE.FILE",
            statusColor: FeedPalette.purple,
            title: "图片生成管线",
            subtitle: "选择本地图片，让静态画面持续流动起来。",
            capability: "createLocalImageStream()"
        ))

        contentStack.addArrangedSubview(feedFixedSpacer(height: 30))
        contentStack.addArrangedSubview(makeSectionHeader(title: "SDK FEATURES", subtitle: "更多能力与接入示例"))
        contentStack.addArrangedSubview(feedFixedSpacer(height: 14))
        contentStack.addArrangedSubview(FeedFeatureCardView(
            category: "SDK RENDERING / TRAJECTORY",
            watermark: "FX",
            accentColor: FeedPalette.pink,
            iconName: "sdk_feature_trajectory_custom",
            iconLabel: "RENDER",
            title: "自定义轨迹渲染",
            subtitle: "使用自定义 Renderer 绘制交互轨迹。",
            tags: ["CANVAS", "MULTI-TOUCH", "CUSTOM EFFECT"],
            highlightedTag: "CUSTOM EFFECT"
        ))
        contentStack.addArrangedSubview(feedFixedSpacer(height: 14))
        let storageCard = FeedFeatureCardView(
            category: "SDK SERVICE / STORAGE",
            watermark: "URL",
            accentColor: FeedPalette.orange,
            iconName: "sdk_feature_storage",
            iconLabel: "UPLOAD",
            title: "存储服务",
            subtitle: "上传图片或视频，获取可复用的远程地址",
            tags: ["IMAGE", "VIDEO", "REMOTE URL"],
            highlightedTag: "REMOTE URL"
        )
        storageCard.isUserInteractionEnabled = true
        storageCard.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(openStorage))
        )
        contentStack.addArrangedSubview(storageCard)
        contentStack.addArrangedSubview(feedFixedSpacer(height: 10))
        contentStack.addArrangedSubview(makeFooter())
    }

    private func configureKeyboardDismissal() {
        let tapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(dismissKeyboard)
        )
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var touchedView = touch.view
        while let currentView = touchedView, currentView !== view {
            if currentView is UIControl {
                return false
            }
            touchedView = currentView.superview
        }
        return true
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func makeHeader() -> UIView {
        let mark = FeedBrandMarkView()
        let name = makeFeedLabel(
            "XMAXSDK",
            size: 15,
            weight: .bold,
            color: .feed(rgb: 0xF2F4F7),
            letterSpacing: 1.8
        )
        let platform = makeFeedLabel(
            "EXAMPLE / IOS",
            size: 8,
            color: .white.withAlphaComponent(0.38),
            letterSpacing: 1
        )
        let brandText = feedVerticalStack([name, platform], spacing: 3)
        let brand = feedHorizontalStack([mark, brandText], spacing: 11)
        let version = FeedPillView(
            text: "v\(XmaxSDKInfo.version)",
            foregroundColor: FeedPalette.mint,
            backgroundColor: FeedPalette.mint.withAlphaComponent(0.086)
        )
        return feedHorizontalStack([brand, feedFlexibleSpacer(), version])
    }

    private func makeHero() -> UIView {
        let card = FeedCardView(
            colors: [.feed(rgb: 0x141D28, alpha: 0.88), .feed(rgb: 0x0C1118, alpha: 0.82)],
            cornerRadius: 20,
            borderColor: .white.withAlphaComponent(0.12),
            shadowRadius: 24,
            shadowOffset: CGSize(width: 0, height: 10)
        )

        let glow = makeGlow(color: .feed(rgb: 0x6895FF, alpha: 0.08), diameter: 96, blurRadius: 28)
        card.contentView.addSubview(glow)
        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = FeedPalette.mint
        line.layer.cornerRadius = 1
        line.snp.makeConstraints { make in
            make.size.equalTo(CGSize(width: 22, height: 2))
        }
        let eyebrow = makeFeedLabel(
            "XMAX PLAYGROUND",
            size: 9,
            weight: .bold,
            color: FeedPalette.mint,
            letterSpacing: 1.2
        )
        let eyebrowRow = feedHorizontalStack([line, eyebrow], spacing: 7)
        let title = makeFeedLabel("实时交互视频模型", size: 24, weight: .bold, color: .feed(rgb: 0xF5F7FB), letterSpacing: -0.3)
        let subtitle = makeFeedLabel("选择输入源，启动 XmaxSDK 流式生成链路", size: 12, color: .feed(rgb: 0x91A0B2))
        let stack = feedVerticalStack([eyebrowRow, title, subtitle])
        stack.setCustomSpacing(18, after: eyebrowRow)
        stack.setCustomSpacing(12, after: title)
        card.contentView.addSubview(stack)

        glow.snp.makeConstraints { make in
            make.size.equalTo(96)
            make.trailing.equalToSuperview().offset(36)
            make.bottom.equalToSuperview().offset(42)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }
        return card
    }

    private func makeMetrics() -> UIView {
        let runtime = FeedRuntimeMetricView(label: "RUNTIME", value: "iOS")
        let minimum = FeedRuntimeMetricView(label: "MIN OS", value: "15+")
        let model = FeedRuntimeMetricView(label: "LATEST MODEL", value: "X2.0")
        let stack = feedHorizontalStack([runtime, minimum, model], spacing: 8)

        runtime.snp.makeConstraints { make in
            make.width.equalTo(minimum)
        }
        minimum.snp.makeConstraints { make in
            make.width.equalTo(model)
        }
        return stack
    }

    private func makeSectionHeader(title: String, subtitle: String) -> UIView {
        let titleLabel = makeFeedLabel(
            title,
            size: 10,
            weight: .bold,
            color: .feed(rgb: 0xC6D0DD),
            letterSpacing: 1.1
        )
        let subtitleLabel = makeFeedLabel(subtitle, size: 11, color: .feed(rgb: 0x667384))
        return feedVerticalStack([titleLabel, subtitleLabel], spacing: 5)
    }

    private func makeFooter() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .white.withAlphaComponent(0.09)
        let copyright = makeFeedLabel(
            "Copyright © 2026 XMAX.AI PTE.LTD All rights reserved.",
            size: 9,
            color: .white.withAlphaComponent(0.31)
        )
        copyright.textAlignment = .center
        let email = makeFeedLabel(
            "sdk@xmax.ai",
            size: 9,
            color: FeedPalette.mint.withAlphaComponent(0.41),
            letterSpacing: 0.4
        )
        email.textAlignment = .center
        container.addSubview(divider)
        container.addSubview(copyright)
        container.addSubview(email)

        divider.snp.makeConstraints { make in
            make.size.equalTo(CGSize(width: 36, height: 1))
            make.centerX.top.equalToSuperview()
        }
        copyright.snp.makeConstraints { make in
            make.top.equalTo(divider.snp.bottom).offset(18)
            make.centerX.equalToSuperview()
            make.horizontalEdges.lessThanOrEqualToSuperview()
        }
        email.snp.makeConstraints { make in
            make.top.equalTo(copyright.snp.bottom).offset(7)
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(-32)
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

    @objc private func openStorage() {
        navigationController?.pushViewController(StorageViewController(), animated: true)
    }

    @objc private func openRealtime() {
        navigationController?.pushViewController(RealtimeViewController(), animated: true)
    }
}
