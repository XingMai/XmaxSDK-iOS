import Kingfisher
import SnapKit
import UIKit

final class RealtimeViewController: UIViewController {
    private let previewView = RealtimePreviewBackdropView()
    private let controlPanelView = RealtimeControlPanelView()

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .black
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configurePreview()
        configureTopControls()
        configureControlPanel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func configurePreview() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        previewView.snp.makeConstraints { make in
            make.top.horizontalEdges.equalToSuperview()
        }
    }

    private func configureTopControls() {
        let backButton = UIButton(type: .custom)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(named: "realtime_nav_back"), for: .normal)
        backButton.imageView?.contentMode = .scaleAspectFit
        backButton.accessibilityLabel = "返回首页"
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        previewView.addSubview(backButton)

        let switchCameraButton = RealtimeCameraSwitchButton()
        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false
        previewView.addSubview(switchCameraButton)

        backButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.equalToSuperview().offset(12)
            make.size.equalTo(44)
        }
        switchCameraButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(6)
            make.trailing.equalToSuperview().inset(8)
            make.width.equalTo(58)
            make.height.equalTo(62)
        }
    }

    private func configureControlPanel() {
        controlPanelView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlPanelView)

        controlPanelView.snp.makeConstraints { make in
            make.horizontalEdges.bottom.equalToSuperview()
        }
        previewView.snp.makeConstraints { make in
            make.bottom.equalTo(controlPanelView.snp.top)
        }
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }
}

