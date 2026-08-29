import SnapKit
import UIKit

final class RealtimePromptKeyboardView: UIView, UITextViewDelegate {
    static let preferredHeight: CGFloat = 138

    var onTextChange: ((String) -> Void)?
    var onSubmit: ((String) -> Void)?
    var onReferenceAction: (() -> Void)?

    private lazy var contentView: UIView = {
        let view = UIView()
        view.backgroundColor = .feed(rgb: 0x252525)
        view.layer.cornerRadius = 15
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = .systemFont(ofSize: 14)
        textView.keyboardAppearance = .dark
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.showsVerticalScrollIndicator = false
        textView.delegate = self
        return textView
    }()

    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = "输入你想要的效果"
        label.textColor = .white.withAlphaComponent(0.5)
        label.font = .systemFont(ofSize: 14)
        label.isUserInteractionEnabled = false
        return label
    }()

    private lazy var referenceButton: RealtimePromptReferenceButton = {
        let button = RealtimePromptReferenceButton()
        button.addTarget(
            self,
            action: #selector(referenceAction),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var submitButton: UIButton = {
        let button = UIButton(type: .custom)
        configureButton(
            button,
            imageName: "realtime_prompt_submit",
            imageSize: CGSize(width: 11, height: 12),
            backgroundColor: .feed(rgb: 0xFF2E88)
        )
        button.accessibilityLabel = "提交自定义模式描述"
        button.addTarget(
            self,
            action: #selector(submitPrompt),
            for: .touchUpInside
        )
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feed(rgb: 0x101010)

        addSubview(contentView)
        contentView.addSubview(textView)
        contentView.addSubview(placeholderLabel)
        contentView.addSubview(referenceButton)
        contentView.addSubview(submitButton)

        contentView.snp.makeConstraints { make in
            make.horizontalEdges.equalToSuperview().inset(14)
            make.verticalEdges.equalToSuperview().inset(14)
        }
        textView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.horizontalEdges.equalToSuperview().inset(12)
            make.bottom.equalTo(referenceButton.snp.top).offset(-8)
        }
        placeholderLabel.snp.makeConstraints { make in
            make.top.leading.equalTo(textView)
            make.trailing.lessThanOrEqualTo(textView)
        }
        submitButton.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(8)
            make.size.equalTo(28)
        }
        referenceButton.snp.makeConstraints { make in
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

    func setReference(_ reference: RealtimeReferenceCatalog.Item?) {
        referenceButton.setReference(reference)
        updateState()
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
            && !referenceButton.blocksSubmission
        submitButton.isEnabled = isEnabled
        submitButton.alpha = isEnabled ? 1 : 0.2
    }

    @objc private func submitPrompt() {
        let prompt = normalizedPrompt()
        guard !prompt.isEmpty else { return }
        onSubmit?(prompt)
    }

    @objc private func referenceAction() {
        onReferenceAction?()
    }
}
