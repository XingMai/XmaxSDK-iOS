import ImageIO
import SnapKit
import UIKit

final class RealtimeLoadingOverlay: UIView {
    private var isLoading = false
    private var transitionVersion: UInt64 = 0

    private lazy var loadingImageView: UIImageView = {
        let imageView = UIImageView(
            image: RealtimeLoadingImageLoader.animatedImage()
        )
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var fallbackIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = UIColor.white.withAlphaComponent(0.86)
        indicator.hidesWhenStopped = true
        return indicator
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.72)
        isHidden = true
        alpha = 0
        isUserInteractionEnabled = false

        addSubview(loadingImageView)
        addSubview(fallbackIndicator)
        loadingImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(54)
            make.height.equalTo(50)
        }
        fallbackIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startLoading() {
        guard !isLoading else { return }
        isLoading = true
        transitionVersion &+= 1
        layer.removeAllAnimations()
        isHidden = false

        if loadingImageView.image == nil {
            fallbackIndicator.startAnimating()
        } else {
            fallbackIndicator.stopAnimating()
            loadingImageView.startAnimating()
        }

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.alpha = 1
        }
    }

    func hideLoading() {
        guard isLoading || !isHidden else { return }
        isLoading = false
        transitionVersion &+= 1
        let version = transitionVersion
        layer.removeAllAnimations()
        loadingImageView.stopAnimating()
        fallbackIndicator.stopAnimating()

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut]
        ) {
            self.alpha = 0
        } completion: { _ in
            guard version == self.transitionVersion else { return }
            self.isHidden = true
        }
    }
}

private enum RealtimeLoadingImageLoader {
    static func animatedImage() -> UIImage? {
        guard let data = NSDataAsset(name: "RealtimeLoading")?.data,
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  nil
              ) else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }
        var images: [UIImage] = []
        var duration: TimeInterval = 0

        for index in 0..<frameCount {
            guard let image = CGImageSourceCreateImageAtIndex(
                source,
                index,
                nil
            ) else { continue }
            images.append(UIImage(cgImage: image))
            duration += frameDuration(source: source, index: index)
        }

        guard !images.isEmpty else { return nil }
        return UIImage.animatedImage(
            with: images,
            duration: duration > 0 ? duration : 0.1 * Double(images.count)
        )
    }

    private static func frameDuration(
        source: CGImageSource,
        index: Int
    ) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            index,
            nil
        ) as? [String: Any],
        let gifProperties = properties[
            kCGImagePropertyGIFDictionary as String
        ] as? [String: Any] else {
            return 0.1
        }

        return gifProperties[
            kCGImagePropertyGIFUnclampedDelayTime as String
        ] as? TimeInterval
            ?? gifProperties[
                kCGImagePropertyGIFDelayTime as String
            ] as? TimeInterval
            ?? 0.1
    }
}