private final class RealtimePreviewBackdropView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        gradientLayer.colors = [
            UIColor.feed(rgb: 0x171719).cgColor,
            UIColor.feed(rgb: 0x0D0D0F).cgColor,
            UIColor.feed(rgb: 0x050506).cgColor
        ]
        gradientLayer.locations = [0, 0.48, 1]
        gradientLayer.startPoint = CGPoint(x: 0.25, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.75, y: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class RealtimeCameraSwitchButton: UIControl {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(named: "realtime_camera_rotate")?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "翻转"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textAlignment = .center

        [iconView, titleLabel].forEach {
            $0.layer.shadowColor = UIColor.black.cgColor
            $0.layer.shadowOpacity = 0.5
            $0.layer.shadowRadius = 2
            $0.layer.shadowOffset = CGSize(width: 0, height: 1)
        }

        addSubview(iconView)
        addSubview(titleLabel)
        accessibilityLabel = "翻转摄像头"
        accessibilityTraits = .button

        iconView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(10)
            make.centerX.equalToSuperview()
            make.size.equalTo(22)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(iconView.snp.bottom).offset(6)
            make.centerX.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct RealtimeReferenceCatalog: Decodable {
    struct Item: Decodable {
        let id: String
        let categoryID: String
        let title: String
        let iconURL: URL
    }

    let items: [Item]

    static func load() -> RealtimeReferenceCatalog {
        guard
            let data = NSDataAsset(name: "RealtimeReferenceCatalog")?.data,
            let catalog = try? JSONDecoder().decode(
                RealtimeReferenceCatalog.self,
                from: data
            )
        else {
            return RealtimeReferenceCatalog(items: [])
        }
        return catalog
    }
}

private final class RealtimeControlPanelView: UIView {
    private enum Layout {
        static let topSpacing: CGFloat = 6
        static let categoryHeight: CGFloat = 36
        static let categoryLeadingSpacing: CGFloat = 11
        static let categoryItemSpacing: CGFloat = 14
        static let clearButtonLeadingSpacing: CGFloat = 14
        static let clearButtonWidth: CGFloat = 28
        static let rowSpacing: CGFloat = 4
        static let referenceHeight: CGFloat = 50
        static let promptInputHeight: CGFloat = 50
        static let bottomSpacing: CGFloat = 10
    }

    private enum Content {
        case references(categoryID: String)
        case instruction
        case prompt
    }

    private struct Category {
        let id: String
        let name: String
        let content: Content
    }

    private let categories = [
        Category(id: "charx", name: "换形象", content: .references(categoryID: "charx")),
        Category(id: "clothx", name: "换装", content: .references(categoryID: "clothx")),
        Category(id: "vibex", name: "换风格", content: .references(categoryID: "vibex")),
        Category(id: "mox", name: "触控动图", content: .instruction),
        Category(id: "dimx", name: "虚拟召唤", content: .references(categoryID: "dimx")),
        Category(id: "free", name: "自由", content: .prompt)
    ]
    private let referencesByCategory = Dictionary(
        grouping: RealtimeReferenceCatalog.load().items,
        by: \.categoryID
    )

    private let disabledActionButton = UIButton(type: .custom)
    private let categoryScrollView = RealtimeCategoryScrollView()
    private let categoryStackView = UIStackView()
    private let contentContainerView = UIView()
    private let referenceListView = RealtimeReferenceListView()
    private let instructionButton = UIButton(type: .custom)
    private let promptInputView = RealtimePromptFieldView()
    private var categoryButtons: [UIButton] = []
    private var selectedCategoryIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feed(rgb: 0x101010)
        configureCategoryRow()
        configureContentArea()
        updateCategorySelection()
        updateVisibleContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCategoryRow() {
        disabledActionButton.translatesAutoresizingMaskIntoConstraints = false
        disabledActionButton.setImage(
            UIImage(
                systemName: "nosign",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 11,
                    weight: .regular
                )
            ),
            for: .normal
        )
        disabledActionButton.tintColor = .white
        disabledActionButton.isEnabled = false
        disabledActionButton.alpha = 0.5
        disabledActionButton.accessibilityLabel = "停止生成"
        addSubview(disabledActionButton)

        categoryScrollView.translatesAutoresizingMaskIntoConstraints = false
        categoryScrollView.showsHorizontalScrollIndicator = false
        categoryScrollView.alwaysBounceHorizontal = true
        categoryScrollView.delaysContentTouches = true
        categoryScrollView.canCancelContentTouches = true
        categoryScrollView.isDirectionalLockEnabled = true
        categoryScrollView.contentInsetAdjustmentBehavior = .never
        addSubview(categoryScrollView)

        categoryStackView.translatesAutoresizingMaskIntoConstraints = false
        categoryStackView.axis = .horizontal
        categoryStackView.alignment = .fill
        categoryStackView.spacing = Layout.categoryItemSpacing
        categoryScrollView.addSubview(categoryStackView)

        for (index, category) in categories.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.setTitle(category.name, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .regular)
            button.addTarget(
                self,
                action: #selector(selectCategory(_:)),
                for: .touchUpInside
            )
            button.accessibilityIdentifier = category.id
            button.snp.makeConstraints { make in
                let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
                let textWidth = ceil(
                    (category.name as NSString).size(
                        withAttributes: [.font: font]
                    ).width
                )
                make.width.equalTo(textWidth + 10)
                make.height.equalTo(Layout.categoryHeight)
            }
            categoryStackView.addArrangedSubview(button)
            categoryButtons.append(button)
        }

        disabledActionButton.snp.makeConstraints { make in
            make.leading.equalToSuperview()
                .offset(Layout.clearButtonLeadingSpacing)
            make.centerY.equalTo(categoryScrollView)
            make.width.equalTo(Layout.clearButtonWidth)
            make.height.equalTo(Layout.categoryHeight)
        }
        categoryScrollView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Layout.topSpacing)
            make.leading.equalTo(disabledActionButton.snp.trailing)
                .offset(Layout.categoryLeadingSpacing)
            make.trailing.equalToSuperview()
            make.height.equalTo(Layout.categoryHeight)
        }
        categoryStackView.snp.makeConstraints { make in
            make.leading.equalTo(categoryScrollView.contentLayoutGuide)
            make.trailing.equalTo(categoryScrollView.contentLayoutGuide)
                .offset(-14)
            make.verticalEdges.equalTo(categoryScrollView.contentLayoutGuide)
            make.height.equalTo(categoryScrollView.frameLayoutGuide)
        }
    }

    private func configureContentArea() {
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainerView)

        contentContainerView.addSubview(referenceListView)

        instructionButton.translatesAutoresizingMaskIntoConstraints = false
        instructionButton.setTitle("点击开始生成", for: .normal)
        instructionButton.setTitleColor(.white.withAlphaComponent(0.85), for: .normal)
        instructionButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        instructionButton.backgroundColor = .white.withAlphaComponent(0.14)
        instructionButton.layer.cornerRadius = 20
        instructionButton.layer.borderWidth = 1
        instructionButton.layer.borderColor = UIColor.white.withAlphaComponent(0.19).cgColor
        instructionButton.accessibilityLabel = "点击开始生成"
        contentContainerView.addSubview(instructionButton)

        promptInputView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(promptInputView)

        contentContainerView.snp.makeConstraints { make in
            make.top.equalTo(categoryScrollView.snp.bottom)
                .offset(Layout.rowSpacing)
            make.horizontalEdges.equalToSuperview()
            make.height.equalTo(Layout.referenceHeight)
            make.bottom.equalTo(safeAreaLayoutGuide)
                .offset(-Layout.bottomSpacing)
        }
        referenceListView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        instructionButton.snp.makeConstraints { make in
            make.horizontalEdges.equalToSuperview().inset(14)
            make.centerY.equalToSuperview()
            make.height.equalTo(Layout.referenceHeight)
        }
        promptInputView.snp.makeConstraints { make in
            make.horizontalEdges.equalToSuperview().inset(14)
            make.centerY.equalToSuperview()
            make.height.equalTo(Layout.promptInputHeight)
        }
    }

    @objc private func selectCategory(_ sender: UIButton) {
        guard sender.tag != selectedCategoryIndex else { return }
        selectedCategoryIndex = sender.tag
        updateCategorySelection()
        updateVisibleContent()

        categoryScrollView.scrollRectToVisible(
            sender.convert(
                sender.bounds.insetBy(dx: -18, dy: 0),
                to: categoryScrollView
            ),
            animated: true
        )
    }

    private func updateCategorySelection() {
        for (index, button) in categoryButtons.enumerated() {
            let isSelected = index == selectedCategoryIndex
            button.setTitleColor(
                isSelected ? .white : .white.withAlphaComponent(0.48),
                for: .normal
            )
            button.titleLabel?.font = .systemFont(
                ofSize: 13,
                weight: isSelected ? .semibold : .regular
            )
            button.accessibilityTraits =
                isSelected ? [.button, .selected] : .button
        }
    }

    private func updateVisibleContent() {
        referenceListView.isHidden = true
        instructionButton.isHidden = true
        promptInputView.isHidden = true

        switch categories[selectedCategoryIndex].content {
        case let .references(categoryID):
            referenceListView.isHidden = false
            referenceListView.apply(
                references: referencesByCategory[categoryID] ?? []
            )
        case .instruction:
            instructionButton.isHidden = false
        case .prompt:
            promptInputView.isHidden = false
        }
    }

}

