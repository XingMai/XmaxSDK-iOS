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
            title: "录制",
            systemName: "record.circle",
            accessibilityLabel: "开始录制生成视频"
        )
        button.accessibilityValue = "未录制"
        button.addTarget(
            self,
            action: #selector(toggleRecording),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var audioVolumeButton: RealtimeMediaActionButton = {
        let button = makeActionButton(
            title: "音量",
            systemName: "slider.horizontal.3",
            accessibilityLabel: "调整音量"
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
            title: "声音",
            systemName: "speaker.wave.2.fill",
            accessibilityLabel: "关闭声音"
        )
        button.addTarget(
            self,
            action: #selector(toggleMute),
            for: .touchUpInside
        )
        button.accessibilityValue = "已开启"
        return button
    }()

    private lazy var frameInterpolationButton: RealtimeMediaActionButton = {
        let button = makeActionButton(
            title: "插帧",
            systemName: "bolt.fill",
            accessibilityLabel: isFrameInterpolationEnabled
                ? "关闭插帧"
                : "开启插帧"
        )
        button.setActive(isFrameInterpolationEnabled)
        button.accessibilityValue = isFrameInterpolationEnabled
            ? "已开启"
            : "已关闭"
        button.addTarget(
            self,
            action: #selector(toggleFrameInterpolation),
            for: .touchUpInside
        )
        return button
    }()

    private lazy var galleryButton: RealtimeMediaActionButton = {
        let button = makeActionButton(
            title: "相册",
            systemName: "photo",
            accessibilityLabel: "从相册替换本地素材"
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
                title: "录制",
                image: makeSymbolImage(systemName: "record.circle")
            )
            recordingButton.setTintColor(.white)
            recordingButton.isEnabled = true
            recordingButton.accessibilityLabel = "开始录制生成视频"
            recordingButton.accessibilityValue = "未录制"
        case .preparing:
            recordingButton.setContent(
                title: "准备",
                image: makeSymbolImage(systemName: "hourglass")
            )
            recordingButton.setTintColor(.systemOrange)
            recordingButton.isEnabled = false
            recordingButton.accessibilityLabel = "正在准备视频录制"
            recordingButton.accessibilityValue = "正在准备"
        case .recording:
            recordingButton.setContent(
                title: "停止",
                image: makeSymbolImage(systemName: "stop.circle.fill")
            )
            recordingButton.setTintColor(.systemRed)
            recordingButton.isEnabled = true
            recordingButton.accessibilityLabel = "停止录制并保存视频"
            recordingButton.accessibilityValue = "正在录制"
        case .saving:
            recordingButton.setContent(
                title: "保存",
                image: makeSymbolImage(systemName: "hourglass")
            )
            recordingButton.setTintColor(.systemOrange)
            recordingButton.isEnabled = false
            recordingButton.accessibilityLabel = "正在保存录制视频"
            recordingButton.accessibilityValue = "正在保存"
        }
    }

    func setFrameInterpolationEnabled(_ enabled: Bool) {
        isFrameInterpolationEnabled = enabled
        frameInterpolationButton.setActive(enabled)
        frameInterpolationButton.accessibilityLabel = enabled
            ? "关闭插帧"
            : "开启插帧"
        frameInterpolationButton.accessibilityValue = enabled
            ? "已开启"
            : "已关闭"
    }

    private func renderMuteState() {
        muteButton.setContent(
            title: isMuted ? "静音" : "声音",
            image: makeSymbolImage(
                systemName: isMuted
                    ? "speaker.slash.fill"
                    : "speaker.wave.2.fill"
            )
        )
        muteButton.accessibilityLabel = isMuted ? "开启声音" : "关闭声音"
        muteButton.accessibilityValue = isMuted ? "已静音" : "已开启"
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
    private let localVolumeRow: RealtimeAudioVolumeSliderRow
    private let remoteVolumeRow: RealtimeAudioVolumeSliderRow

    init(localVolume: Float, remoteVolume: Float) {
        localVolumeRow = RealtimeAudioVolumeSliderRow(
            title: "本地音量",
            value: localVolume
        )
        remoteVolumeRow = RealtimeAudioVolumeSliderRow(
            title: "远端音量",
            value: remoteVolume
        )
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover
        preferredContentSize = CGSize(width: 260, height: 144)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 14
        view.clipsToBounds = true

        localVolumeRow.onValueChanged = { [weak self] value in
            self?.onLocalVolumeChanged?(value)
        }
        remoteVolumeRow.onValueChanged = { [weak self] value in
            self?.onRemoteVolumeChanged?(value)
        }

        let stackView = UIStackView(
            arrangedSubviews: [localVolumeRow, remoteVolumeRow]
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
