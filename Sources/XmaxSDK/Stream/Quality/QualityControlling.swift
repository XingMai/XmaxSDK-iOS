/// 定义网络质量与设备性能告警的监听能力。
protocol QualityControlling: Sendable {
    /// 设置上行统计接收状态，并通知监听器清空旧统计。
    ///
    /// - Parameter enabled: 是否已经发布本地视频。
    func setUplinkVideoStatisticsEnabled(_ enabled: Bool)

    /// 设置下行统计目标用户，并通知监听器清空旧统计。
    ///
    /// - Parameter userID: 结果流用户标识；nil 表示停止接收。
    func setDownlinkVideoStatisticsUser(_ userID: String?)

    /// 设置视频上行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；未发布或断开连接时收到 nil；传入 nil 清除监听器。
    func setUplinkVideoStatisticsListener(_ listener: UplinkVideoStatisticsListener?)

    /// 设置视频下行统计监听器。
    ///
    /// - Parameter listener: 主线程回调；结果流清理时收到 nil；传入 nil 清除监听器。
    func setDownlinkVideoStatisticsListener(_ listener: DownlinkVideoStatisticsListener?)

    /// 设置网络质量监听器，传入空值时清除监听器。
    func setNetworkQualityListener(
        _ listener: RealtimeNetworkQualityListener?
    )

    /// 设置设备性能告警监听器，传入空值时清除监听器。
    func setPerformanceAlarmListener(
        _ listener: RealtimePerformanceAlarmListener?
    )
}
