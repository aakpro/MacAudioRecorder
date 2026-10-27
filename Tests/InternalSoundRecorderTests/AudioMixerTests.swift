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
}
