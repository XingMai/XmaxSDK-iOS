import Foundation

/// 定义本地图片流创建、帧输出和预览资源管理能力。
protocol ImageControlling: Sendable {

    /// 当前本地图片视频轨道；尚未创建或已停止时为空。
    var currentTrack: RealtimeVideoTrack? { get }

    /// 从已解码的图片创建媒体流并开始持续输出视频帧。
    ///
    /// - Parameters:
    ///   - decodedImage: 已完成方向处理和像素解码的图片。
    ///   - videoFormat: 期望的输出格式；为空时使用图片尺寸和模型默认帧率，尺寸按模型规则调整。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 已有活动图片流、格式无效、图片处理或帧输出启动失败时抛出错误。
    func createLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 从编码后的图片数据创建媒体流并开始持续输出视频帧。
    ///
    /// - Parameters:
    ///   - imageData: 非空的图片文件编码数据。
    ///   - videoFormat: 期望的输出格式；为空时使用图片尺寸和模型默认帧率，尺寸按模型规则调整。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 已有活动图片流、数据或格式无效、图片解码或帧输出启动失败时抛出错误。
    func createLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 从本地图片文件创建媒体流并开始持续输出视频帧。
    ///
    /// - Parameters:
    ///   - fileURL: 可读取的本地图片文件地址。
    ///   - videoFormat: 期望的输出格式；为空时使用图片尺寸和模型默认帧率，尺寸按模型规则调整。
    /// - Returns: 包含本地图片视频轨道的媒体流。
    /// - Throws: 已有活动图片流、文件读取、格式校验、图片解码或帧输出启动失败时抛出错误。
    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    /// 停止并等待图片帧输出任务结束，释放当前轨道及预览绑定；无活动流时不执行操作。
    func stopLocalImageStream() async
}
