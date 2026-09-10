import SnapKit
import UIKit

enum RealtimeRecordingButtonState {
    case idle
    case preparing
    case recording
    case saving
}

final class RealtimeMediaTopBar: UIView {
    private enum Layout {
        static let itemWidth: CGFloat = 48
        static let height: CGFloat = 50
        static let iconSize: CGFloat = 17
    }

    // 事件监听
    var onOpenGallery: (() -> Void)?
    var onToggleRecording: (() -> Void)?
    var onOpenAudioVolume: ((UIView) -> Void)?
    var onMuteChanged: ((Bool) -> Void)?
    var onFrameInterpolationChanged: ((Bool) -> Void)?

    // 显示配置
    private let showsVideoControls: Bool

    // 运行状态
    private var isMuted = false
    private var isFrameInterpolationEnabled = false

    // 界面组件
    private lazy var recordingButton: RealtimeMediaActionButton = {
        let button = makeActionButton(
            title: XLLocalization.text("record.title"),
            systemName: "record.circle",
            accessibilityLabel: XLLocalization.text("record.start")
        )
        button.accessibilityValue = XLLocalization.text("record.idle")
        button.addTarget(
            self,
            action: #selector(toggleRecording),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var audioVolumeButton: RealtimeMediaActionButton = {
        let button = makeActionButton(
            title: XLLocalization.text("realtime.volume"),
            systemName: "slider.horizontal.3",
            accessibilityLabel: XLLocalization.text("realtime.volume.adjust")
        )
        button.addTarget(
            self,
            action: #selector(openAudioVolume),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var muteButton: RealtimeMediaActionButton = {
        let button = makeActionButton(
            title: XLLocalization.text("realtime.sound"),
            systemName: "speaker.wave.2.fill",
            accessibilityLabel: XLLocalization.text("realtime.sound.disable")
        )
        button.addTarget(
            self,
            action: #selector(toggleMute),
            for: .touchUpInside
        )
        button.accessibilityValue = XLLocalization.text("common.enabled")
        return button
    }()

    private lazy var frameInterpolationButton: RealtimeMediaActionButton = {
        let button = makeActionButton(
            title: XLLocalization.text("realtime.interpolation"),
            systemName: "bolt.fill",
            accessibilityLabel: isFrameInterpolationEnabled
                ? XLLocalization.text("realtime.interpolation.disable")
                : XLLocalization.text("realtime.interpolation.enable")
        )
        button.setActive(isFrameInterpolationEnabled)
        button.accessibilityValue = isFrameInterpolationEnabled
            ? XLLocalization.text("common.enabled")
            : XLLocalization.text("common.disabled")
        button.addTarget(
            self,
            action: #selector(toggleFrameInterpolation),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var galleryButton: RealtimeMediaActionButton = {
        let button = makeActionButton(
            title: XLLocalization.text("realtime.photos"),
            systemName: "photo",
            accessibilityLabel: XLLocalization.text("realtime.photos.replace")
        )
        button.addTarget(
            self,
            action: #selector(openGallery),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var stackView: UIStackView = {
        var buttons: [UIView] = []
        if showsVideoControls {
            buttons.append(recordingButton)
            buttons.append(audioVolumeButton)
            buttons.append(muteButton)
        }
        buttons.append(frameInterpolationButton)
        buttons.append(galleryButton)

        let stackView = UIStackView(arrangedSubviews: buttons)
        stackView.axis = .horizontal
        stackView.alignment = .fill
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        return stackView
    }()

    init(showsVideoControls: Bool) {
        self.showsVideoControls = showsVideoControls
        super.init(frame: .zero)

        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: CGFloat(showsVideoControls ? 5 : 2) * Layout.itemWidth,
            height: Layout.height
        )
    }

    private func makeActionButton(
        title: String,
        systemName: String,
        accessibilityLabel: String
    ) -> RealtimeMediaActionButton {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: Layout.iconSize,
            weight: .medium
        )
        let button = RealtimeMediaActionButton(
            title: title,
            image: UIImage(
                systemName: systemName,
                withConfiguration: configuration
            )
        )
        button.accessibilityLabel = accessibilityLabel
        return button
    }

    @objc private func toggleMute() {
        isMuted.toggle()
        renderMuteState()
        onMuteChanged?(isMuted)
    }

    func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        renderMuteState()
    }

    func setRecordingState(_ state: RealtimeRecordingButtonState) {
        switch state {
        case .idle:
            recordingButton.setContent(
                title: XLLocalization.text("record.title"),
                image: makeSymbolImage(systemName: "record.circle")
            )
            recordingButton.setTintColor(.white)
            recordingButton.isEnabled = true
            recordingButton.accessibilityLabel = XLLocalization.text("record.start")
            recordingButton.accessibilityValue = XLLocalization.text("record.idle")
        case .preparing:
            recordingButton.setContent(
                title: XLLocalization.text("record.prepare"),
                image: makeSymbolImage(systemName: "hourglass")
            )
            recordingButton.setTintColor(.systemOrange)
            recordingButton.isEnabled = false
            recordingButton.accessibilityLabel = XLLocalization.text("record.preparing.label")
            recordingButton.accessibilityValue = XLLocalization.text("record.preparing")
        case .recording:
            recordingButton.setContent(
                title: XLLocalization.text("record.stop"),
                image: makeSymbolImage(systemName: "stop.circle.fill")
            )
            recordingButton.setTintColor(.systemRed)
            recordingButton.isEnabled = true
            recordingButton.accessibilityLabel = XLLocalization.text("record.stopSave")
            recordingButton.accessibilityValue = XLLocalization.text("record.recording")
        case .saving:
            recordingButton.setContent(
                title: XLLocalization.text("record.save"),
                image: makeSymbolImage(systemName: "hourglass")
            )
            recordingButton.setTintColor(.systemOrange)
            recordingButton.isEnabled = false
            recordingButton.accessibilityLabel = XLLocalization.text("record.saving.label")
            recordingButton.accessibilityValue = XLLocalization.text("record.saving")
        }
    }

    func setFrameInterpolationEnabled(_ enabled: Bool) {
        isFrameInterpolationEnabled = enabled
        frameInterpolationButton.setActive(enabled)
        frameInterpolationButton.accessibilityLabel = enabled
            ? XLLocalization.text("realtime.interpolation.disable")
            : XLLocalization.text("realtime.interpolation.enable")
        frameInterpolationButton.accessibilityValue = enabled
            ? XLLocalization.text("common.enabled")
            : XLLocalization.text("common.disabled")
    }

    private func renderMuteState() {
        muteButton.setContent(
            title: isMuted ? XLLocalization.text("realtime.mute") : XLLocalization.text("realtime.sound"),
            image: makeSymbolImage(
                systemName: isMuted
                    ? "speaker.slash.fill"
                    : "speaker.wave.2.fill"
            )
        )
        muteButton.accessibilityLabel = isMuted ? XLLocalization.text("realtime.sound.enable") : XLLocalization.text("realtime.sound.disable")
        muteButton.accessibilityValue = isMuted ? XLLocalization.text("realtime.muted") : XLLocalization.text("common.enabled")
    }

    @objc private func openAudioVolume() {
        onOpenAudioVolume?(audioVolumeButton)
    }

    @objc private func toggleRecording() {
        onToggleRecording?()
    }

    @objc private func toggleFrameInterpolation() {
        onFrameInterpolationChanged?(!isFrameInterpolationEnabled)
    }

    private func makeSymbolImage(systemName: String) -> UIImage? {
        UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: Layout.iconSize,
                weight: .medium
            )
        )
    }

    @objc private func openGallery() {
        onOpenGallery?()
    }
}

