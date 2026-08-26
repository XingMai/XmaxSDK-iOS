import SnapKit
import UIKit

final class RealtimeMediaPickerButton: UIControl {
    private lazy var iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(
            systemName: "square.stack",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 22,
                weight: .medium
            )
        )?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        configureShadow(for: imageView)
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(iconView)
        accessibilityLabel = "从相册替换本地素材"
        accessibilityTraits = .button

        iconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(24)
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
