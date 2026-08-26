import Foundation

/// 定义媒体层向 Core 暴露的统一能力。
protocol MediaControlling: Actor {

    /// 当前活动的本地视频轨道。
    var currentTrack: RealtimeVideoTrack? { get }

    /// 当前本地视频格式。
    var currentVideoFormat: RealtimeVideoFormat? { get }

    /// 当前媒体来源是否包含由 SDK 管理的本地音频。
    var hasAudio: Bool { get }

    func createLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream

    func replaceLocalCameraStream(
        videoFormat: RealtimeVideoFormat,
        position: CameraPosition
    ) async throws -> RealtimeMediaStream

    func stopLocalCameraStream() async

    func switchCamera() async throws -> RealtimeMediaStream

    func createLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    func createLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    func createLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    func replaceLocalImageStream(
        imageData: Data,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    func replaceLocalImageStream(
        decodedImage: any DecodedImage,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    func replaceLocalImageStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    func stopLocalImageStream() async

    func createLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    func replaceLocalVideoStream(
        fileURL: URL,
        videoFormat: RealtimeVideoFormat?
    ) async throws -> RealtimeMediaStream

    func stopLocalVideoStream() async

    func restartForGeneration() async throws

    func owns(_ stream: RealtimeMediaStream) -> Bool
}