final class RealtimeAudioVolumeMenuViewController: UIViewController,
    UIPopoverPresentationControllerDelegate {

    // 音量回调
    var onLocalVolumeChanged: ((Float) -> Void)?
    var onRemoteVolumeChanged: ((Float) -> Void)?

    // 界面组件
    private let localVolumeRow: RealtimeAudioVolumeSliderRow?
    private let remoteVolumeRow: RealtimeAudioVolumeSliderRow

    init(localVolume: Float? = nil, remoteVolume: Float) {
        localVolumeRow = localVolume.map {
            RealtimeAudioVolumeSliderRow(title: XLLocalization.text("realtime.volume.local"), value: $0)
        }
        remoteVolumeRow = RealtimeAudioVolumeSliderRow(
            title: XLLocalization.text("realtime.volume.remote"),
            value: remoteVolume
        )
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover
        preferredContentSize = CGSize(
            width: 260,
            height: localVolume == nil ? 82 : 144
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 14
        view.clipsToBounds = true

        localVolumeRow?.onValueChanged = { [weak self] value in
            self?.onLocalVolumeChanged?(value)
        }
        remoteVolumeRow.onValueChanged = { [weak self] value in
            self?.onRemoteVolumeChanged?(value)
        }

        let stackView = UIStackView(
            arrangedSubviews: [localVolumeRow, remoteVolumeRow].compactMap { $0 }
        )
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        stackView.spacing = 8
        view.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(14)
        }
    }

    func adaptivePresentationStyle(
        for controller: UIPresentationController
    ) -> UIModalPresentationStyle {
        .none
    }
}

