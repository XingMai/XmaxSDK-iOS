import Foundation

/// 管理生成任务期间的轨迹交互输入。
protocol InteractionControlling: Sendable {
    /// 开始接收当前生成任务的触控轨迹。
    ///
    /// - Parameters:
    ///   - taskID: 当前生成任务标识。
    ///   - videoFormat: 本地媒体输出规格。
    ///   - useDisplayedSize: 是否按实际显示的结果帧尺寸换算轨迹坐标。
    func startInteraction(
        taskID: String,
        videoFormat: RealtimeVideoFormat,
        useDisplayedSize: Bool
    ) async

    /// 停止接收轨迹并清理当前任务。
    func stopInteraction() async

    /// 提交触控轨迹。
    ///
    /// - Parameter frame: 当前视图中采集的轨迹及显示尺寸。
    func submitInteraction(_ frame: InteractionFrame) async
}

extension InteractionControlling {
    func startInteraction(taskID: String, videoFormat: RealtimeVideoFormat) async {
        await startInteraction(taskID: taskID, videoFormat: videoFormat, useDisplayedSize: false)
    }
}
