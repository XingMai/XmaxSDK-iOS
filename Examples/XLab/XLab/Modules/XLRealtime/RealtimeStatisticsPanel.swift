import SwiftUI
import XmaxSDK

/// UIKit 与 SwiftUI 共用的统计展示数据；指标直接来自 SDK。
@MainActor
final class RealtimeStatisticsStore: ObservableObject {

    // 视频统计
    @Published var uplink: UplinkVideoStatistics?
    @Published var downlink: DownlinkVideoStatistics?
    @Published var networkQuality: RealtimeNetworkQuality?

    func observe(_ manager: any XmaxRealtimeManaging) async {
        await manager.setUplinkVideoStatisticsListener { [weak self] in
            self?.uplink = $0
        }
        await manager.setDownlinkVideoStatisticsListener { [weak self] in
            self?.downlink = $0
        }
        await manager.setNetworkQualityListener { [weak self] in
            self?.networkQuality = $0
        }
    }

    func clear() {
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                heading("uplink")
                row("resolution", resolution(statistics.uplink?.width, statistics.uplink?.height))
                row("captureFPS", value(statistics.uplink?.captureFrameRate, "fps"))
                row("encodeFPS", value(statistics.uplink?.encodeFrameRate, "fps"))
                row("sendFPS", value(statistics.uplink?.sendFrameRate, "fps"))
                row("bitrate", value(statistics.uplink?.bitrateKbps, "kbps"))
                row("loss", value(statistics.uplink?.packetLossPercent, "%"))
                row("quality", quality(statistics.networkQuality?.uplink))

                heading("downlink")
                    .padding(.top, 6)
                row("resolution", resolution(statistics.downlink?.width, statistics.downlink?.height))
                row("decodeFPS", value(statistics.downlink?.decodeFrameRate, "fps"))
                row("renderFPS", value(statistics.downlink?.renderFrameRate, "fps"))
                row("bitrate", value(statistics.downlink?.bitrateKbps, "kbps"))
                row("loss", value(statistics.downlink?.packetLossPercent, "%"))
                row("quality", quality(statistics.networkQuality?.downlink))
                row("delay", value(statistics.downlink?.endToEndDelayMs, "ms"))
            }
            .padding(10)
        }
        .background(Color.black.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
