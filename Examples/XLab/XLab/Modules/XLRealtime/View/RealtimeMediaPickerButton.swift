import SnapKit
import UIKit

final class RealtimeMediaTopBar: UIView {
    var onOpenGallery: (() -> Void)?

    private let showsMute: Bool

    private lazy var muteButton: UIButton = {
        let button = makeIconButton(
            systemName: "speaker.slash.fill",
            accessibilityLabel: "静音"
        )
        return button
    }()

    private lazy var frameInterpolationButton: UIButton = {
        let button = makeIconButton(
            systemName: "rectangle.stack.fill",
            accessibilityLabel: "插帧"
        )
        return button
    }()

    private lazy var galleryButton: UIButton = {
        let button = makeIconButton(
            systemName: "square.stack",
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
        CGSize(width: CGFloat(showsMute ? 3 : 2) * 44, height: 44)
    }

    private func makeIconButton(
        systemName: String,
        accessibilityLabel: String
    ) -> UIButton {
        let button = UIButton(type: .custom)
        let configuration = UIImage.SymbolConfiguration(
            pointSize: 21,
            weight: .medium
        )
        button.setImage(
            UIImage(systemName: systemName, withConfiguration: configuration),
            for: .normal
        )
        button.tintColor = .white
        button.imageView?.contentMode = .scaleAspectFit
        button.imageView?.layer.shadowColor = UIColor.black.cgColor
        button.imageView?.layer.shadowOpacity = 0.5
        button.imageView?.layer.shadowRadius = 2
        button.imageView?.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityTraits = .button
        return button
    }

    @objc private func openGallery() {
        onOpenGallery?()
    }
}