private final class RealtimeAudioVolumeSliderRow: UIView {

    // 音量回调
    var onValueChanged: ((Float) -> Void)?

    // 界面组件
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()

    init(title: String, value: Float) {
        super.init(frame: .zero)

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .label

        valueLabel.font = .monospacedDigitSystemFont(
            ofSize: 12,
            weight: .regular
        )
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = value
        slider.minimumTrackTintColor = .systemPink
        slider.accessibilityLabel = title
        slider.addTarget(
            self,
            action: #selector(sliderValueChanged),
            for: .valueChanged
        )

        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(slider)
        titleLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview()
        }
        valueLabel.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview()
            make.leading.greaterThanOrEqualTo(titleLabel.snp.trailing)
                .offset(8)
        }
        slider.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.horizontalEdges.bottom.equalToSuperview()
        }
        renderValue(value)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func sliderValueChanged() {
        renderValue(slider.value)
        onValueChanged?(slider.value)
    }

    private func renderValue(_ value: Float) {
        let percentage = Int((value * 100).rounded())
        valueLabel.text = "\(percentage)%"
        slider.accessibilityValue = valueLabel.text
    }
}

private final class RealtimeMediaActionButton: UIControl {
    private lazy var iconView: UIImageView = {
        let imageView = UIImageView(image: image?.withRenderingMode(.alwaysTemplate))
        imageView.tintColor = .white
        imageView.contentMode = .center
        configureShadow(for: imageView)
        return imageView
    }()

    private lazy var actionLabel: UILabel = {
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        configureShadow(for: label)
        return label
    }()

    private let title: String
    private let image: UIImage?

    init(title: String, image: UIImage?) {
        self.title = title
        self.image = image
        super.init(frame: .zero)

        accessibilityTraits = .button
        addSubview(iconView)
        addSubview(actionLabel)

        iconView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(5)
            make.centerX.equalToSuperview()
            make.width.equalTo(28)
            make.height.equalTo(22)
        }
        actionLabel.snp.makeConstraints { make in
            make.top.equalTo(iconView.snp.bottom).offset(2)
            make.centerX.equalToSuperview()
            make.horizontalEdges.equalToSuperview().inset(2)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent(title: String, image: UIImage?) {
        actionLabel.text = title
        iconView.image = image?.withRenderingMode(.alwaysTemplate)
    }

    func setActive(_ isActive: Bool) {
        iconView.tintColor = isActive ? .systemYellow : .white
        if isActive {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }
    }

    func setTintColor(_ color: UIColor) {
        iconView.tintColor = color
    }

    override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1 : 0.55
            accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
        }
    }

    override var isHighlighted: Bool {
        didSet {
            guard isEnabled else { return }
            alpha = isHighlighted ? 0.55 : 1
        }
    }

    private func configureShadow(for view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.5
        view.layer.shadowRadius = 2
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
    }
}
