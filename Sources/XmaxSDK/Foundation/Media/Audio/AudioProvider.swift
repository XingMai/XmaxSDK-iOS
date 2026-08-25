import Foundation

/// 使用平台音频播放器播放本地 PCM 音频帧。
final class AudioProvider: AudioProviding, @unchecked Sendable {
    typealias PlaybackFactory = @Sendable () throws -> any AudioPlaybackControlling

    // 依赖
    private let playbackFactory: PlaybackFactory

    // 并发控制
    private let lock = NSLock()

    // 播放资源
    private var playbackController: (any AudioPlaybackControlling)?

    init(
        playbackFactory: @escaping PlaybackFactory = {
            try SystemAudioPlaybackController()
        }
    ) {
        self.playbackFactory = playbackFactory
    }

    deinit {
        playbackController?.stop()
    }

    func start() async throws {
        try lock.withLock {
            guard playbackController == nil else {
                return
            }

            do {
                let controller = try playbackFactory()
                try controller.start()
                playbackController = controller
            } catch let error as XmaxError {
                throw error
            } catch {
                throw XmaxError(
                    code: .mediaError,
                    message: (error as NSError).localizedDescription
                )
            }
        }
    }

    func write(frame: AudioFrame) {
        lock.withLock {
            guard let playbackController else {
                return
            }

            do {
                try playbackController.enqueue(frame.data)
            } catch {
                XmaxLogger.error(
                    "写入本地音频帧失败\n└─ 原因：\((error as NSError).localizedDescription)",
                    category: "Audio"
                )
            }
        }
    }

    func flush() async throws {
        try lock.withLock {
            guard let playbackController else {
                return
            }

            do {
                try playbackController.flush()
            } catch let error as XmaxError {
                throw error
            } catch {
                throw XmaxError(
                    code: .mediaError,
                    message: (error as NSError).localizedDescription
                )
            }
        }
    }

    func stop() async {
        lock.withLock {
            let controller = playbackController
            playbackController = nil
            controller?.stop()
        }
    }
}
