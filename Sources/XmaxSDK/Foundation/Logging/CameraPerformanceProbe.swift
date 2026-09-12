import Foundation

/// 临时摄像头性能采样；优化对比结束后移除本文件及调用点。
final class CameraPerformanceProbe: @unchecked Sendable {
    static let shared = CameraPerformanceProbe()

    // 临时对照开关；设为 false 后恢复完整管线，Release 构建始终关闭。
#if DEBUG
    static let captureOnlyEnabled = true
#else
    static let captureOnlyEnabled = false
#endif

    enum Stage: Hashable, Sendable {
        case capture
        case delivery
        case preparation
        case conversion
        case scheduling
        case rtcTotal
        case total
        case preview
    }

    struct Statistics: Sendable {
        var count = 0
        var totalMs = 0.0
        mutating func add(_ milliseconds: Double) {
            count += 1
            totalMs += milliseconds
        }
    }

    struct FrameTiming: Sendable {
        let capture: UInt64
        let callbackEntry: UInt64
        let conversionStart: UInt64
        let conversionEnd: UInt64

        func sample(previewStart: UInt64, previewEnd: UInt64) -> PreviewSample? {
            guard capture <= callbackEntry, callbackEntry <= conversionStart,
                  conversionStart <= conversionEnd,
                  conversionEnd <= previewStart, previewStart <= previewEnd else { return nil }
            return PreviewSample(
                delivery: Double(callbackEntry - capture) / 1000000,
                preparation: Double(conversionStart - callbackEntry) / 1000000,
                conversion: Double(conversionEnd - conversionStart) / 1000000,
                scheduling: Double(previewStart - conversionEnd) / 1000000,
                preview: Double(previewEnd - previewStart) / 1000000
            )
        }
    }

    struct PreviewSample: Sendable {
        let delivery: Double
        let preparation: Double
        let conversion: Double
        let scheduling: Double
        let preview: Double

        var total: Double { delivery + preparation + conversion + scheduling + preview }
    }

    private struct Window: Sendable {
        let sessionStart: UInt64
        var start: UInt64
        let description: String
        let fps: Int
        var stages: [Stage: Statistics] = [:]
        var drops: [String: Int] = [:]
        var previewReplaced = 0

        func message() -> String {
            var lines = [
                CameraPerformanceProbe.captureOnlyEnabled
                    ? "摄像头最小采集对照 [TEMP] (Camera Capture-Only Baseline)"
                    : "摄像头平均耗时 [TEMP] (Camera Average Timing)",
                "├─ 配置 (Configuration)：\(description)，\(fps) fps"
            ]
            let metrics: [(Stage, String)] = CameraPerformanceProbe.captureOnlyEnabled ? [
                (.delivery, "采集→回调入口 (Capture-to-Callback Delivery)"),
                (.capture, "最小回调处理 (Minimal Callback Processing)")
            ] : [
                (.total, "平均总耗时：采集→预览提交 (Average Capture-to-Preview Latency)"),
                (.delivery, "采集→回调入口 (Capture-to-Callback Delivery)"),
                (.preparation, "回调入口→转换开始 (Callback Preparation)"),
                (.conversion, "裁剪缩放 (Crop and Scale)"),
                (.scheduling, "转换完成→预览处理开始 (Conversion-to-Preview Wait)"),
                (.preview, "预览准备与提交 (Preview Preparation and Submit)"),
                (.rtcTotal, "RTC 准备与推送，不计入上述分段 (RTC Preparation and Push, Separate Measurement)")
            ]
            for (index, metric) in metrics.enumerated() {
                let value = stages[metric.0].map {
                    String(format: "%.2f ms", $0.totalMs / Double($0.count))
                } ?? "无采样 (No Samples)"
                lines.append("\(index == metrics.count - 1 ? "└─" : "├─") \(metric.1)：\(value)")
            }
            if !drops.isEmpty || previewReplaced > 0 {
                lines.append("丢帧 (Dropped Frames)：采集 (Capture)=\(drops.values.reduce(0, +))，预览合并 (Preview Replaced)=\(previewReplaced)")
            }
            return lines.joined(separator: "\n")
        }
    }

    // 并发控制
    private let lock = NSLock()
    private let loggingQueue = DispatchQueue(label: "ai.xmax.sdk.camera.performance", qos: .utility)

    // 当前采集窗口
    private var window: Window?

    // 待预览帧的时间点，不持有像素数据
    private var pendingFrames: [Int64: FrameTiming] = [:]

