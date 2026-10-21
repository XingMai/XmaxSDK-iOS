import SwiftUI
import XmaxSDK

/// UIKit 与 SwiftUI 共用的统计展示数据；指标直接来自 SDK。
@MainActor
final class RealtimeStatisticsStore: ObservableObject {

    // 视频统计
    @Published var uplink: UplinkVideoStatistics?
    @Published var downlink: DownlinkVideoStatistics?
    @Published var networkQuality: RealtimeNetworkQuality?

    // 传输档位
    @Published private(set) var uplinkLevel: RealtimeQualityLevel?
    @Published private(set) var downlinkLevel: RealtimeQualityLevel?
    @Published private(set) var canAdjustQuality = false
    @Published private(set) var isAdjustingQuality = false
    @Published private(set) var qualityError: String?
    private var manager: (any XmaxRealtimeManaging)?
    private var refreshTask: Task<Void, Never>?
    private var adjustmentTask: Task<Void, Never>?

    func observe(_ manager: any XmaxRealtimeManaging) async {
        self.manager = manager
        await manager.setUplinkVideoStatisticsListener { [weak self] in
            self?.uplink = $0
        }
        await manager.setDownlinkVideoStatisticsListener { [weak self] in
            self?.downlink = $0
        }
        await manager.setNetworkQualityListener { [weak self] in
            self?.networkQuality = $0
            self?.refreshQualityLevels()
        }
        refreshQualityLevels()
    }

    func updateState(_ state: RealtimeState) {
        canAdjustQuality = state.connectionState == .generating
        if state.connectionState != .connected && state.connectionState != .generating {
            refreshTask?.cancel()
            uplinkLevel = nil
            downlinkLevel = nil
            qualityError = nil
        } else {
            refreshQualityLevels()
        }
    }

    func setQualityLevel(_ level: RealtimeQualityLevel, downlink: Bool) {
        guard canAdjustQuality, !isAdjustingQuality, let manager else { return }
        isAdjustingQuality = true
        qualityError = nil
        adjustmentTask = Task { [weak self] in
            do {
                if downlink {
                    try await manager.setDownlinkQualityLevel(level)
                } else {
                    try await manager.setUplinkQualityLevel(level)
                }
            } catch {
                if !Task.isCancelled, self?.canAdjustQuality == true {
                    self?.qualityError = error.localizedDescription
                }
            }
            guard !Task.isCancelled else { return }
            self?.isAdjustingQuality = false
            self?.refreshQualityLevels()
        }
    }

    private func refreshQualityLevels() {
        refreshTask?.cancel()
        guard let manager else { return }
        refreshTask = Task { [weak self] in
            let uplink = await manager.uplinkQualityLevel
            let downlink = await manager.downlinkQualityLevel
            guard !Task.isCancelled else { return }
            self?.uplinkLevel = uplink
            self?.downlinkLevel = downlink
        }
    }

    func clear() {
        refreshTask?.cancel()
        adjustmentTask?.cancel()
        manager = nil
        uplinkLevel = nil
        downlinkLevel = nil
        canAdjustQuality = false
        isAdjustingQuality = false
        qualityError = nil
        uplink = nil
        downlink = nil
        networkQuality = nil
    }
}

/// 实时上下行指标面板；高度不足时允许滚动查看。
struct RealtimeStatisticsPanel: View {

    // 统计数据
    @ObservedObject var statistics: RealtimeStatisticsStore
    @ObservedObject private var localization = XLLocalization.shared

    // 内容布局
    var onContentHeightChange: ((CGFloat) -> Void)? = nil
    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                heading("uplink")
                qualityButtons(downlink: false)
                row("resolution", resolution(statistics.uplink?.width, statistics.uplink?.height))
                row("captureFPS", value(statistics.uplink?.captureFrameRate, "fps"))
                row("encodeFPS", value(statistics.uplink?.encodeFrameRate, "fps"))
                row("sendFPS", value(statistics.uplink?.sendFrameRate, "fps"))
                row("bitrate", value(statistics.uplink?.bitrateKbps, "kbps"))
                row("loss", value(statistics.uplink?.packetLossPercent, "%"))
                row("quality", quality(statistics.networkQuality?.uplink))

                heading("downlink")
                    .padding(.top, 6)
                qualityButtons(downlink: true)
                row("resolution", resolution(statistics.downlink?.width, statistics.downlink?.height))
                row("decodeFPS", value(statistics.downlink?.decodeFrameRate, "fps"))
                row("renderFPS", value(statistics.downlink?.renderFrameRate, "fps"))
                row("bitrate", value(statistics.downlink?.bitrateKbps, "kbps"))
                row("loss", value(statistics.downlink?.packetLossPercent, "%"))
                row("quality", quality(statistics.networkQuality?.downlink))
                row("delay", value(statistics.downlink?.endToEndDelayMs, "ms"))
                Text(XLLocalization.text("statistics.level.hint"))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
                if let error = statistics.qualityError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
            .padding(10)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: StatisticsContentHeightKey.self,
                        value: geometry.size.height
                    )
                }
            }
        }
        .frame(maxHeight: contentHeight, alignment: .top)
        .background(Color.black.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onPreferenceChange(StatisticsContentHeightKey.self) { height in
            guard height > 0, contentHeight != height else { return }
            contentHeight = height
            onContentHeightChange?(height)
        }
    }

    private func qualityButtons(downlink: Bool) -> some View {
        let current = downlink ? statistics.downlinkLevel : statistics.uplinkLevel
        return HStack(spacing: 3) {
            ForEach(RealtimeQualityLevel.allCases, id: \.self) { level in
                Button {
                    statistics.setQualityLevel(level, downlink: downlink)
                } label: {
                    Text("L\(level.rawValue)")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .foregroundStyle(.white)
                        .background(current == level ? Color.blue : Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .disabled(!statistics.canAdjustQuality || statistics.isAdjustingQuality || current == level)
                .accessibilityLabel(XLLocalization.text(downlink ? "statistics.downlink" : "statistics.uplink") + " L\(level.rawValue)")
                .accessibilityAddTraits(current == level ? .isSelected : [])
            }
        }
        .opacity(statistics.canAdjustQuality && !statistics.isAdjustingQuality ? 1 : 0.5)
    }

    private func heading(_ key: String) -> some View {
        Text(XLLocalization.text("statistics." + key))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(minHeight: 15)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(XLLocalization.text("statistics." + key))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
            Text(value)
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(minHeight: 14)
    }

    private func resolution(_ width: Int?, _ height: Int?) -> String {
        guard let width, let height else { return "—" }
        return "\(width) × \(height)"
    }

    private func value(_ number: Int?, _ unit: String) -> String {
        number.map { "\($0) \(unit)" } ?? "—"
    }

    private func quality(_ quality: RealtimeNetworkQualityLevel?) -> String {
        guard let quality, quality != .unknown else { return "—" }
        return XLLocalization.text("statistics.quality." + quality.rawValue)
    }
}

private enum StatisticsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