private final class RealtimeCategoryScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }
}

private final class RealtimeReferenceListView: UIView {
    private enum Layout {
        static let itemLength: CGFloat = 50
        static let itemSpacing: CGFloat = 10
        static let edgeFadeWidth: CGFloat = 32
        static let selectionBorderWidth: CGFloat = 2
        static let edgeFadeTransitionDuration: CFTimeInterval = 0.3
    }

    private let collectionView: UICollectionView
    private let addReferenceButton = UIButton(type: .custom)
    private let edgeFadeMaskLayer = CAGradientLayer()
    private let feedbackGenerator = UISelectionFeedbackGenerator()
    private var references: [RealtimeReferenceCatalog.Item] = []
    private var selectedReferenceID: String?
    private var hasConfiguredEdgeFadeMask = false
    private var isShowingLeftFade = false
    private var isShowingRightFade = false

    override init(frame: CGRect) {
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
        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )

        super.init(frame: frame)

        addReferenceButton.setImage(
            UIImage(named: "realtime_add_reference"),
            for: .normal
        )
        addReferenceButton.imageView?.contentMode = .scaleAspectFill
        addReferenceButton.backgroundColor = .feed(rgb: 0x303032)
        addReferenceButton.layer.cornerRadius = 10
        addReferenceButton.layer.cornerCurve = .continuous
        addReferenceButton.clipsToBounds = true
        addReferenceButton.accessibilityLabel = "添加参考图"

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

