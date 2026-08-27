import SnapKit
import UIKit

final class RealtimeMediaTopBar: UIView {
    private enum Layout {
        static let itemWidth: CGFloat = 52
        static let height: CGFloat = 54
        static let iconSize: CGFloat = 21
    }

    var onOpenGallery: (() -> Void)?

    private let showsMute: Bool
    private var isMuted = false

    private lazy var muteButton: RealtimeMediaActionButton = {
        let button = makeActionButton(
            title: "声音",
            systemName: "speaker.wave.2.fill",
            accessibilityLabel: "关闭声音"
        )
        button.addTarget(
            self,
            action: #selector(toggleMute),
            for: .touchUpInside
        )
        button.accessibilityValue = "已开启"
        return button
    }()

    private lazy var frameInterpolationButton: RealtimeMediaActionButton = {
        let button = makeActionButton(
            title: "插帧",
            systemName: "bolt.fill",
            accessibilityLabel: "插帧"
        )
        return button
    }()

    private lazy var galleryButton: RealtimeMediaActionButton = {
        let button = makeActionButton(
            title: "相册",
            systemName: "photo",
            accessibilityLabel: "从相册替换本地素材"
        )
        button.addTarget(
            self,
            action: #selector(openGallery),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var stackView: UIStackView = {
        var buttons: [UIView] = []
        if showsMute {
            buttons.append(muteButton)
        }
        buttons.append(frameInterpolationButton)
        buttons.append(galleryButton)

        let stackView = UIStackView(arrangedSubviews: buttons)
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        return stackView
    }()

    init(showsMute: Bool) {
        self.showsMute = showsMute
        super.init(frame: .zero)

        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: CGFloat(showsMute ? 3 : 2) * Layout.itemWidth,
            height: Layout.height
        )
    }

    private func makeActionButton(
        title: String,
        systemName: String,
        accessibilityLabel: String
    ) -> RealtimeMediaActionButton {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: Layout.iconSize,
            weight: .medium
        )
        let button = RealtimeMediaActionButton(
            title: title,
            image: UIImage(
                systemName: systemName,
                withConfiguration: configuration
            )
        )
        button.accessibilityLabel = accessibilityLabel
        return button
    }

    @objc private func toggleMute() {
        isMuted.toggle()
        muteButton.setContent(
            title: isMuted ? "静音" : "声音",
            image: makeSymbolImage(
                systemName: isMuted
                    ? "speaker.slash.fill"
                    : "speaker.wave.2.fill"
            )
        )
        muteButton.accessibilityLabel = isMuted ? "开启声音" : "关闭声音"
        muteButton.accessibilityValue = isMuted ? "已静音" : "已开启"
    }

    private func makeSymbolImage(systemName: String) -> UIImage? {
        UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: Layout.iconSize,
                weight: .medium
            )
        )
    }

    @objc private func openGallery() {
        onOpenGallery?()
    }
}

private final class RealtimeMediaActionButton: UIControl {
    private lazy var iconView: UIImageView = {
        let imageView = UIImageView(image: image?.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        configureShadow(for: imageView)
        return imageView
    }()

    private lazy var actionLabel: UILabel = {
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textAlignment = .center
        configureShadow(for: label)
        return label
    }()

    private let title: String
    private let image: UIImage?

    init(title: String, image: UIImage?) {
        self.title = title
        self.image = image
        super.init(frame: .zero)

        accessibilityTraits = .button
        addSubview(iconView)
        addSubview(actionLabel)

        iconView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(6)
            make.centerX.equalToSuperview()
            make.size.equalTo(22)
        }
        actionLabel.snp.makeConstraints { make in
            make.top.equalTo(iconView.snp.bottom).offset(4)
            make.centerX.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent(title: String, image: UIImage?) {
        actionLabel.text = title
        iconView.image = image?.withRenderingMode(.alwaysTemplate)
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.55 : 1
        }
    }

    private func configureShadow(for view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.5
        view.layer.shadowRadius = 2
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
    }
}
