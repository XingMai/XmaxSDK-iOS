import Foundation

typealias VideoPreviewResume = @Sendable () async -> Void

/// 缓存本地文件视频的最近一帧，并控制生成等待阶段的预览暂停。
final class LocalVideoPreviewController: @unchecked Sendable {

    // 并发控制
    private let lock = NSLock()

    // 预览资源
    private var latestSample: Sample?
    private weak var pausedTrack: RealtimeVideoTrack?

    // 运行状态
    private var pauseVersion: UInt64 = 0
    private var isVideoOutputPaused = false

    /// 原子地记录并输出视频帧，暂停期间忽略后续帧。
    func output(
        frame: VideoFrame,
        mediaTimeUs: Int64,
        frameListener: @Sendable (VideoFrame) throws -> Void
    ) throws {
        try lock.withLock {
            guard !isVideoOutputPaused else { return }
            try frameListener(frame)
            latestSample = Sample(
                frame: frame,
                mediaTimeUs: mediaTimeUs
            )
        }
    }

    /// 将指定轨道的预览暂停在最近一帧，并返回文件时间和恢复操作。
    func pause(
        track: RealtimeVideoTrack
    ) async -> (
        mediaTimeUs: Int64?,
        resume: VideoPreviewResume
    ) {
        let state = lock.withLock { () -> (Sample?, UInt64) in
            pauseVersion &+= 1
            isVideoOutputPaused = true
            pausedTrack = track
            return (latestSample, pauseVersion)
        }

        if let sample = state.0 {
            await setPreviewFrame(
                sample.frame,
                track: track,
                version: state.1
            )
        }

        return (
            state.0?.mediaTimeUs,
            { [weak self, weak track] in
                guard let self, let track else { return }
                await self.resume(track: track, version: state.1)
            }
        )
    }

    /// 检查点时间线重新建立后恢复底层视频帧输出，但继续保留静态覆盖。
    func resumeVideoOutput() {
        lock.withLock {
            isVideoOutputPaused = false
        }
    }

    /// 清理暂停覆盖和最近帧缓存。
    func reset() async {
        let state = lock.withLock { () -> (RealtimeVideoTrack?, UInt64) in
            let track = pausedTrack
            pausedTrack = nil
            latestSample = nil
            pauseVersion &+= 1
            isVideoOutputPaused = false
            return (track, pauseVersion)
        }
        guard let track = state.0 else { return }
        await MainActor.run {
            guard self.lock.withLock({
                self.pauseVersion == state.1 && self.pausedTrack == nil
            }) else {
                return
            }
            do {
                try VideoRenderRegistry.setPreviewFrame(nil, for: track)
            } catch {
                Self.logFailure(error)
            }
        }
    }
}

private extension LocalVideoPreviewController {
    struct Sample: Sendable {
        let frame: VideoFrame
        let mediaTimeUs: Int64
    }

    func setPreviewFrame(
        _ frame: VideoFrame,
        track: RealtimeVideoTrack,
        version: UInt64
    ) async {
        await MainActor.run {
            guard self.lock.withLock({
                self.pauseVersion == version && self.pausedTrack === track
            }) else {
                return
            }
            do {
                try VideoRenderRegistry.setPreviewFrame(frame, for: track)
            } catch {
                Self.logFailure(error)
            }
        }
    }

    func resume(
        track: RealtimeVideoTrack,
        version: UInt64
    ) async {
        let shouldResume = lock.withLock { () -> Bool in
            guard pauseVersion == version, pausedTrack === track else {
                return false
            }
            pausedTrack = nil
            isVideoOutputPaused = false
            return true
        }
        guard shouldResume else { return }
        await MainActor.run {
            guard self.lock.withLock({
                self.pauseVersion == version && self.pausedTrack == nil
            }) else {
                return
            }
            do {
                try VideoRenderRegistry.setPreviewFrame(nil, for: track)
            } catch {
                Self.logFailure(error)
            }
        }
    }

    static func logFailure(_ error: any Error) {
        XmaxLogger.error(
            "更新本地视频暂停预览失败\n└─ 原因：" +
                (error as NSError).localizedDescription,
            category: "Rendering"
        )
    }
}
