import UIKit
import XmaxSDK

final class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "XLab"
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.text = "XmaxSDK"

        let versionLabel = UILabel()
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.font = .preferredFont(forTextStyle: .body)
        versionLabel.textColor = .secondaryLabel
        versionLabel.text = "iOS SDK \(XmaxSDKInfo.version)"

        let stackView = UIStackView(arrangedSubviews: [titleLabel, versionLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
