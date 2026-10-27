import Foundation
import CoreMedia
import AVFoundation

public enum MockAudioGenerator {
    /// Generates a valid CMSampleBuffer containing PCM audio (e.g. sine wave)
    public static func makeAudioSampleBuffer(
        frameCount: Int = 1024,
        sampleRate: Double = 48000.0,
        channels: Int = 2,
        frequency: Double = 440.0,
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * MemoryLayout<Float>.size),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: UInt32(MemoryLayout<Float>.size * 8),
            mReserved: 0
        )

        var formatDesc: CMAudioFormatDescription?
        let descStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDesc
        )
        guard descStatus == noErr, let formatDesc = formatDesc else { return nil }

        let sampleCount = frameCount * channels
        var samples = [Float](repeating: 0, count: sampleCount)
        let timeOffset = CMTimeGetSeconds(presentationTime)

        for frame in 0..<frameCount {
            let t = timeOffset + Double(frame) / sampleRate
            let sampleVal = Float(sin(2.0 * .pi * frequency * t) * 0.8)
            for ch in 0..<channels {
                samples[frame * channels + ch] = sampleVal
            }
        }

        let dataSize = sampleCount * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let blockBuffer = blockBuffer else { return nil }

        let replaceStatus = samples.withUnsafeBufferPointer { ptr in
            CMBlockBufferReplaceDataBytes(
                with: ptr.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: dataSize
            )
        }
        guard replaceStatus == noErr else { return nil }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: Int64(frameCount), timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        let bufferStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDesc,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard bufferStatus == noErr else { return nil }
        return sampleBuffer
    }
}
