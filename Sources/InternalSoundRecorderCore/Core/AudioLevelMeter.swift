import Foundation
import CoreMedia
import Accelerate
import os

public struct AudioLevels: Sendable {
    public let rms: Float       // Normalized 0.0 ... 1.0
    public let peak: Float      // Normalized 0.0 ... 1.0
    public let decibels: Float  // -60 dBFS to 0 dBFS

    public static let zero = AudioLevels(rms: 0, peak: 0, decibels: -60)
}

public final class AudioLevelMeter: @unchecked Sendable {
    private let decayFactor: Float = 0.88 // Smooth falloff for UI visualization
    private let smoothedPeak = OSAllocatedUnfairLock(initialState: Float(0.0))

    public init() {}

    /// Pure calculation from raw Float32 PCM samples (ideal for unit testing)
    public static func calculateLevels(samples: [Float]) -> AudioLevels {
        guard !samples.isEmpty else { return .zero }
        return samples.withUnsafeBufferPointer { buffer in
            guard let ptr = buffer.baseAddress else { return .zero }
            return calculateLevels(from: ptr, count: samples.count)
        }
    }

    /// Fast Accelerate/vDSP computation from raw Float32 pointer
    public static func calculateLevels(from ptr: UnsafePointer<Float>, count: Int) -> AudioLevels {
        guard count > 0 else { return .zero }

        var rms: Float = 0.0
        vDSP_rmsqv(ptr, 1, &rms, vDSP_Length(count))

        var peak: Float = 0.0
        vDSP_maxmgv(ptr, 1, &peak, vDSP_Length(count))

        // Convert RMS to dBFS (-60 dB to 0 dB range)
        let minDB: Float = -60.0
        let decibels: Float
        if rms > 0.00001 {
            decibels = max(minDB, min(0.0, 20.0 * log10(rms)))
        } else {
            decibels = minDB
        }

        // Normalize dB (-60 dB to 0 dB -> 0.0 to 1.0)
        let normalizedRMS = (decibels - minDB) / (-minDB)
        let normalizedPeak = min(1.0, max(0.0, peak))

        return AudioLevels(
            rms: normalizedRMS,
            peak: normalizedPeak,
            decibels: decibels
        )
    }

    /// Processes a CMSampleBuffer coming from ScreenCaptureKit or AVFoundation
    public func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> AudioLevels {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return .zero
        }

        var blockBuffer: CMBlockBuffer?
        var bufferListSizeNeeded: Int = 0

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )

        guard status == noErr, bufferListSizeNeeded > 0 else {
            return .zero
        }

        let bufferListPointer = AudioBufferList.allocate(maximumBuffers: bufferListSizeNeeded)
        defer { free(bufferListPointer.unsafeMutablePointer) }

        let extractStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferListPointer.unsafeMutablePointer,
            bufferListSize: bufferListSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard extractStatus == noErr else { return .zero }

        var maxRMS: Float = 0.0
        var maxPeak: Float = 0.0

        for buffer in bufferListPointer {
            guard let data = buffer.mData else { continue }
            let byteCount = Int(buffer.mDataByteSize)

            if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                let floatCount = byteCount / MemoryLayout<Float>.size
                guard floatCount > 0 else { continue }
                let floatPtr = data.assumingMemoryBound(to: Float.self)
                let levels = Self.calculateLevels(from: floatPtr, count: floatCount)
                maxRMS = max(maxRMS, levels.rms)
                maxPeak = max(maxPeak, levels.peak)
            } else if asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 && asbd.mBitsPerChannel == 16 {
                let int16Count = byteCount / MemoryLayout<Int16>.size
                guard int16Count > 0 else { continue }
                let int16Ptr = data.assumingMemoryBound(to: Int16.self)

                var floatSamples = [Float](repeating: 0, count: int16Count)
                for i in 0..<int16Count {
                    floatSamples[i] = Float(int16Ptr[i]) / 32768.0
                }
                let levels = Self.calculateLevels(samples: floatSamples)
                maxRMS = max(maxRMS, levels.rms)
                maxPeak = max(maxPeak, levels.peak)
            }
        }

        let peakToSmooth = maxPeak
        let currentPeak = smoothedPeak.withLock { s -> Float in
            s = max(peakToSmooth, s * decayFactor)
            return s
        }

        let minDB: Float = -60.0
        let decibels = minDB + (maxRMS * (-minDB))

        return AudioLevels(rms: maxRMS, peak: currentPeak, decibels: decibels)
    }

    public func reset() {
        smoothedPeak.withLock { $0 = 0.0 }
    }
}
