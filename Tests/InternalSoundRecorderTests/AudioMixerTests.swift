import XCTest
import CoreMedia
@testable import InternalSoundRecorderCore

final class AudioMixerTests: XCTestCase {

    func testMixerCombinesSystemAndMicrophone() {
        let mixer = AudioMixer()

        let micBuffer = MockAudioGenerator.makeAudioSampleBuffer(
            frameCount: 1024,
            sampleRate: 48000,
            channels: 2,
            frequency: 440.0,
            presentationTime: CMTime(value: 0, timescale: 48000)
        )!

        let sysBuffer = MockAudioGenerator.makeAudioSampleBuffer(
            frameCount: 1024,
            sampleRate: 48000,
            channels: 2,
            frequency: 440.0,
            presentationTime: CMTime(value: 0, timescale: 48000)
        )!

        // Pre-mix levels of system buffer
        let preLevels = AudioLevelMeter().processSampleBuffer(sysBuffer)

        // Ingest mic and mix into system buffer
        mixer.ingestMicrophoneBuffer(micBuffer)
        let mixedBuffer = mixer.mixSystemAudioBuffer(sysBuffer)

        // Post-mix levels should be louder
        let postLevels = AudioLevelMeter().processSampleBuffer(mixedBuffer)

        XCTAssertGreaterThan(postLevels.peak, preLevels.peak)
        XCTAssertGreaterThan(postLevels.rms, preLevels.rms)
    }

    func testMixerPreventsDistortionClipping() {
        let mixer = AudioMixer()

        // Create 2 loud buffers
        let micBuffer = MockAudioGenerator.makeAudioSampleBuffer(
            frameCount: 1024,
            frequency: 440.0,
            presentationTime: CMTime(value: 0, timescale: 48000)
        )!
        let sysBuffer = MockAudioGenerator.makeAudioSampleBuffer(
            frameCount: 1024,
            frequency: 440.0,
            presentationTime: CMTime(value: 0, timescale: 48000)
        )!

        mixer.ingestMicrophoneBuffer(micBuffer)
        let mixedBuffer = mixer.mixSystemAudioBuffer(sysBuffer)

        let levels = AudioLevelMeter().processSampleBuffer(mixedBuffer)
        // Hard clip ensures peak never exceeds 1.0 (0 dBFS)
        XCTAssertLessThanOrEqual(levels.peak, 1.0001)
    }

    func testMixerVolumeScaling() {
        let mixer = AudioMixer(systemVolume: 0.5, micVolume: 1.5)

        let sysBuffer = MockAudioGenerator.makeAudioSampleBuffer(
            frameCount: 1024,
            sampleRate: 48000,
            channels: 2,
            frequency: 440.0,
            presentationTime: CMTime(value: 0, timescale: 48000)
        )!

        let originalLevels = AudioLevelMeter().processSampleBuffer(sysBuffer)
        let attenuatedBuffer = mixer.mixSystemAudioBuffer(sysBuffer)
        let attenuatedLevels = AudioLevelMeter().processSampleBuffer(attenuatedBuffer)

        // At 50% volume, peak should be lower than original
        XCTAssertLessThan(attenuatedLevels.peak, originalLevels.peak)
    }

    func testNonInterleavedStereoMixingWithMonoMicrophone() throws {
        let mixer = AudioMixer(systemVolume: 1.0, micVolume: 1.0)

        // 1. Create a mono mic buffer (channels = 1, e.g. Mac built-in mic)
        let frameCount = 1024
        let micBuffer = try XCTUnwrap(MockAudioGenerator.makeAudioSampleBuffer(
            frameCount: frameCount,
            sampleRate: 48000,
            channels: 1,
            frequency: 440.0,
            presentationTime: CMTime(value: 0, timescale: 48000)
        ))

        // 2. Create a silent non-interleaved stereo system audio buffer (like ScreenCaptureKit native)
        let sysBuffer = try XCTUnwrap(MockAudioGenerator.makeNonInterleavedAudioSampleBuffer(
            frameCount: frameCount,
            sampleRate: 48000,
            leftFrequency: 0.0,
            rightFrequency: 0.0,
            presentationTime: CMTime(value: 0, timescale: 48000)
        ))

        // Ingest mono mic and mix into non-interleaved system audio
        mixer.ingestMicrophoneBuffer(micBuffer)
        let mixedBuffer = mixer.mixSystemAudioBuffer(sysBuffer)

        // Extract both channel buffers from mixed non-interleaved CMSampleBuffer
        var blockBuffer: CMBlockBuffer?
        var bufferListSizeNeeded = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            mixedBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )

