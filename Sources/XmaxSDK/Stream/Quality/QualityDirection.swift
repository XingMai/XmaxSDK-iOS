//
//  QualityDirection.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 单个传输方向的网络采样与升降档规则。
struct QualityDirection: Sendable {

    // 媒体基准
    let baseline: RealtimeVideoFormat
    let downlink: Bool

    // 当前档位
    private(set) var level: Int

    // 采样窗口
    private var goodSamples = 0
    private var poorSamples = 0
    private var lastSample: TimeInterval?
    private var stableUntil: TimeInterval = 0
    private var upgradeAfter: TimeInterval = 0
    private var probeUntil: TimeInterval = 0

    /// 创建单个方向的质量策略，并解析可用的初始档位。
    ///
    /// - Parameters:
    ///   - baseline: 不会随调档变化的媒体原始规格。
    ///   - level: 初始档位，超出范围时限制到 `1...5`。
    ///   - downlink: 是否为下行方向。
    init(baseline: RealtimeVideoFormat, level: Int, downlink: Bool) {
        self.baseline = baseline
        self.downlink = downlink
        self.level = min(5, max(1, level))
        while self.level > 1, !supports(self.level) { self.level -= 1 }
    }

    // 当前传输规格
    var format: RealtimeVideoFormat { format(at: level) }

    /// 计算指定档位对应的传输规格。
    ///
    /// - Parameter level: 目标传输档位。
    /// - Returns: 由当前媒体基准和方向解析的规格。
    func format(at level: Int) -> RealtimeVideoFormat {
        QualityVideoFormat.resolve(baseline, level: level, downlink: downlink)
    }

    /// 清空连续好坏网络采样及最后采样时间。
    mutating func resetSamples() {
        goodSamples = 0
        poorSamples = 0
        lastSample = nil
    }

    /// 根据有效连续采样和冷却条件提出升降档候选。
    ///
    /// - Parameters:
    ///   - quality: 当前网络质量等级。
    ///   - sampledAt: 该质量样本的单调时钟时间，单位为秒。
    ///   - now: 当前单调时钟时间，单位为秒。
    /// - Returns: 可执行的候选档位；无需调整时返回 `nil`。
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

    /// 记录调档结果，并更新稳定窗口及升档冷却期。
    ///
    /// - Parameters:
    ///   - next: 本次尝试的目标档位。
    ///   - success: 该档位是否成功应用。
    ///   - now: 当前单调时钟时间，单位为秒。
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

    /// 判断指定档位是否满足当前方向的编码预算。
    ///
    /// - Parameter level: 需要校验的档位。
    /// - Returns: 下行或上行码率预算可成功解析时返回 `true`。
    func supports(_ level: Int) -> Bool {
        downlink || (try? EncodingBitratePolicy.resolve(format(at: level))) != nil
    }
}

