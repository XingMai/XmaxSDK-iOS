import Kingfisher
import SnapKit
import UIKit

final class RealtimeReferenceListView: UIView {
    private enum Layout {
        static let itemLength: CGFloat = 50
        static let itemSpacing: CGFloat = 10
        static let edgeFadeWidth: CGFloat = 32
        static let selectionBorderWidth: CGFloat = 2
        static let edgeFadeTransitionDuration: CFTimeInterval = 0.3
    }

    private let feedbackGenerator = UISelectionFeedbackGenerator()
    private var references: [RealtimeReferenceCatalog.Item] = []
    private var selectedReferenceID: String?
    private var hasConfiguredEdgeFadeMask = false
    private var isShowingLeftFade = false
    private var isShowingRightFade = false

    var onSelectionChanged: ((RealtimeReferenceCatalog.Item?) -> Void)?
    var onAddReference: (() -> Void)?
    var onRetryUpload: ((RealtimeReferenceCatalog.Item) -> Void)?

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(
            width: Layout.itemLength,
            height: Layout.itemLength
        )
        layout.minimumLineSpacing = Layout.itemSpacing
        layout.sectionInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: 0,
            right: 14
        )

        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        collectionView.backgroundColor = .clear
        collectionView.clipsToBounds = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.alwaysBounceVertical = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(
            RealtimeReferenceCell.self,
            forCellWithReuseIdentifier: RealtimeReferenceCell.reuseIdentifier
        )
        return collectionView
    }()

    private lazy var addReferenceButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(
            UIImage(named: "realtime_add_reference"),
            for: .normal
        )
        button.imageView?.contentMode = .scaleAspectFill
        button.backgroundColor = .feed(rgb: 0x303032)
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.accessibilityLabel = "添加参考图"
        button.addTarget(
            self,
            action: #selector(addReference),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var edgeFadeMaskLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(addReferenceButton)
        addSubview(collectionView)

        addReferenceButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.size.equalTo(Layout.itemLength)
        }
        collectionView.snp.makeConstraints { make in
            make.verticalEdges.trailing.equalToSuperview()
            make.leading.equalTo(addReferenceButton.snp.trailing)
                .offset(Layout.itemSpacing)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateEdgeFadeMask()
    }

    func apply(
        references: [RealtimeReferenceCatalog.Item],
        selectedReferenceID: String?
    ) {
        self.references = references
        self.selectedReferenceID = selectedReferenceID.flatMap { selectedID in
            references.contains(where: { $0.id == selectedID })
                ? selectedID
                : nil
        }
        collectionView.reloadData()
        updateEdgeFadeMask()
    }

    func setSelectedReferenceID(_ referenceID: String?) {
        let validatedReferenceID = referenceID.flatMap { referenceID in
            references.contains(where: { $0.id == referenceID })
                ? referenceID
                : nil
        }
        let previousReferenceID = selectedReferenceID
        guard previousReferenceID != validatedReferenceID else { return }

        selectedReferenceID = validatedReferenceID
        let changedIndexPaths = references.enumerated().compactMap {
            index, reference -> IndexPath? in
            guard reference.id == previousReferenceID
                    || reference.id == validatedReferenceID else {
                return nil
            }
            return IndexPath(item: index, section: 0)
        }
        collectionView.reloadItems(at: changedIndexPaths)
    }

    func centerSelectedReference(animated: Bool) {
        guard let selectedReferenceID,
              let index = references.firstIndex(where: {
                  $0.id == selectedReferenceID
              }) else {
            return
        }
        collectionView.scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: .centeredHorizontally,
            animated: animated
        )
    }

    func insert(_ reference: RealtimeReferenceCatalog.Item) {
        let previousReferenceID = selectedReferenceID
        references.insert(reference, at: 0)
        selectedReferenceID = reference.id

        collectionView.performBatchUpdates {
            collectionView.insertItems(
                at: [IndexPath(item: 0, section: 0)]
            )
        } completion: { [weak self] _ in
            guard let self else { return }
            if let previousReferenceID,
               let previousIndex = references.firstIndex(where: {
                   $0.id == previousReferenceID
               }) {
                collectionView.reloadItems(
                    at: [IndexPath(item: previousIndex, section: 0)]
                )
            }
            collectionView.scrollToItem(
                at: IndexPath(item: 0, section: 0),
                at: .left,
                animated: true
            )
            updateEdgeFadeMask()
        }
        onSelectionChanged?(reference)
    }

    func update(_ reference: RealtimeReferenceCatalog.Item) {
        guard let index = references.firstIndex(where: {
            $0.id == reference.id
        }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        if let cell = collectionView.cellForItem(
            at: indexPath
        ) as? RealtimeReferenceCell {
            cell.setUploadState(reference.uploadState, animated: true)
            return
        }
        collectionView.reloadItems(
            at: [indexPath]
        )
    }

    func isSelected(_ referenceID: String) -> Bool {
        selectedReferenceID == referenceID
    }

    private func updateEdgeFadeMask() {
        let inset = collectionView.adjustedContentInset
        let minimumOffsetX = -inset.left
        let maximumOffsetX = max(
            minimumOffsetX,
            collectionView.contentSize.width
                - collectionView.bounds.width
                + inset.right
        )
        let threshold: CGFloat = 0.5
        let showsLeftFade =
            collectionView.contentOffset.x > minimumOffsetX + threshold
        let showsRightFade =
            collectionView.contentOffset.x < maximumOffsetX - threshold

        let maskBounds = collectionView.bounds.insetBy(
            dx: -Layout.selectionBorderWidth,
            dy: -Layout.selectionBorderWidth
        )
        let width = maskBounds.width
        guard width > 0 else { return }

        let fadeLocation = NSNumber(
            value: min(Layout.edgeFadeWidth, width / 2) / width
        )
        let trailingFadeLocation = NSNumber(
            value: 1 - fadeLocation.doubleValue
        )
        let transparent = UIColor.clear.cgColor
        let opaque = UIColor.black.cgColor
        let colors = [
            showsLeftFade ? transparent : opaque,
            opaque,
            opaque,
            showsRightFade ? transparent : opaque
        ]
        let visibilityChanged =
            showsLeftFade != isShowingLeftFade
            || showsRightFade != isShowingRightFade
        let shouldAnimate = hasConfiguredEdgeFadeMask && visibilityChanged
        let currentColors =
            edgeFadeMaskLayer.presentation()?.colors
            ?? edgeFadeMaskLayer.colors

        isShowingLeftFade = showsLeftFade
        isShowingRightFade = showsRightFade
        hasConfiguredEdgeFadeMask = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeFadeMaskLayer.colors = colors
        edgeFadeMaskLayer.locations = [
            0,
            fadeLocation,
            trailingFadeLocation,
            1
        ]
        edgeFadeMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        edgeFadeMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        edgeFadeMaskLayer.frame = maskBounds
        collectionView.layer.mask = edgeFadeMaskLayer
        CATransaction.commit()

        guard shouldAnimate else { return }

        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = currentColors
        animation.toValue = colors
        animation.duration = Layout.edgeFadeTransitionDuration
        animation.timingFunction = CAMediaTimingFunction(
            name: .easeInEaseOut
        )
        edgeFadeMaskLayer.add(animation, forKey: "edgeFadeTransition")
    }

    @objc private func addReference() {
        onAddReference?()
    }
}

