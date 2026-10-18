//
//  QualityHistory.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 按模型和传输方向保存一小时内成功提交的档位。
struct QualityHistory {

    /// 模型隔离
    let model: String

    /// 持久化存储
    var defaults: UserDefaults = .standard

    /// 读取当前模型指定方向最近一小时内的有效档位。
    ///
    /// - Parameters:
    ///   - downlink: 是否读取下行档位；`false` 表示上行。
    ///   - now: 当前 Unix 时间，单位为秒。
    /// - Returns: 有效历史档位；历史缺失、过期或时间无效时返回默认档位 2。
    func read(downlink: Bool, now: TimeInterval = Date().timeIntervalSince1970) -> Int {
        let key = key(downlink)
        let savedAt = defaults.double(forKey: key + ".time")
        let level = defaults.integer(forKey: key)
        guard (1...5).contains(level), savedAt > 0, now >= savedAt, now - savedAt < 3600 else { return 2 }
        return level
    }

    /// 保存当前模型指定方向成功应用的档位。
    ///
    /// - Parameters:
    ///   - level: 成功应用的档位，范围为 `1...5`。
    ///   - downlink: 是否保存下行档位；`false` 表示上行。
    ///   - now: 当前 Unix 时间，单位为秒。
    func write(level: Int, downlink: Bool, now: TimeInterval = Date().timeIntervalSince1970) {
        defaults.set(level, forKey: key(downlink))
        defaults.set(now, forKey: key(downlink) + ".time")
    }

    /// 生成按模型和传输方向隔离的历史存储键。
    ///
    /// - Parameter downlink: 是否为下行方向。
    /// - Returns: 当前模型和方向对应的存储键。
    private func key(_ downlink: Bool) -> String {
        "xmax.quality.agora.\(model).\(downlink ? "downlink" : "uplink")"
    }
}
