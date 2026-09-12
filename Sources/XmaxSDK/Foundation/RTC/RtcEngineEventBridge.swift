import Foundation
@preconcurrency import VolcEngineRTC

/// 将火山 RTC Engine 回调转发给中性的 RTC 基础层。
final class RtcEngineEventBridge: NSObject, ByteRTCEngineDelegate {
    typealias SeiHandler = @Sendable (
        ByteRTCEngine,
        String,
        ByteRTCStreamInfo,
        Data
    ) -> Void
    typealias PerformanceAlarmHandler = @Sendable (
        ByteRTCEngine,
        ByteRTCStreamInfo,
        ByteRTCPerformanceAlarmReason,
        ByteRTCSourceWantedData
    ) -> Void

    // 事件回调
    private let onSei: SeiHandler
    private let onPerformanceAlarm: PerformanceAlarmHandler

    init(
        onSei: @escaping SeiHandler,
        onPerformanceAlarm: @escaping PerformanceAlarmHandler
    ) {
        self.onSei = onSei
        self.onPerformanceAlarm = onPerformanceAlarm
    }

    func rtcEngine(
        _ engine: ByteRTCEngine,
        onSEIMessageReceived streamId: String,
        info: ByteRTCStreamInfo,
        andMessage message: Data
    ) {
        onSei(engine, streamId, info, message)
    }

    func rtcEngine(
        _ engine: ByteRTCEngine,
        onPerformanceAlarms streamId: String,
        info: ByteRTCStreamInfo,
        mode: ByteRTCPerformanceAlarmMode,
        reason: ByteRTCPerformanceAlarmReason,
        sourceWantedData data: ByteRTCSourceWantedData
    ) {
        onPerformanceAlarm(engine, info, reason, data)
    }
}
