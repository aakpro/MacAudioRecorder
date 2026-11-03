import Foundation
import CoreMedia
import Accelerate
import os

public final class AudioMixer: @unchecked Sendable {
    private struct MixerState {
        var micLeftRingBuffer: [Float] = []
        var micRightRingBuffer: [Float] = []
        var lastSystemPTS: CMTime = .invalid
        var lastMicPTS: CMTime = .invalid
        var systemVolume: Float = 1.0
        var micVolume: Float = 1.0
    }

    private let state = OSAllocatedUnfairLock(initialState: MixerState())
    // 4 seconds of audio frames at 48kHz
    private let maxBufferSize = 48000 * 4

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
            $0.micLeftRingBuffer.removeAll(keepingCapacity: true)
            $0.micRightRingBuffer.removeAll(keepingCapacity: true)
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

        var leftSamples: [Float] = []
        var rightSamples: [Float] = []

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isInt16 = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0 && asbd.mBitsPerChannel == 16
        let channelsPerFrame = Int(asbd.mChannelsPerFrame)

        if bufferListPointer.count >= 2 {
            // Non-interleaved stereo (or multi-channel): buffer 0 is Left, buffer 1 is Right
            let leftBuffer = bufferListPointer[0]
            let rightBuffer = bufferListPointer[1]
            guard let leftData = leftBuffer.mData, let rightData = rightBuffer.mData else { return }

            if isFloat {
                let frameCount = Int(leftBuffer.mDataByteSize) / MemoryLayout<Float>.size
                let leftPtr = leftData.assumingMemoryBound(to: Float.self)
                let rightPtr = rightData.assumingMemoryBound(to: Float.self)
                leftSamples = Array(UnsafeBufferPointer(start: leftPtr, count: frameCount))
                rightSamples = Array(UnsafeBufferPointer(start: rightPtr, count: frameCount))
            } else if isInt16 {
                let frameCount = Int(leftBuffer.mDataByteSize) / MemoryLayout<Int16>.size
                let leftPtr = leftData.assumingMemoryBound(to: Int16.self)
                let rightPtr = rightData.assumingMemoryBound(to: Int16.self)
                leftSamples.reserveCapacity(frameCount)
                rightSamples.reserveCapacity(frameCount)
                for i in 0..<frameCount {
                    leftSamples.append(Float(leftPtr[i]) / 32768.0)
                    rightSamples.append(Float(rightPtr[i]) / 32768.0)
                }
            }
        } else if let firstBuffer = bufferListPointer.first, let data = firstBuffer.mData {
            let byteCount = Int(firstBuffer.mDataByteSize)

            if isFloat {
                let floatCount = byteCount / MemoryLayout<Float>.size
                let ptr = data.assumingMemoryBound(to: Float.self)
                if channelsPerFrame <= 1 {
                    // Mono mic: duplicate mono frame to both Left and Right channels
                    leftSamples = Array(UnsafeBufferPointer(start: ptr, count: floatCount))
                    rightSamples = leftSamples
                } else {
                    // Interleaved stereo mic: ptr[2*i] = L, ptr[2*i+1] = R
                    let frameCount = floatCount / channelsPerFrame
                    leftSamples.reserveCapacity(frameCount)
                    rightSamples.reserveCapacity(frameCount)
                    for i in 0..<frameCount {
                        leftSamples.append(ptr[i * channelsPerFrame])
                        rightSamples.append(ptr[i * channelsPerFrame + 1])
                    }
                }
            } else if isInt16 {
                let int16Count = byteCount / MemoryLayout<Int16>.size
                let ptr = data.assumingMemoryBound(to: Int16.self)
                if channelsPerFrame <= 1 {
                    // Mono Int16
                    leftSamples.reserveCapacity(int16Count)
                    for i in 0..<int16Count {
                        leftSamples.append(Float(ptr[i]) / 32768.0)
                    }
                    rightSamples = leftSamples
                } else {
                    // Interleaved stereo Int16
                    let frameCount = int16Count / channelsPerFrame
                    leftSamples.reserveCapacity(frameCount)
                    rightSamples.reserveCapacity(frameCount)
                    for i in 0..<frameCount {
                        leftSamples.append(Float(ptr[i * channelsPerFrame]) / 32768.0)
                        rightSamples.append(Float(ptr[i * channelsPerFrame + 1]) / 32768.0)
                    }
                }
            }
        }

        guard !leftSamples.isEmpty else { return }

        let micPts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let samplesToAppendLeft = leftSamples
        let samplesToAppendRight = rightSamples

