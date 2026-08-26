import Foundation

/// 管理生成任务期间的轨迹交互输入。
protocol InteractionControlling: Sendable {
    func startInteraction(
        taskID: String,
        videoFormat: RealtimeVideoFormat
    ) async

    func stopInteraction() async

    func submitInteraction(_ frame: InteractionFrame) async
}
