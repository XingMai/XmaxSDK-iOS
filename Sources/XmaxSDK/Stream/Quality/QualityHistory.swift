import Foundation

/// 按模型和传输方向保存一小时内成功提交的档位。
struct QualityHistory {
    let model: String
    var defaults: UserDefaults = .standard

    func read(downlink: Bool, now: TimeInterval = Date().timeIntervalSince1970) -> Int {
        let key = key(downlink)
        let savedAt = defaults.double(forKey: key + ".time")
        let level = defaults.integer(forKey: key)
        guard (1...5).contains(level), savedAt > 0, now >= savedAt, now - savedAt < 3600 else { return 2 }
        return level
    }

    func write(level: Int, downlink: Bool, now: TimeInterval = Date().timeIntervalSince1970) {
        defaults.set(level, forKey: key(downlink))
        defaults.set(now, forKey: key(downlink) + ".time")
    }

    private func key(_ downlink: Bool) -> String {
        "xmax.quality.agora.\(model).\(downlink ? "downlink" : "uplink")"
    }
}
