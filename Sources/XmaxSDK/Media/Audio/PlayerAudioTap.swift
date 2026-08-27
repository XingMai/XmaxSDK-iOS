@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import MediaToolbox

/// 从 AVPlayer 音频渲染链路复制 PCM，并转换为 RTC 使用的固定音频帧。
final class PlayerAudioTap: @unchecked Sendable {

    // 音频输出参数
    private static let bytesPerFrame = AudioFrame.samplesPerFrame
        * MemoryLayout<Int16>.size
    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(AudioFrame.sampleRate),
        channels: AVAudioChannelCount(AudioFrame.channelCount),
        interleaved: true
    )!

    // 帧监听
    private let frameListener: MediaAudioFrameListener
    private let errorListener: XmaxErrorListener

    // 平台资源
    private var storedProcessingTap: MTAudioProcessingTap?
    private let processingQueue = DispatchQueue(
        label: "ai.xmax.sdk.player-audio-tap",
        qos: .userInteractive
    )

    // 并发控制
    private let stateLock = NSLock()

    // 音频格式
    private var sourceDescription: AudioStreamBasicDescription?

    // 运行状态
    private var resetVersion: UInt64 = 0
    private var pendingData = Data()

    init(
        frameListener: @escaping MediaAudioFrameListener,
        errorListener: @escaping XmaxErrorListener
    ) throws {
        self.frameListener = frameListener
        self.errorListener = errorListener

        let clientInfo = Unmanaged.passRetained(self).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: PlayerAudioTap.initialize,
            finalize: PlayerAudioTap.finalize,
            prepare: PlayerAudioTap.prepare,
            unprepare: PlayerAudioTap.unprepare,
            process: PlayerAudioTap.process
        )

        var processingTap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &processingTap
        )
        guard status == noErr, let processingTap else {
            Unmanaged<PlayerAudioTap>
                .fromOpaque(clientInfo)
                .release()
            throw XmaxError(
                code: .mediaError,
                message: "Failed to create player audio tap: \(status)"
            )
        }
        storedProcessingTap = processingTap
    }

    /// 清空 seek 或循环播放前积累的非完整音频帧。
    func reset() {
        stateLock.withLock {
            resetVersion &+= 1
        }
        processingQueue.async { [weak self] in
            self?.pendingData.removeAll(keepingCapacity: true)
        }
    }

    /// 将 Tap 所有权交给 AVAudioMix，避免处理器与 Tap 形成保留环。
    func takeProcessingTap() -> MTAudioProcessingTap {
        let processingTap = storedProcessingTap!
        storedProcessingTap = nil
        return processingTap
    }
}

private extension PlayerAudioTap {
    struct AudioBufferCopy: @unchecked Sendable {
        let channelCount: UInt32
        let data: Data
    }

    struct AudioSample: @unchecked Sendable {
        let format: AudioStreamBasicDescription
        let frameCount: AVAudioFrameCount
        let buffers: [AudioBufferCopy]
        let resetVersion: UInt64
        let startsStream: Bool
    }

    static let initialize: MTAudioProcessingTapInitCallback = {
        _, clientInfo, storageOut in
        storageOut.pointee = clientInfo
    }

    static let finalize: MTAudioProcessingTapFinalizeCallback = { tap in
        let storage = MTAudioProcessingTapGetStorage(tap)
        Unmanaged<PlayerAudioTap>.fromOpaque(storage).release()
    }

    static let prepare: MTAudioProcessingTapPrepareCallback = {
        tap, _, processingFormat in
        let processor = processor(for: tap)
        processor.stateLock.withLock {
            processor.sourceDescription = processingFormat.pointee
            processor.resetVersion &+= 1
        }
        processor.processingQueue.async { [weak processor] in
            processor?.pendingData.removeAll(keepingCapacity: true)
        }
    }

    static let unprepare: MTAudioProcessingTapUnprepareCallback = { tap in
        let processor = processor(for: tap)
        processor.stateLock.withLock {
            processor.sourceDescription = nil
            processor.resetVersion &+= 1
        }
    }

    static let process: MTAudioProcessingTapProcessCallback = {
        tap,
        numberFrames,
        _,
        bufferListInOut,
        numberFramesOut,
        flagsOut in
        var sourceFlags = MTAudioProcessingTapFlags()
        var sourceTimeRange = CMTimeRange.invalid
        var sourceFrameCount = CMItemCount()
        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            numberFrames,
            bufferListInOut,
            &sourceFlags,
            &sourceTimeRange,
            &sourceFrameCount
        )
        guard status == noErr else {
            numberFramesOut.pointee = 0
            flagsOut.pointee = sourceFlags
            return
        }

