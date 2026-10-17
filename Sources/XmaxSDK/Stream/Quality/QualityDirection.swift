import Foundation

/// 单个传输方向的网络采样与升降档规则。
struct QualityDirection: Sendable {
    let baseline: RealtimeVideoFormat
    let downlink: Bool
    private(set) var level: Int

    // 采样窗口
    private var goodSamples = 0
    private var poorSamples = 0
    private var lastSample: TimeInterval?
    private var stableUntil: TimeInterval = 0
    private var upgradeAfter: TimeInterval = 0
    private var probeUntil: TimeInterval = 0

    init(baseline: RealtimeVideoFormat, level: Int, downlink: Bool) {
        self.baseline = baseline
        self.downlink = downlink
        self.level = min(5, max(1, level))
        while self.level > 1, !supports(self.level) { self.level -= 1 }
    }

    var format: RealtimeVideoFormat { format(at: level) }

    func format(at level: Int) -> RealtimeVideoFormat {
        QualityVideoFormat.resolve(baseline, level: level, downlink: downlink)
    }

    mutating func resetSamples() {
        goodSamples = 0
        poorSamples = 0
        lastSample = nil
    }

    mutating func observe(_ quality: RealtimeNetworkQualityLevel, sampledAt: TimeInterval, now: TimeInterval) -> Int? {
        guard sampledAt <= now, lastSample.map({ sampledAt > $0 }) ?? true else { return nil }
        if let lastSample, sampledAt - lastSample > 5 { resetSamples() }
        lastSample = sampledAt
        guard now - sampledAt <= 5, now >= stableUntil else {
            goodSamples = 0
            poorSamples = 0
            return nil
        }

        let step: Int
        switch quality {
        case .bad, .veryBad:
            goodSamples = 0
            poorSamples += 1
            guard poorSamples >= 3 else { return nil }
            step = 1
        case .excellent, .good:
            poorSamples = 0
            goodSamples += 1
            guard goodSamples >= 5, now >= upgradeAfter else { return nil }
            step = -1
        default:
            goodSamples = 0
            poorSamples = 0
            return nil
        }

        var candidate = level + step
        while (1...5).contains(candidate) {
            if format(at: candidate) != format, supports(candidate) { return candidate }
            candidate += step
        }
        return nil
    }

    mutating func complete(level next: Int, success: Bool, now: TimeInterval) {
        resetSamples()
        stableUntil = now + 4
        guard success else { return }
        if next < level {
            probeUntil = now + 20
        } else if next > level {
            if now < probeUntil { upgradeAfter = now + 60 }
            probeUntil = 0
        }
        level = next
    }

    func supports(_ level: Int) -> Bool {
        downlink || (try? EncodingBitratePolicy.resolve(format(at: level))) != nil
    }
}

