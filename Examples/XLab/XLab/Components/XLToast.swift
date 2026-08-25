import SnapKit
import UIKit

@MainActor
enum XLToast {
    static func show(
        _ message: String,
        in hostView: UIView,
        duration: TimeInterval = 2
    ) {
        removeExistingToast(from: hostView)

        let toastView = XLToastView(message: message)
        hostView.addSubview(toastView)
        toastView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.lessThanOrEqualTo(hostView.snp.width).offset(-64)
        }
        hostView.layoutIfNeeded()

        UIAccessibility.post(notification: .announcement, argument: message)
        animateIn(toastView)

        DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0)) {
            guard toastView.superview != nil else { return }
            animateOut(toastView)
        }
    }

    private static func removeExistingToast(from hostView: UIView) {
        hostView.subviews
            .compactMap { $0 as? XLToastView }
            .forEach { $0.removeFromSuperview() }
    }

    private static func animateIn(_ toastView: XLToastView) {
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            toastView.alpha = 1
            toastView.transform = .identity
        }
    }

    private static func animateOut(_ toastView: XLToastView) {
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                toastView.alpha = 0
                toastView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            },
            completion: { _ in toastView.removeFromSuperview() }
        )
    }
}

private final class XLToastView: UIView {
    init(message: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 16 / 255, alpha: 0.6)
        layer.cornerRadius = 4
        layer.cornerCurve = .continuous
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        isUserInteractionEnabled = false

        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(label)
        label.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(9)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
