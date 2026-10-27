import XCTest
import CoreMedia
@testable import InternalSoundRecorderCore

final class AudioLevelMeterTests: XCTestCase {

    func testSilenceProducesZeroLevels() {
        let silence = [Float](repeating: 0.0, count: 1024)
        let levels = AudioLevelMeter.calculateLevels(samples: silence)

        XCTAssertEqual(levels.rms, 0.0, accuracy: 0.001)
        XCTAssertEqual(levels.peak, 0.0, accuracy: 0.001)
        XCTAssertEqual(levels.decibels, -60.0, accuracy: 0.1)
    }

    func testSineWaveProducesAccurateLevels() {
        var sine = [Float](repeating: 0.0, count: 4800)
        let amplitude: Float = 0.8
        for i in 0..<sine.count {
            sine[i] = amplitude * sin(Float(i) * 0.1)
        }

        let levels = AudioLevelMeter.calculateLevels(samples: sine)

        // Peak should be approximately the amplitude (0.8)
        XCTAssertEqual(levels.peak, amplitude, accuracy: 0.05)

        // RMS for sine wave with amplitude A is A / sqrt(2) ~ 0.8 / 1.414 ~ 0.565
        // Normalized RMS: (-5 dB - (-60 dB)) / 60 dB ~ 55 / 60 ~ 0.91
        XCTAssertGreaterThan(levels.rms, 0.5)
        XCTAssertGreaterThan(levels.decibels, -10.0)
    }

    func testSampleBufferProcessing() {
        let meter = AudioLevelMeter()
        let sampleBuffer = MockAudioGenerator.makeAudioSampleBuffer(
            frameCount: 1024,
            presentationTime: CMTime(value: 0, timescale: 48000)
        )

        XCTAssertNotNil(sampleBuffer)
        let levels = meter.processSampleBuffer(sampleBuffer!)

        XCTAssertGreaterThan(levels.peak, 0.5)
        XCTAssertGreaterThan(levels.rms, 0.5)
        XCTAssertGreaterThan(levels.decibels, -20.0)
    }

    func testPeakDecayAfterLoudSound() {
        let meter = AudioLevelMeter()

        let loudBuffer = MockAudioGenerator.makeAudioSampleBuffer(
            frameCount: 1024,
            frequency: 440.0,
            presentationTime: CMTime(value: 0, timescale: 48000)
        )!
        let loudLevels = meter.processSampleBuffer(loudBuffer)
        XCTAssertGreaterThan(loudLevels.peak, 0.5)

        // Feed silence buffer next
        let silentBuffer = MockAudioGenerator.makeAudioSampleBuffer(
            frameCount: 1024,
            frequency: 0.0,
            presentationTime: CMTime(value: 1024, timescale: 48000)
        )!
        let silentLevels = meter.processSampleBuffer(silentBuffer)

        // Peak should decay smoothly rather than dropping immediately to 0
        XCTAssertLessThanOrEqual(silentLevels.peak, loudLevels.peak)
        XCTAssertGreaterThan(silentLevels.peak, 0.0)
    }
}
