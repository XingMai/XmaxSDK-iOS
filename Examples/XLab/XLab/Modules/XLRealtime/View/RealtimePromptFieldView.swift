import SnapKit
import UIKit

final class RealtimePromptFieldView: UIView, UITextFieldDelegate {
    var onBeginEditing: ((String) -> Void)?
    var onSubmit: ((String) -> Void)?
    var onReferenceAction: (() -> Void)?

    private lazy var textField: UITextField = {
        let textField = UITextField()
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
        return textField
    }()

    private lazy var submitControl = RealtimePromptCircleView(
        imageName: "realtime_prompt_submit",
        imageSize: CGSize(width: 13, height: 14),
        backgroundColor: .feed(rgb: 0xFF2E88)
    )

    private lazy var referenceButton: RealtimePromptReferenceButton = {
        let button = RealtimePromptReferenceButton()
        button.addTarget(
            self,
            action: #selector(referenceAction),
            for: .touchUpInside
        )
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feed(rgb: 0x272728)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous

        addSubview(textField)
        addSubview(referenceButton)
        addSubview(submitControl)
        submitControl.accessibilityLabel = "提交自定义模式描述"
        submitControl.addTarget(
            self,
            action: #selector(submitPrompt),
            for: .touchUpInside
        )

        textField.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(11)
            make.verticalEdges.equalToSuperview()
            make.trailing.equalTo(referenceButton.snp.leading).offset(-10)
        }
        referenceButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.size.equalTo(32)
        }
        submitControl.snp.makeConstraints { make in
            make.leading.equalTo(referenceButton.snp.trailing).offset(8)
            make.trailing.equalToSuperview().offset(-8)
            make.centerY.equalToSuperview()
            make.size.equalTo(32)
        }
        updateState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setText(_ text: String) {
        textField.text = text
        updateState()
    }

    func setReference(_ reference: RealtimeReferenceCatalog.Item?) {
        referenceButton.setReference(reference)
        updateState()
    }

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        onBeginEditing?(textField.text ?? "")
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    @objc private func textDidChange() {
        updateState()
    }

    private func normalizedPrompt() -> String {
        (textField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateState() {
        let isEnabled = !normalizedPrompt().isEmpty
            && !referenceButton.blocksSubmission
        submitControl.isEnabled = isEnabled
        submitControl.alpha = isEnabled ? 1 : 0.2
    }

    @objc private func submitPrompt() {
        let prompt = normalizedPrompt()
        guard !prompt.isEmpty, !referenceButton.blocksSubmission else {
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSubmit?(prompt)
    }

    @objc private func referenceAction() {
        onReferenceAction?()
    }
}

private final class RealtimePromptCircleView: UIControl {
    private let imageName: String
    private let imageSize: CGSize

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    init(
        imageName: String,
        imageSize: CGSize,
        backgroundColor: UIColor
    ) {
        self.imageName = imageName
        self.imageSize = imageSize
        super.init(frame: .zero)
        self.backgroundColor = backgroundColor
        layer.cornerRadius = 16
        clipsToBounds = true

        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(imageSize)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: isHighlighted ? 0.08 : 0.18,
                delay: 0,
                options: [
                    .allowUserInteraction,
                    .beginFromCurrentState,
                    .curveEaseOut,
                ]
            ) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.84, y: 0.84)
                    : .identity
            }
        }
    }
}