        numberFramesOut.pointee = sourceFrameCount
        flagsOut.pointee = sourceFlags
        guard sourceFrameCount > 0,
              sourceFrameCount <= CMItemCount(AVAudioFrameCount.max) else {
            return
        }
        processor(for: tap).capture(
            bufferList: bufferListInOut,
            frameCount: AVAudioFrameCount(sourceFrameCount),
            startsStream: sourceFlags &
                MTAudioProcessingTapFlags(kMTAudioProcessingTapFlag_StartOfStream)
                != 0
        )
    }

    static func processor(
        for tap: MTAudioProcessingTap
    ) -> PlayerAudioTap {
        Unmanaged<PlayerAudioTap>.fromOpaque(
            MTAudioProcessingTapGetStorage(tap)
        ).takeUnretainedValue()
    }

    func capture(
        bufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: AVAudioFrameCount,
        startsStream: Bool
    ) {
        let state = stateLock.withLock {
            (sourceDescription, resetVersion)
        }
        guard let format = state.0 else {
            return
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList).map {
            buffer -> AudioBufferCopy in
            let byteCount = Int(buffer.mDataByteSize)
            let data = buffer.mData.map {
                Data(bytes: $0, count: byteCount)
            } ?? Data()
            return AudioBufferCopy(
                channelCount: buffer.mNumberChannels,
                data: data
            )
        }
        let sample = AudioSample(
            format: format,
            frameCount: frameCount,
            buffers: buffers,
            resetVersion: state.1,
            startsStream: startsStream
        )
        processingQueue.async { [weak self] in
            self?.process(sample)
        }
    }

    func process(_ sample: AudioSample) {
        let currentVersion = stateLock.withLock { resetVersion }
        guard currentVersion == sample.resetVersion else {
            return
        }
        if sample.startsStream {
            pendingData.removeAll(keepingCapacity: true)
        }

        do {
            let data = try convert(sample)
            pendingData.append(data)
            emitFrames()
        } catch {
            errorListener(XmaxError.from(error))
        }
    }

    func convert(_ sample: AudioSample) throws -> Data {
        var sourceDescription = sample.format
        guard let sourceFormat = AVAudioFormat(
            streamDescription: &sourceDescription
        ),
              let sourceBuffer = AVAudioPCMBuffer(
                  pcmFormat: sourceFormat,
                  frameCapacity: sample.frameCount
              ) else {
            throw Self.mediaError("Player audio format is unsupported")
        }
        sourceBuffer.frameLength = sample.frameCount

        let targetBuffers = UnsafeMutableAudioBufferListPointer(
            sourceBuffer.mutableAudioBufferList
        )
        guard targetBuffers.count == sample.buffers.count else {
            throw Self.mediaError("Player audio buffer layout is invalid")
        }
        for index in targetBuffers.indices {
            let source = sample.buffers[index]
            let byteCount = source.data.count
            guard byteCount <= Int(targetBuffers[index].mDataByteSize),
                  let destination = targetBuffers[index].mData else {
                throw Self.mediaError("Player audio buffer is invalid")
            }
            source.data.copyBytes(
                to: destination.assumingMemoryBound(to: UInt8.self),
                count: byteCount
            )
            targetBuffers[index].mDataByteSize = UInt32(byteCount)
            targetBuffers[index].mNumberChannels = source.channelCount
        }

        guard let converter = AVAudioConverter(
            from: sourceFormat,
            to: Self.targetFormat
        ) else {
            throw Self.mediaError("Failed to create player audio converter")
        }
        let ratio = Self.targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = max(
            AVAudioFrameCount(ceil(Double(sample.frameCount) * ratio)) + 32,
            1
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.targetFormat,
            frameCapacity: capacity
        ) else {
            throw Self.mediaError("Failed to allocate converted audio buffer")
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return sourceBuffer
        }
        guard status != .error, conversionError == nil else {
            throw Self.mediaError(
                conversionError?.localizedDescription
                    ?? "Player audio conversion failed"
            )
        }

        let outputList = UnsafeMutableAudioBufferListPointer(
            outputBuffer.mutableAudioBufferList
        )
        guard let output = outputList.first,
              let bytes = output.mData else {
            return Data()
        }
        return Data(bytes: bytes, count: Int(output.mDataByteSize))
    }

    func emitFrames() {
        while pendingData.count >= Self.bytesPerFrame {
            let data = Data(pendingData.prefix(Self.bytesPerFrame))
            pendingData.removeFirst(Self.bytesPerFrame)
            do {
                try frameListener(AudioFrame(
                    data: data,
                    timestampUs: Int64(
                        DispatchTime.now().uptimeNanoseconds / 1_000
                    )
                ))
            } catch {
                errorListener(XmaxError.from(error))
            }
        }
    }

    static func mediaError(_ message: String) -> XmaxError {
        XmaxError(code: .mediaError, message: message)
    }
}