    func start(description: String, fps: Int) {
        stop()
        guard XmaxLogger.isEnabled(.performance), fps > 0 else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
            window = Window(sessionStart: now, start: now, description: description, fps: fps)
        }
        if Self.captureOnlyEnabled {
            XmaxLogger.media.warn(
                message: "最小采集对照已开启：不缩放、不预览、不推送视频帧，请勿开始生成 " +
                    "(Capture-only baseline enabled: no scaling, preview or video push; do not start generation)",
                option: .performance
            )
        }
    }

    func begin(frameTimestampUs: Int64? = nil) -> UInt64? {
        lock.withLock {
            guard let window else { return nil }
            if let frameTimestampUs, frameTimestampUs < Int64(window.sessionStart / 1000) {
                return nil
            }
            return DispatchTime.now().uptimeNanoseconds
        }
    }

    func finish(_ stage: Stage, since start: UInt64?) {
        guard let start else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        record(stage, milliseconds: Double(now - start) / 1000000, measuredAt: start, now: now)
    }

    static func deliveryMilliseconds(timestampUs: Int64, callbackEntry: UInt64) -> Double? {
        guard timestampUs >= 0, UInt64(timestampUs) <= UInt64.max / 1000 else { return nil }
        let capture = UInt64(timestampUs) * 1000
        guard capture <= callbackEntry else { return nil }
        return Double(callbackEntry - capture) / 1000000
    }

    func captureOnlyFrame(timestampUs: Int64, callbackEntry: UInt64, samplingStart: UInt64?) {
        guard let samplingStart,
              let milliseconds = Self.deliveryMilliseconds(timestampUs: timestampUs, callbackEntry: callbackEntry) else { return }
        record(.delivery, milliseconds: milliseconds, measuredAt: samplingStart, now: DispatchTime.now().uptimeNanoseconds)
    }

    func convertedFrame(timestampUs: Int64, callbackEntry: UInt64, since start: UInt64?) {
        guard let start, timestampUs >= 0,
              UInt64(timestampUs) <= UInt64.max / 1000 else { return }
        let end = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
            guard let sessionStart = window?.sessionStart,
                  start >= sessionStart, UInt64(timestampUs) * 1000 >= sessionStart else { return }
            // 未绑定预览时也限制临时时间点的存储数量。
            if pendingFrames.count >= 256 { pendingFrames.removeAll(keepingCapacity: true) }
            pendingFrames[timestampUs] = FrameTiming(
                capture: UInt64(timestampUs) * 1000,
                callbackEntry: callbackEntry,
                conversionStart: start,
                conversionEnd: end
            )
        }
    }

    func finishPreview(timestampUs: Int64, since start: UInt64?) {
        guard let start else { return }
        let end = DispatchTime.now().uptimeNanoseconds
        lock.withLock {
            guard window != nil,
                  let timing = pendingFrames.removeValue(forKey: timestampUs),
                  let sample = timing.sample(previewStart: start, previewEnd: end) else { return }
            window?.stages[.total, default: Statistics()].add(sample.total)
            window?.stages[.delivery, default: Statistics()].add(sample.delivery)
            window?.stages[.preparation, default: Statistics()].add(sample.preparation)
            window?.stages[.conversion, default: Statistics()].add(sample.conversion)
            window?.stages[.scheduling, default: Statistics()].add(sample.scheduling)
            window?.stages[.preview, default: Statistics()].add(sample.preview)
        }
    }

    func dropped(reason: String) {
        lock.withLock { window?.drops[reason, default: 0] += 1 }
    }

    func replacedPreview(timestampUs: Int64) {
        lock.withLock {
            guard let current = window, timestampUs >= Int64(current.sessionStart / 1000) else { return }
            pendingFrames.removeValue(forKey: timestampUs)
            window?.previewReplaced += 1
        }
    }

    func stop() {
        let snapshot = lock.withLock {
            let snapshot = window
            window = nil
            pendingFrames.removeAll(keepingCapacity: true)
            return snapshot
        }
        if let snapshot { emit(snapshot) }
    }

    private func record(_ stage: Stage, milliseconds: Double, measuredAt: UInt64, now: UInt64) {
        let snapshot: Window? = lock.withLock {
            guard let sessionStart = window?.sessionStart,
                  let fps = window?.fps,
                  let windowStart = window?.start,
                  measuredAt >= sessionStart else { return nil }
            window?.stages[stage, default: Statistics()].add(milliseconds)
            guard stage == .capture, now - windowStart >= 5000000000 else { return nil }
            guard let snapshot = window else { return nil }
            window = Window(sessionStart: sessionStart, start: now, description: snapshot.description, fps: fps)
            return snapshot
        }
        if let snapshot { emit(snapshot) }
    }

    private func emit(_ snapshot: Window) {
        guard !snapshot.stages.isEmpty || !snapshot.drops.isEmpty else { return }
        loggingQueue.async {
            XmaxLogger.media.info(message: snapshot.message(), option: .performance)
        }
    }
}
