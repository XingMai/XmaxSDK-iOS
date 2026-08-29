import Kingfisher
import SnapKit
import UIKit

final class RealtimePromptReferenceButton: UIControl {
    private var displayedURL: URL?

    private(set) var blocksSubmission = false

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }()

    private lazy var addImageView: UIImageView = {
        let image = UIImage(named: "realtime_prompt_add")?
            .withRenderingMode(.alwaysTemplate)
        let view = UIImageView(image: image)
        view.tintColor = .white
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        return view
    }()

    private lazy var overlayView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }()

    private lazy var uploadIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.color = .white
        view.hidesWhenStopped = true
        view.transform = CGAffineTransform(scaleX: 0.65, y: 0.65)
        return view
    }()

    private lazy var retryImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: 12,
            weight: .semibold
        )
        let view = UIImageView(
            image: UIImage(
                systemName: "arrow.clockwise",
                withConfiguration: configuration
            )
        )
        view.tintColor = .white
        view.contentMode = .scaleAspectFit
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white.withAlphaComponent(0.12)
        clipsToBounds = true

        addSubview(imageView)
        addSubview(addImageView)
        addSubview(overlayView)
        overlayView.addSubview(uploadIndicator)
        overlayView.addSubview(retryImageView)

        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        addImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(12)
        }
        overlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        uploadIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        retryImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(14)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
    }

    func setReference(_ reference: RealtimeReferenceCatalog.Item?) {
        uploadIndicator.stopAnimating()
        retryImageView.isHidden = true
        blocksSubmission = reference != nil
            && reference?.uploadState != .ready
        isEnabled = reference?.uploadState != .uploading

        guard let reference else {
            displayedURL = nil
            imageView.kf.cancelDownloadTask()
            imageView.image = nil
            imageView.isHidden = true
            addImageView.isHidden = false
            overlayView.isHidden = true
            accessibilityLabel = "添加自定义模式参考图"
            return
        }

        imageView.isHidden = false
        addImageView.isHidden = true
        accessibilityLabel = switch reference.uploadState {
        case .ready:
            "删除自定义模式参考图"
        case .uploading:
            "正在上传自定义模式参考图"
        case .failed:
            "重试上传自定义模式参考图"
        }

        if displayedURL != reference.iconURL {
            displayedURL = reference.iconURL
            imageView.kf.setImage(
                with: reference.iconURL,
                options: [
                    .processor(
                        DownsamplingImageProcessor(
                            size: CGSize(width: 42, height: 42)
                        )
                    ),
                    .scaleFactor(max(traitCollection.displayScale, 1)),
                    .transition(.fade(0.2)),
                    .loadDiskFileSynchronously
                ]
            )
        }

        switch reference.uploadState {
        case .ready:
            overlayView.isHidden = true
        case .uploading:
            overlayView.isHidden = false
            uploadIndicator.startAnimating()
        case .failed:
            overlayView.isHidden = false
            retryImageView.isHidden = false
        }
    }
}
