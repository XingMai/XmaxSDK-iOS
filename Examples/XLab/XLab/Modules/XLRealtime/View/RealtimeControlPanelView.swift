import SnapKit
import UIKit

final class RealtimeControlPanelView: UIView {
    private enum Layout {
        static let topSpacing: CGFloat = 6
        static let categoryHeight: CGFloat = 36
        static let categoryLeadingSpacing: CGFloat = 11
        static let categoryItemSpacing: CGFloat = 14
        static let clearButtonLeadingSpacing: CGFloat = 14
        static let clearButtonWidth: CGFloat = 28
        static let rowSpacing: CGFloat = 4
        static let referenceHeight: CGFloat = 50
        static let instructionHeight: CGFloat = 40
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
        Category(
            id: "charx",
            name: "换形象",
            content: .references(categoryID: "charx")
        ),
        Category(
            id: "clothx",
            name: "换装",
            content: .references(categoryID: "clothx")
        ),
        Category(
            id: "vibex",
            name: "换风格",
            content: .references(categoryID: "vibex")
        ),
        Category(
            id: "dimx",
            name: "虚拟召唤",
            content: .references(categoryID: "dimx")
        ),
        Category(id: "mox", name: "触控动图", content: .instruction),
        Category(id: "free", name: "自由", content: .prompt)
    ]
    private var referencesByCategory = Dictionary(
        grouping: RealtimeReferenceCatalog.load().items,
        by: \.categoryID
    )
    private var categoryButtons: [UIButton] = []
    private var referenceListViews: [String: RealtimeReferenceListView] = [:]
    private var selectedCategoryIndex = 0
    private var selectedReferenceID: String?
    private var isGenerationActive = false

    var onBeginPromptEditing: ((String) -> Void)?
    var onReferenceSelectionChanged: ((RealtimeReferenceCatalog.Item?) -> Void)?
    var onAddReference: ((String) -> Void)?
    var onRetryReferenceUpload: ((RealtimeReferenceCatalog.Item) -> Void)?
    var onPromptReferenceAction: (() -> Void)?
    var onInstructionAction: (() -> Void)?
    var onDisableGeneration: (() -> Void)?