        let bufferListPointer = AudioBufferList.allocate(maximumBuffers: bufferListSizeNeeded)
        defer { free(bufferListPointer.unsafeMutablePointer) }

        let extractStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            mixedBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferListPointer.unsafeMutablePointer,
            bufferListSize: bufferListSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        XCTAssertEqual(extractStatus, noErr)
        XCTAssertEqual(bufferListPointer.count, 2, "ScreenCaptureKit native audio must have 2 distinct buffers (Left & Right)")

        let leftPtr = bufferListPointer[0].mData!.assumingMemoryBound(to: Float.self)
        let rightPtr = bufferListPointer[1].mData!.assumingMemoryBound(to: Float.self)

        // Left and Right channels must be perfectly synchronized and non-zero
        var nonZeroCount = 0
        for i in 0..<frameCount {
            let leftSample = leftPtr[i]
            let rightSample = rightPtr[i]
            // Left and Right channels must have identical samples
            XCTAssertEqual(leftSample, rightSample, accuracy: 0.0001, "Left and Right channels must be identical for mono mic input at frame \(i)")

            if abs(leftSample) > 0.01 {
                nonZeroCount += 1
            }
        }
        XCTAssertGreaterThan(nonZeroCount, 500, "Microphone audio must be present in both channels")

        // Crucial bug prevention check:
        // Ensure adjacent samples are NOT duplicated! In the old bug, [s0, s0, s1, s1] caused 0.5x speed.
        // For a 440Hz sine wave at 48kHz, s[0] != s[1] and s[1] != s[2] everywhere away from the peak.
        var duplicatesCount = 0
        for i in 0..<(frameCount - 1) {
            if abs(leftPtr[i] - leftPtr[i + 1]) < 0.000001 && abs(leftPtr[i]) > 0.1 {
                duplicatesCount += 1
            }
        }
        XCTAssertEqual(duplicatesCount, 0, "No duplicate consecutive samples should exist (prevents 0.5x slow-motion/halved pitch bug)")
    }

    func testConsecutiveBuffersStreamingAndPhaseAlignment() throws {
        let mixer = AudioMixer(systemVolume: 0.0, micVolume: 1.0)
        let frameCount = 1024
        let bufferCount = 4

        for b in 0..<bufferCount {
            let pts = CMTime(value: Int64(b * frameCount), timescale: 48000)
            let micBuffer = try XCTUnwrap(MockAudioGenerator.makeAudioSampleBuffer(
                frameCount: frameCount,
                sampleRate: 48000,
                channels: 1,
                frequency: 220.0,
                presentationTime: pts
            ))
            let sysBuffer = try XCTUnwrap(MockAudioGenerator.makeNonInterleavedAudioSampleBuffer(
                frameCount: frameCount,
                sampleRate: 48000,
                leftFrequency: 0.0,
                rightFrequency: 0.0,
                presentationTime: pts
            ))

            mixer.ingestMicrophoneBuffer(micBuffer)
            let mixed = mixer.mixSystemAudioBuffer(sysBuffer)

            let levels = AudioLevelMeter().processSampleBuffer(mixed)
            XCTAssertGreaterThan(levels.peak, 0.5, "Buffer \(b) must have mic audio mixed in")
        }
    }
}
