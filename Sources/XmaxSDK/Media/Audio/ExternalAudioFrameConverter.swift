//
//  ExternalAudioFrameConverter.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

@preconcurrency import AVFoundation
import CoreMedia
import Foundation

/// Converts a serialized external PCM stream into timestamped RTC audio packets.
final class ExternalAudioFrameConverter {

    /// The RTC input format.
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(AudioFrame.sampleRate),
        channels: AVAudioChannelCount(AudioFrame.channelCount),
        interleaved: true
    )!

    /// The PCM format fixed by the first accepted buffer.
    private var inputFormat: AVAudioFormat?

    /// The reusable sample-rate and channel converter, omitted for matching PCM.
    private var converter: AVAudioConverter?

    /// The first sample's timestamp in the current contiguous segment.
    private var anchor: CMTime?

    /// The expected start time of the next source buffer.
    private var nextInputTime: CMTime?

    /// The converted sample count in the current segment.
    private var outputSampleCount = 0

    /// The continuous PCM packetizer, retaining less than one packet between submissions.
    private var packetizer = PCMFramePacketizer()

    /// Creates a converter for one external source binding.
    init() {
    }

    /// Converts and packetizes a PCM buffer while preserving its presentation timeline.
    ///
    /// - Parameters:
    ///   - sampleBuffer: Ready PCM samples with a timestamp shared with video.
    ///   - handler: The synchronous receiver for 10 ms RTC packets.
    ///
    /// - Throws: An error if PCM data is invalid, the format changes, or conversion or delivery
    ///   fails. Invalid timestamps and overlapping buffers are ignored.
    func append(
        _ sampleBuffer: CMSampleBuffer,
        handler: MediaAudioFrameListener
    ) throws {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestampUs = CMTimeConvertScale(
            timestamp,
            timescale: 1000000,
            method: .roundTowardZero
        )
        guard timestamp.isNumeric, timestamp.epoch == 0, timestamp >= .zero,
            timestampUs.isNumeric, timestampUs.value >= 0
        else {
            return
        }

        let format = try resolveInputFormat(sampleBuffer)
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0, sampleCount <= Int(Int32.max),
            CMSampleBufferDataIsReady(sampleBuffer)
        else {
            throw Self.audioError("External audio requires ready PCM samples")
        }

        if let nextInputTime {
            let difference = CMTimeGetSeconds(
                CMTimeSubtract(
                    timestamp,
                    nextInputTime
                )
            )
            let tolerance = 0.5 / format.sampleRate
            if difference < -tolerance {
                return
            }
            if difference > tolerance {
                converter?.reset()
                packetizer = PCMFramePacketizer()
                outputSampleCount = 0
                anchor = timestamp
            }
        }
        if anchor == nil {
            anchor = timestamp
        }

        guard
            let input = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
            )
        else {
            throw Self.audioError("Could not allocate external audio input")
        }

        input.frameLength = AVAudioFrameCount(sampleCount)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(sampleCount),
            into: input.mutableAudioBufferList
        )
        guard status == noErr else {
            throw Self.audioError("Could not copy external PCM samples (\(status))")
        }

        if let converter {
            try convert(
                input,
                using: converter,
                handler: handler
            )
        } else {
            try emit(
                input,
                handler: handler
            )
        }

        nextInputTime = CMTimeAdd(
            timestamp,
            CMTimeMakeWithSeconds(
                Double(sampleCount) / format.sampleRate,
                preferredTimescale: 1000000000
            )
        )
    }
}

private extension ExternalAudioFrameConverter {

    /// Establishes the binding's PCM format and optional format converter.
    ///
    /// - Parameter sampleBuffer: The buffer defining the source PCM format.
    ///
    /// - Returns: The unchanged source format for this binding.
    ///
    /// - Throws: An error if the source is not valid linear PCM or its format changes.
    func resolveInputFormat(
        _ sampleBuffer: CMSampleBuffer
    ) throws -> AVAudioFormat {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
            CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio,
            let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description),
            stream.pointee.mFormatID == kAudioFormatLinearPCM,
            stream.pointee.mSampleRate.isFinite, stream.pointee.mSampleRate > 0,
            stream.pointee.mChannelsPerFrame > 0,
            let format = AVAudioFormat(streamDescription: stream)
        else {
            throw Self.audioError("External audio must contain linear PCM")
        }

        if let inputFormat {
            guard inputFormat == format else {
                throw Self.audioError("External PCM format cannot change during a binding")
            }
            return inputFormat
        }
        if format != outputFormat {
            guard
                let converter = AVAudioConverter(
                    from: format,
                    to: outputFormat
                )
            else {
                throw Self.audioError("External PCM format cannot be converted for RTC")
            }
            converter.primeMethod = .none
            self.converter = converter
        }

        inputFormat = format
        return format
    }

    /// Resamples PCM and drains available converted output without ending the stream.
    ///
    /// - Parameters:
    ///   - input: Owned PCM samples for this submission.
    ///   - converter: The converter retaining resampling state between submissions.
    ///   - handler: The synchronous RTC packet receiver.
    ///
    /// - Throws: An error if allocation, conversion, or packet delivery fails.
    func convert(
        _ input: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        handler: MediaAudioFrameListener
    ) throws {
        let capacity =
            ceil(
                Double(input.frameLength) * outputFormat.sampleRate / input.format.sampleRate
            ) + Double(AudioFrame.samplesPerFrame)
        guard capacity.isFinite, capacity <= Double(UInt32.max),
            let output = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(capacity)
            )
        else {
            throw Self.audioError("Could not allocate external audio output")
        }

        var suppliedInput = false
        while true {
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(
                to: output,
                error: &error
            ) { _, inputStatus in
                if suppliedInput {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                suppliedInput = true
                inputStatus.pointee = .haveData
                return input
            }
            guard status != .error, error == nil else {
                throw Self.audioError(
                    error?.localizedDescription ?? "External PCM conversion failed"
                )
            }

            try emit(
                output,
                handler: handler
            )
            guard status == .haveData else {
                return
            }
        }
    }

    /// Emits whole packets with timestamps derived from the segment's first sample.
    ///
    /// - Parameters:
    ///   - buffer: The converted 48 kHz mono PCM16 samples.
    ///   - handler: The synchronous RTC packet receiver.
    ///
    /// - Throws: An error from the packet receiver.
    func emit(
        _ buffer: AVAudioPCMBuffer,
        handler: MediaAudioFrameListener
    ) throws {
        guard buffer.frameLength > 0, let samples = buffer.int16ChannelData?.pointee,
            let anchor
        else {
            return
        }

        packetizer.append(
            Data(
                bytes: samples,
                count: Int(buffer.frameLength) * MemoryLayout<Int16>.size
            ),
            at: outputSampleCount
        )
        outputSampleCount += Int(buffer.frameLength)

        while let packet = packetizer.nextFrame() {
            let timestamp = CMTimeAdd(
                anchor,
                CMTime(
                    value: Int64(packet.sampleOffset),
                    timescale: CMTimeScale(AudioFrame.sampleRate)
                )
            )
            let timestampUs = CMTimeConvertScale(
                timestamp,
                timescale: 1000000,
                method: .roundTowardZero
            )

            try handler(
                AudioFrame(
                    data: packet.data,
                    timestampUs: timestampUs.value
                )
            )
        }
    }

    /// Creates an external PCM processing error.
    ///
    /// - Parameter message: The failure description.
    ///
    /// - Returns: A media error for the current source binding.
    static func audioError(
        _ message: String
    ) -> XmaxError {
        XmaxError(
            code: .mediaError,
            message: message
        )
    }
}