    private lazy var disabledActionButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(
            UIImage(
                systemName: "nosign",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 13,
                    weight: .regular
                )
            ),
            for: .normal
        )
        button.tintColor = .white
        button.alpha = 0.5
        button.isEnabled = false
        button.accessibilityLabel = "停止生成"
        button.addTarget(
            self,
            action: #selector(disableGeneration),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var categoryScrollView: RealtimeCategoryScrollView = {
        let scrollView = RealtimeCategoryScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delaysContentTouches = true
        scrollView.canCancelContentTouches = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.contentInsetAdjustmentBehavior = .never
        return scrollView
    }()

    private lazy var categoryStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = Layout.categoryItemSpacing
        return stack
    }()

    private lazy var contentContainerView = UIView()

    private lazy var instructionButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setTitle("点击开始生成", for: .normal)
        button.setTitleColor(.white.withAlphaComponent(0.85), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.backgroundColor = .white.withAlphaComponent(0.14)
        button.layer.cornerRadius = Layout.instructionHeight / 2
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white
            .withAlphaComponent(0.19)
            .cgColor
        button.accessibilityLabel = "点击开始生成"
        button.addTarget(
            self,
            action: #selector(performInstructionAction),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var promptInputView: RealtimePromptFieldView = {
        let view = RealtimePromptFieldView()
        view.onBeginEditing = { [weak self] text in
            self?.onBeginPromptEditing?(text)
        }
        view.onReferenceAction = { [weak self] in
            self?.onPromptReferenceAction?()
        }
        return view
    }()

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

    func setPromptText(_ text: String) {
        promptInputView.setText(text)
    }

    func setPromptReference(_ reference: RealtimeReferenceCatalog.Item?) {
        promptInputView.setReference(reference)
    }

    func insertReference(_ reference: RealtimeReferenceCatalog.Item) {
        referencesByCategory[reference.categoryID, default: []]
            .insert(reference, at: 0)
        selectedReferenceID = reference.id
        referenceListViews[reference.categoryID]?.insert(reference)
        updateReferenceSelection()
    }

    func updateReference(_ reference: RealtimeReferenceCatalog.Item) {
        referenceListViews[reference.categoryID]?.update(reference)
    }

    func isReferenceSelected(_ referenceID: String) -> Bool {
        selectedReferenceID == referenceID
    }

    func clearReferenceSelection(matching referenceID: String? = nil) {
        guard referenceID == nil || referenceID == selectedReferenceID else {
            return
        }
        selectedReferenceID = nil
        updateReferenceSelection()
    }

    func setGenerationActive(_ isActive: Bool, animated: Bool = true) {
        isGenerationActive = isActive
        updateInstructionState()
        guard disabledActionButton.isEnabled != isActive else { return }
        disabledActionButton.isEnabled = isActive

        let changes = {
            self.disabledActionButton.alpha = isActive ? 1 : 0.5
        }
        guard animated, window != nil else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [
                .beginFromCurrentState,
                .allowUserInteraction,
                .curveEaseInOut
            ],
            animations: changes
        )
    }

    private func updateInstructionState() {
        instructionButton.setTitle(
            isGenerationActive
                ? "在画面上拖拽，用轨迹控制角色"
                : "点击开始生成",
            for: .normal
        )
        instructionButton.titleLabel?.font = .systemFont(
            ofSize: 13,
            weight: .medium
        )
        instructionButton.setTitleColor(
            .white.withAlphaComponent(isGenerationActive ? 0.4 : 0.85),
            for: .normal
        )
        instructionButton.backgroundColor = .white.withAlphaComponent(
            isGenerationActive ? 0.09 : 0.14
        )
        instructionButton.accessibilityLabel = isGenerationActive
            ? "触控动图生成中"
            : "点击开始生成"
    }

    private func configureCategoryRow() {
        addSubview(disabledActionButton)
        addSubview(categoryScrollView)
        categoryScrollView.addSubview(categoryStackView)

        for (index, category) in categories.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.setTitle(category.name, for: .normal)
            button.titleLabel?.font = .systemFont(
                ofSize: 13,
                weight: .regular
            )
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
        addSubview(contentContainerView)

        configureReferenceListViews()
        contentContainerView.addSubview(instructionButton)
        contentContainerView.addSubview(promptInputView)

        contentContainerView.snp.makeConstraints { make in
            make.top.equalTo(categoryScrollView.snp.bottom)
                .offset(Layout.rowSpacing)
            make.horizontalEdges.equalToSuperview()
            make.height.equalTo(Layout.referenceHeight)
            make.bottom.equalTo(safeAreaLayoutGuide)
                .offset(-Layout.bottomSpacing)
        }
        instructionButton.snp.makeConstraints { make in
            make.horizontalEdges.equalToSuperview().inset(14)
            make.centerY.equalToSuperview()
            make.height.equalTo(Layout.instructionHeight)
        }
        promptInputView.snp.makeConstraints { make in
            make.horizontalEdges.equalToSuperview().inset(14)
            make.centerY.equalToSuperview()
            make.height.equalTo(Layout.promptInputHeight)
        }
    }

    private func configureReferenceListViews() {
        for category in categories {
            guard case let .references(categoryID) = category.content else {
                continue
            }

            let listView: RealtimeReferenceListView = {
                let view = RealtimeReferenceListView()
                view.onSelectionChanged = { [weak self] reference in
                    guard let self else { return }
                    selectedReferenceID = reference?.id
                    updateReferenceSelection()
                    onReferenceSelectionChanged?(reference)
                }
                view.onAddReference = { [weak self] in
                    self?.onAddReference?(categoryID)
                }
                view.onRetryUpload = { [weak self] reference in
                    self?.onRetryReferenceUpload?(reference)
                }
                view.isHidden = true
                return view
            }()

            contentContainerView.addSubview(listView)
            listView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            listView.apply(
                references: referencesByCategory[categoryID] ?? [],
                selectedReferenceID: nil
            )
            referenceListViews[categoryID] = listView
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
        referenceListViews.values.forEach { $0.isHidden = true }
        instructionButton.isHidden = true
        promptInputView.isHidden = true

        switch categories[selectedCategoryIndex].content {
        case let .references(categoryID):
            guard let listView = referenceListViews[categoryID] else {
                return
            }
            listView.isHidden = false
            guard let selectedReferenceID,
                  listView.isSelected(selectedReferenceID) else {
                return
            }
            DispatchQueue.main.async {
                listView.centerSelectedReference(animated: true)
            }
        case .instruction:
            instructionButton.isHidden = false
        case .prompt:
            promptInputView.isHidden = false
        }
    }

    private func updateReferenceSelection() {
        for (categoryID, listView) in referenceListViews {
            let selectedID = selectedReferenceID.flatMap { selectedID in
                referencesByCategory[categoryID]?.contains(where: {
                    $0.id == selectedID
                }) == true ? selectedID : nil
            }
            listView.setSelectedReferenceID(selectedID)
        }
    }

    @objc private func disableGeneration() {
        clearReferenceSelection()
        onDisableGeneration?()
    }

    @objc private func performInstructionAction() {
        guard !isGenerationActive else { return }
        onInstructionAction?()
    }
}

private final class RealtimeCategoryScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }
}
