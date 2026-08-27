import SnapKit
import UIKit

final class RealtimeCameraActionBar: UIView {
    var onSwitchCamera: (() -> Void)?

    private lazy var switchCameraButton: RealtimeLabeledActionButton = {
        let button = RealtimeLabeledActionButton(
            title: "翻转",
            image: UIImage(named: "realtime_camera_rotate")
        )
        button.accessibilityLabel = "翻转摄像头"
        button.addTarget(
            self,
            action: #selector(switchCamera),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var frameInterpolationButton: RealtimeLabeledActionButton = {
        let image = UIImage(
            systemName: "rectangle.stack.fill",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 20,
                weight: .medium
            )
        )
        let button = RealtimeLabeledActionButton(
            title: "插帧",
            image: image
        )
        button.accessibilityLabel = "插帧"
        return button
    }()

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView(
            arrangedSubviews: [
                switchCameraButton,
                frameInterpolationButton
            ]
        )
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        return stackView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSwitchCameraEnabled(_ isEnabled: Bool) {
        switchCameraButton.isEnabled = isEnabled
    }

    @objc private func switchCamera() {
        onSwitchCamera?()
    }
}

private final class RealtimeLabeledActionButton: UIControl {
    private let title: String
    private let image: UIImage?

    private lazy var iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = image?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        configureShadow(for: imageView)
        return imageView
    }()

    private lazy var actionLabel: UILabel = {
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textAlignment = .center
        configureShadow(for: label)
        return label
    }()

    init(title: String, image: UIImage?) {
        self.title = title
        self.image = image
        super.init(frame: .zero)

        accessibilityTraits = .button
        addSubview(iconView)
        addSubview(actionLabel)

        iconView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(9)
            make.centerX.equalToSuperview()
            make.size.equalTo(22)
        }
        actionLabel.snp.makeConstraints { make in
            make.top.equalTo(iconView.snp.bottom).offset(5)
            make.centerX.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureShadow(for view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.5
        view.layer.shadowRadius = 2
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
    }
}