extension RealtimeReferenceListView: UICollectionViewDataSource,
    UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        references.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: RealtimeReferenceCell.reuseIdentifier,
                for: indexPath
            ) as? RealtimeReferenceCell
        else {
            return UICollectionViewCell()
        }

        let reference = references[indexPath.item]
        cell.configure(
            reference: reference,
            isSelected: reference.id == selectedReferenceID
        )
        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateEdgeFadeMask()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        let previousReferenceID = selectedReferenceID
        let reference = references[indexPath.item]
        if reference.uploadState == .failed {
            onRetryUpload?(reference)
            return
        }
        let isCancellingSelection = previousReferenceID == reference.id
        selectedReferenceID = isCancellingSelection ? nil : reference.id
        feedbackGenerator.selectionChanged()

        let changedIndexPaths = references.enumerated().compactMap {
            index, item -> IndexPath? in
            guard
                item.id == previousReferenceID
                || item.id == selectedReferenceID
            else {
                return nil
            }
            return IndexPath(item: index, section: 0)
        }
        collectionView.reloadItems(at: changedIndexPaths)
        if isCancellingSelection {
            onSelectionChanged?(nil)
        } else {
            collectionView.scrollToItem(
                at: indexPath,
                at: .centeredHorizontally,
                animated: true
            )
            onSelectionChanged?(reference)
        }
    }
}

private final class RealtimeReferenceCell: UICollectionViewCell {
    private enum Layout {
        static let selectionBorderWidth: CGFloat = 2
    }

    static let reuseIdentifier = "RealtimeReferenceCell"

    private lazy var selectionBorderView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.borderWidth = Layout.selectionBorderWidth
        view.layer.borderColor = UIColor.feed(rgb: 0xFF2E88).cgColor
        view.layer.cornerRadius = 12
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }()

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }()

    private lazy var uploadOverlayView: UIView = {
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
        view.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        return view
    }()

    private lazy var retryImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: 16,
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
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false

        contentView.backgroundColor = .feed(rgb: 0x303032)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        insertSubview(selectionBorderView, belowSubview: contentView)
        contentView.addSubview(imageView)
        contentView.addSubview(uploadOverlayView)
        uploadOverlayView.addSubview(uploadIndicator)
        uploadOverlayView.addSubview(retryImageView)

        selectionBorderView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
                .inset(-Layout.selectionBorderWidth)
        }
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        uploadOverlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        uploadIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        retryImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(20)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        selectionBorderView.isHidden = true
        uploadOverlayView.isHidden = true
        uploadIndicator.stopAnimating()
        retryImageView.isHidden = true
    }

    func configure(
        reference: RealtimeReferenceCatalog.Item,
        isSelected: Bool
    ) {
        accessibilityLabel = reference.title
        selectionBorderView.isHidden = !isSelected
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        loadImage(from: reference.iconURL)
        setUploadState(reference.uploadState, animated: false)
    }

    func setUploadState(
        _ state: RealtimeReferenceUploadState,
        animated: Bool
    ) {
        uploadOverlayView.layer.removeAllAnimations()
        uploadOverlayView.alpha = 1
        uploadIndicator.stopAnimating()
        retryImageView.isHidden = true

        switch state {
        case .ready:
            guard animated, !uploadOverlayView.isHidden else {
                uploadOverlayView.isHidden = true
                return
            }
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.uploadOverlayView.alpha = 0
            } completion: { _ in
                self.uploadOverlayView.isHidden = true
                self.uploadOverlayView.alpha = 1
            }
        case .uploading:
            uploadOverlayView.isHidden = false
            uploadIndicator.startAnimating()
        case .failed:
            uploadOverlayView.isHidden = false
            retryImageView.isHidden = false
        }
    }

    private func loadImage(from url: URL) {
        let scale = max(traitCollection.displayScale, 1)
        imageView.kf.setImage(
            with: url,
            options: [
                .processor(
                    DownsamplingImageProcessor(
                        size: CGSize(width: 75, height: 75)
                    )
                ),
                .scaleFactor(scale),
                .transition(.fade(0.2)),
                .loadDiskFileSynchronously,
                .cacheOriginalImage
            ]
        )
    }
}
