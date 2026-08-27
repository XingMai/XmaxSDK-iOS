/// 定义网络质量与设备性能告警的监听能力。
protocol QualityControlling: Sendable {
    /// 设置网络质量监听器，传入空值时清除监听器。
    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    )

    /// 设置设备性能告警监听器，传入空值时清除监听器。
    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    )
}
