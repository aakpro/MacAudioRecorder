import Foundation
import CoreMedia
import Accelerate
import os

public final class AudioMixer: @unchecked Sendable {
    private struct MixerState {
        var micRingBuffer: [Float] = []
        var lastSystemPTS: CMTime = .invalid
        var lastMicPTS: CMTime = .invalid
        var systemVolume: Float = 1.0
        var micVolume: Float = 1.0
    }

    private let state = OSAllocatedUnfairLock(initialState: MixerState())
    private let maxBufferSize = 48000 * 2 * 4 // Up to 4 seconds of stereo Float32 PCM at 48kHz

    public init(systemVolume: Float = 1.0, micVolume: Float = 1.0) {
        state.withLock {
            $0.systemVolume = systemVolume
            $0.micVolume = micVolume
        }
    }

    public func setVolumes(system: Float, mic: Float) {
        state.withLock {
            $0.systemVolume = system
            $0.micVolume = mic
        }
    }

    public func reset() {
        state.withLock {
            $0.micRingBuffer.removeAll(keepingCapacity: true)
            $0.lastSystemPTS = .invalid
            $0.lastMicPTS = .invalid
        }
    }

    /// Ingests a microphone buffer, extracting and normalizing Float32 stereo samples into the ring buffer
    public func ingestMicrophoneBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return
        }

        var blockBuffer: CMBlockBuffer?
        var bufferListSizeNeeded = 0

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
        guard status == noErr, bufferListSizeNeeded > 0 else { return }

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
        guard extractStatus == noErr else { return }

        var extractedStereo: [Float] = []
        let channels = Int(asbd.mChannelsPerFrame)

        for buffer in bufferListPointer {
            guard let data = buffer.mData else { continue }
            let byteCount = Int(buffer.mDataByteSize)

            if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                let floatCount = byteCount / MemoryLayout<Float>.size
                let floatPtr = data.assumingMemoryBound(to: Float.self)
                if channels == 1 {
                    // Convert mono mic to stereo
                    for i in 0..<floatCount {
                        let s = floatPtr[i]
                        extractedStereo.append(s)
                        extractedStereo.append(s)
                    }
                } else {
                    for i in 0..<floatCount {
                        extractedStereo.append(floatPtr[i])
                    }
                }
            } else if asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 && asbd.mBitsPerChannel == 16 {
                let int16Count = byteCount / MemoryLayout<Int16>.size
                let int16Ptr = data.assumingMemoryBound(to: Int16.self)
                if channels == 1 {
                    for i in 0..<int16Count {
                        let s = Float(int16Ptr[i]) / 32768.0
                        extractedStereo.append(s)
                        extractedStereo.append(s)
                    }
                } else {
                    for i in 0..<int16Count {
                        extractedStereo.append(Float(int16Ptr[i]) / 32768.0)
                    }
                }
            }
        }

        guard !extractedStereo.isEmpty else { return }

        let micPts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let samplesToAppend = extractedStereo

        state.withLock { s in
            s.lastMicPTS = micPts
            s.micRingBuffer.append(contentsOf: samplesToAppend)
            if s.micRingBuffer.count > maxBufferSize {
                let overflow = s.micRingBuffer.count - maxBufferSize
                s.micRingBuffer.removeFirst(overflow)
            }
        }
    }

    /// Mixes microphone audio in-place into the system audio sample buffer
    @discardableResult
    public func mixSystemAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        var bufferListSizeNeeded = 0

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
        guard status == noErr, bufferListSizeNeeded > 0 else { return sampleBuffer }

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
        guard extractStatus == noErr else { return sampleBuffer }

        let sysPts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        for buffer in bufferListPointer {
            guard let data = buffer.mData else { continue }
            let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard floatCount > 0 else { continue }
            let systemPtr = data.assumingMemoryBound(to: Float.self)

            // Retrieve matching microphone samples from the ring buffer
            let micSamples = state.withLock { s -> [Float] in
                s.lastSystemPTS = sysPts
                let countToTake = min(floatCount, s.micRingBuffer.count)
                guard countToTake > 0 else { return [] }
                let slice = Array(s.micRingBuffer.prefix(countToTake))
                s.micRingBuffer.removeFirst(countToTake)
                return slice
            }

            if !micSamples.isEmpty {
                micSamples.withUnsafeBufferPointer { micBuffer in
                    guard let micPtr = micBuffer.baseAddress else { return }
                    // Vector addition: systemPtr[i] += micPtr[i]
                    vDSP_vadd(systemPtr, 1, micPtr, 1, systemPtr, 1, vDSP_Length(micSamples.count))

                    // Hard clip to [-1.0, 1.0] to prevent digital clipping/distortion
                    var minVal: Float = -1.0
                    var maxVal: Float = 1.0
                    vDSP_vclip(systemPtr, 1, &minVal, &maxVal, systemPtr, 1, vDSP_Length(micSamples.count))
                }
            }
        }

        return sampleBuffer
    }
}
