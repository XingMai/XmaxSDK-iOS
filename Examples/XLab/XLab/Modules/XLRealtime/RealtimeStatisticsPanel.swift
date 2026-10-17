import SwiftUI
@_spi(QualityDebug) import XmaxSDK

/// UIKit 与 SwiftUI 共用的统计展示数据；指标直接来自 SDK。
@MainActor
final class RealtimeStatisticsStore: ObservableObject {

    // 视频统计
    @Published var uplink: UplinkVideoStatistics?
    @Published var downlink: DownlinkVideoStatistics?
    @Published var networkQuality: RealtimeNetworkQuality?
    @Published var adaptiveQuality: RealtimeQualityDebugState?
    @Published var isSelectingQuality = false

    // 调试入口
    private weak var qualityManager: (any RealtimeQualityDebugging)?

    func observe(_ manager: any XmaxRealtimeManaging) async {
        qualityManager = manager as? any RealtimeQualityDebugging
        await manager.setUplinkVideoStatisticsListener { [weak self] in
            self?.uplink = $0
            self?.refreshQuality()
        }
        await manager.setDownlinkVideoStatisticsListener { [weak self] in
            self?.downlink = $0
            self?.refreshQuality()
        }
        await manager.setNetworkQualityListener { [weak self] in
            self?.networkQuality = $0
        }
    }

    func clear() {
        uplink = nil
        downlink = nil
        networkQuality = nil
        adaptiveQuality = nil
        qualityManager = nil
    }

    func selectQuality(_ level: Int, downlink: Bool) {
        guard !isSelectingQuality, let qualityManager else { return }
        isSelectingQuality = true
        Task { [weak self] in
            defer { self?.isSelectingQuality = false }
            do {
                try await qualityManager.selectQualityLevel(level, downlink: downlink)
            } catch {
                print("[XLab] Quality selection failed: \(error.localizedDescription)")
            }
            self?.refreshQuality()
        }
    }

    private func refreshQuality() {
        guard let qualityManager else { return }
        Task { [weak self] in
            let state = await qualityManager.qualityDebugState
            guard self?.qualityManager === qualityManager else { return }
            self?.adaptiveQuality = state
        }
    }
}

/// 实时上下行指标面板；高度不足时允许滚动查看。
struct RealtimeStatisticsPanel: View {

    // 统计数据
    @ObservedObject var statistics: RealtimeStatisticsStore
    @ObservedObject private var localization = XLLocalization.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                qualityControls
                Divider().background(Color.white.opacity(0.2))

                heading("uplink")
                row("resolution", resolution(statistics.uplink?.width, statistics.uplink?.height))
                row("sendBitrate", value(statistics.uplink?.bitrateKbps, "kbps"))
                row("captureFPS", value(statistics.uplink?.captureFrameRate, "fps"))
                row("encodeFPS", value(statistics.uplink?.encodeFrameRate, "fps"))
                row("sendFPS", value(statistics.uplink?.sendFrameRate, "fps"))
                row("loss", value(statistics.uplink?.packetLossPercent, "%"))

                Divider().background(Color.white.opacity(0.2))
                heading("downlink")
                row("resolution", resolution(statistics.downlink?.width, statistics.downlink?.height))
                row("receiveBitrate", value(statistics.downlink?.bitrateKbps, "kbps"))
                row("decodeFPS", value(statistics.downlink?.decodeFrameRate, "fps"))
                row("renderFPS", value(statistics.downlink?.renderFrameRate, "fps"))
                row("loss", value(statistics.downlink?.packetLossPercent, "%"))
                row("delay", value(statistics.downlink?.endToEndDelayMs, "ms"))
                Text(XLLocalization.text("statistics.note"))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))

                Divider().background(Color.white.opacity(0.2))
                heading("quality")
                row("uplink", quality(statistics.networkQuality?.uplink))
                row("downlink", quality(statistics.networkQuality?.downlink))
            }
            .padding(10)
        }
        .background(Color.black.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var qualityControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("qualityDebug")
            qualityMenu(downlink: false)
            row("requested", format(statistics.adaptiveQuality?.uplink))
            qualityMenu(downlink: true)
            row("requested", format(statistics.adaptiveQuality?.downlink))
            row("interpolation", statistics.adaptiveQuality.map {
                XLLocalization.text($0.interpolationEnabled ? "common.enabled" : "common.disabled")
            } ?? "—")
        }
    }

    private func heading(_ key: String) -> some View {
        Text(XLLocalization.text("statistics." + key))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
    }

    private func qualityMenu(downlink: Bool) -> some View {
        Menu {
            ForEach(1...5, id: \.self) { level in
                Button("L\(level)") { statistics.selectQuality(level, downlink: downlink) }
            }
        } label: {
            row(downlink ? "downlinkTier" : "uplinkTier", statistics.adaptiveQuality.map {
                "L\(downlink ? $0.downlinkLevel : $0.uplinkLevel) ▾"
            } ?? "—")
        }
        .disabled(statistics.adaptiveQuality == nil || statistics.isSelectingQuality)
    }

    private func format(_ format: RealtimeVideoFormat?) -> String {
        guard let format else { return "—" }
        return "\(format.width) × \(format.height)"
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
