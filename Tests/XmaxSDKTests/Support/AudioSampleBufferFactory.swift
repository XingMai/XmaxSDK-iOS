//
//  AudioSampleBufferFactory.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-iOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AVFoundation
import CoreMedia
import XCTest

enum AudioSampleBufferFactory {
    static func make(
        count: Int = 480,
        timestamp: CMTime = .zero,
        sampleRate: Double = 48000,
        channels: AVAudioChannelCount = 1,
        commonFormat: AVAudioCommonFormat = .pcmFormatInt16,
        interleaved: Bool = true,
        value: Int16 = 1000
    ) throws -> CMSampleBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: commonFormat,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: interleaved
        ))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
        pcm.frameLength = AVAudioFrameCount(count)
        for buffer in UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList) {
            let pointer = try XCTUnwrap(buffer.mData)
            if commonFormat == .pcmFormatInt16 {
                pointer.assumingMemoryBound(to: Int16.self).initialize(
                    repeating: value,
                    count: Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                )
            } else {
                pointer.assumingMemoryBound(to: Float.self).initialize(
                    repeating: 0.25,
                    count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                )
            }
        }

        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: format.streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &description
        ), noErr)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: try XCTUnwrap(description),
            sampleCount: count,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ), noErr)
        let result = try XCTUnwrap(sampleBuffer)
        XCTAssertEqual(CMSampleBufferSetDataBufferFromAudioBufferList(
            result,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcm.audioBufferList
        ), noErr)
        XCTAssertEqual(CMSampleBufferSetDataReady(result), noErr)
        return result
    }
}