    func apply(references: [RealtimeReferenceCatalog.Item]) {
        self.references = references
        selectedReferenceID = nil
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
        collectionView.layoutIfNeeded()
        updateEdgeFadeMask()
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
        selectedReferenceID = reference.id
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
        collectionView.scrollToItem(
            at: indexPath,
            at: .centeredHorizontally,
            animated: true
        )
    }
}

private final class RealtimeReferenceCell: UICollectionViewCell {
    static let reuseIdentifier = "RealtimeReferenceCell"

    private let selectionBorderView = UIView()
    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false

        selectionBorderView.backgroundColor = .clear
        selectionBorderView.layer.borderWidth = Layout.selectionBorderWidth
        selectionBorderView.layer.borderColor = UIColor.feed(rgb: 0xFF2E88).cgColor
        selectionBorderView.layer.cornerRadius = 12
        selectionBorderView.isHidden = true
        selectionBorderView.isUserInteractionEnabled = false

        contentView.backgroundColor = .feed(rgb: 0x303032)
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        insertSubview(selectionBorderView, belowSubview: contentView)
        contentView.addSubview(imageView)

        selectionBorderView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
                .inset(-Layout.selectionBorderWidth)
        }
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
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
    }

    func configure(
        reference: RealtimeReferenceCatalog.Item,
        isSelected: Bool
    ) {
        accessibilityLabel = reference.title
        selectionBorderView.isHidden = !isSelected
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        loadImage(from: reference.iconURL)
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
                .cacheOriginalImage
            ]
        )
    }

    private enum Layout {
        static let selectionBorderWidth: CGFloat = 2
    }
}

private final class RealtimePromptFieldView: UIView, UITextFieldDelegate {
    private let textField = UITextField()
    private let submitControl = RealtimePromptCircleView(
        imageName: "realtime_prompt_submit",
        imageSize: CGSize(width: 13, height: 14),
        backgroundColor: .feed(rgb: 0xFF2E88)
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feed(rgb: 0x272728)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous

        textField.translatesAutoresizingMaskIntoConstraints = false
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

        let addControl = RealtimePromptCircleView(
            imageName: "realtime_prompt_add",
            imageSize: CGSize(width: 14, height: 14),
            backgroundColor: .white.withAlphaComponent(0.12)
        )

        addSubview(textField)
        addSubview(addControl)
        addSubview(submitControl)
        submitControl.alpha = 0.2

        textField.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(11)
            make.verticalEdges.equalToSuperview()
            make.trailing.equalTo(addControl.snp.leading).offset(-10)
        }
        addControl.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.size.equalTo(32)
        }
        submitControl.snp.makeConstraints { make in
            make.leading.equalTo(addControl.snp.trailing).offset(8)
            make.trailing.equalToSuperview().offset(-8)
            make.centerY.equalToSuperview()
            make.size.equalTo(32)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func textDidChange() {
        let hasText = !(textField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        submitControl.alpha = hasText ? 1 : 0.2
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

private final class RealtimePromptCircleView: UIView {
    init(
        imageName: String,
        imageSize: CGSize,
        backgroundColor: UIColor
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = backgroundColor
        layer.cornerRadius = 16
        clipsToBounds = true

        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(imageSize)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