        state.withLock { s in
            s.lastMicPTS = micPts
            s.micLeftRingBuffer.append(contentsOf: samplesToAppendLeft)
            s.micRightRingBuffer.append(contentsOf: samplesToAppendRight)
            if s.micLeftRingBuffer.count > maxBufferSize {
                let overflow = s.micLeftRingBuffer.count - maxBufferSize
                s.micLeftRingBuffer.removeFirst(overflow)
                s.micRightRingBuffer.removeFirst(overflow)
            }
        }
    }

    /// Mixes microphone audio in-place into the system audio sample buffer
    @discardableResult
    public func mixSystemAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return sampleBuffer
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

        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0 || bufferListPointer.count > 1
        let channelsPerFrame = max(1, Int(asbd.mChannelsPerFrame))
        let frameCount: Int
        if isNonInterleaved {
            guard let firstBuf = bufferListPointer.first else { return sampleBuffer }
            frameCount = Int(firstBuf.mDataByteSize) / MemoryLayout<Float>.size
        } else {
            guard let firstBuf = bufferListPointer.first else { return sampleBuffer }
            let totalFloats = Int(firstBuf.mDataByteSize) / MemoryLayout<Float>.size
            frameCount = totalFloats / channelsPerFrame
        }

        guard frameCount > 0 else { return sampleBuffer }

        let sysPts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Dequeue matching microphone frames ONCE for this entire audio frame block
        let (sysVol, micVol, leftMic, rightMic) = state.withLock { s -> (Float, Float, [Float], [Float]) in
            s.lastSystemPTS = sysPts
            let countToTake = min(frameCount, s.micLeftRingBuffer.count)
            if countToTake > 0 {
                let lChunk = Array(s.micLeftRingBuffer.prefix(countToTake))
                let rChunk = Array(s.micRightRingBuffer.prefix(countToTake))
                s.micLeftRingBuffer.removeFirst(countToTake)
                s.micRightRingBuffer.removeFirst(countToTake)
                return (s.systemVolume, s.micVolume, lChunk, rChunk)
            } else {
                return (s.systemVolume, s.micVolume, [], [])
            }
        }

        let micCount = leftMic.count

        if isNonInterleaved && bufferListPointer.count >= 2 {
            // ScreenCaptureKit native stereo non-interleaved (Buffer 0 = Left, Buffer 1 = Right)
            let leftBuffer = bufferListPointer[0]
            let rightBuffer = bufferListPointer[1]
            guard let leftData = leftBuffer.mData, let rightData = rightBuffer.mData else { return sampleBuffer }
            let leftPtr = leftData.assumingMemoryBound(to: Float.self)
            let rightPtr = rightData.assumingMemoryBound(to: Float.self)

            if sysVol != 1.0 {
                var vol = sysVol
                vDSP_vsmul(leftPtr, 1, &vol, leftPtr, 1, vDSP_Length(frameCount))
                vDSP_vsmul(rightPtr, 1, &vol, rightPtr, 1, vDSP_Length(frameCount))
            }

            if micCount > 0 {
                var lMic = leftMic
                var rMic = rightMic
                if micVol != 1.0 {
                    var mVol = micVol
                    vDSP_vsmul(lMic, 1, &mVol, &lMic, 1, vDSP_Length(micCount))
                    vDSP_vsmul(rMic, 1, &mVol, &rMic, 1, vDSP_Length(micCount))
                }
                lMic.withUnsafeBufferPointer { lBuf in
                    guard let lPtr = lBuf.baseAddress else { return }
                    vDSP_vadd(leftPtr, 1, lPtr, 1, leftPtr, 1, vDSP_Length(micCount))
                }
                rMic.withUnsafeBufferPointer { rBuf in
                    guard let rPtr = rBuf.baseAddress else { return }
                    vDSP_vadd(rightPtr, 1, rPtr, 1, rightPtr, 1, vDSP_Length(micCount))
                }
            }

            var minVal: Float = -1.0
            var maxVal: Float = 1.0
            vDSP_vclip(leftPtr, 1, &minVal, &maxVal, leftPtr, 1, vDSP_Length(frameCount))
            vDSP_vclip(rightPtr, 1, &minVal, &maxVal, rightPtr, 1, vDSP_Length(frameCount))

            // Scale volume for any extra non-interleaved channels
            if bufferListPointer.count > 2 && sysVol != 1.0 {
                for c in 2..<bufferListPointer.count {
                    if let data = bufferListPointer[c].mData {
                        let ptr = data.assumingMemoryBound(to: Float.self)
                        var vol = sysVol
                        vDSP_vsmul(ptr, 1, &vol, ptr, 1, vDSP_Length(frameCount))
                    }
                }
            }
        } else if let firstBuf = bufferListPointer.first, let data = firstBuf.mData {
            // Single buffer: either interleaved stereo or mono
            let ptr = data.assumingMemoryBound(to: Float.self)

            if channelsPerFrame == 1 {
                // Mono system audio
                if sysVol != 1.0 {
                    var vol = sysVol
                    vDSP_vsmul(ptr, 1, &vol, ptr, 1, vDSP_Length(frameCount))
                }
                if micCount > 0 {
                    var monoMic = [Float](repeating: 0, count: micCount)
                    for i in 0..<micCount {
                        monoMic[i] = (leftMic[i] + rightMic[i]) * 0.5 * micVol
                    }
                    monoMic.withUnsafeBufferPointer { mBuf in
                        guard let mPtr = mBuf.baseAddress else { return }
                        vDSP_vadd(ptr, 1, mPtr, 1, ptr, 1, vDSP_Length(micCount))
                    }
                }
                var minVal: Float = -1.0
                var maxVal: Float = 1.0
                vDSP_vclip(ptr, 1, &minVal, &maxVal, ptr, 1, vDSP_Length(frameCount))
            } else {
                // Interleaved stereo (or multi-channel)
                for i in 0..<frameCount {
                    var l = ptr[i * channelsPerFrame] * sysVol
                    var r = ptr[i * channelsPerFrame + 1] * sysVol
                    if i < micCount {
                        l += leftMic[i] * micVol
                        r += rightMic[i] * micVol
                    }
                    ptr[i * channelsPerFrame] = max(-1.0, min(1.0, l))
                    ptr[i * channelsPerFrame + 1] = max(-1.0, min(1.0, r))
                }
            }
        }

        return sampleBuffer
    }
}
