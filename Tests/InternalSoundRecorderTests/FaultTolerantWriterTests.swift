import XCTest
import CoreMedia
import AVFoundation
@testable import InternalSoundRecorderCore

final class FaultTolerantWriterTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ISRTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testFragmentedM4AWritingAndFinalization() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test_recording.m4a")
        let writer = try ResilientAudioWriter(
            outputURL: fileURL,
            format: .m4aAAC,
            sampleRate: 48000,
            channels: 2,
            fragmentInterval: 1.0,
            bitRate: 192000
        )

        let sampleRate: Double = 48000
        let frameCount: Int = 1024
        let totalBuffers = 100 // ~2.13 seconds of audio

        for i in 0..<totalBuffers {
            let pts = CMTime(value: Int64(i * frameCount), timescale: CMTimeScale(sampleRate))
            guard let buffer = MockAudioGenerator.makeAudioSampleBuffer(
                frameCount: frameCount,
                sampleRate: sampleRate,
                channels: 2,
                presentationTime: pts
            ) else {
                XCTFail("Failed to generate mock audio buffer")
                return
            }

            let appended = writer.append(buffer)
            XCTAssertTrue(appended, "Buffer \(i) should append successfully")
        }

        XCTAssertGreaterThan(writer.recordedDuration, 1.5)

        // Finish writing gracefully
        let finalURL = try await writer.finish()
        XCTAssertEqual(finalURL, fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // Verify with AVURLAsset that the output is valid and playable
        let asset = AVURLAsset(url: fileURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(tracks.isEmpty, "Audio track must be present in output file")

        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        XCTAssertGreaterThan(durationSeconds, 1.8)
    }

    func testCrashResiliencePeriodicFlush() throws {
        let fileURL = tempDirectory.appendingPathComponent("test_crash_resilience.m4a")
        let writer = try ResilientAudioWriter(
            outputURL: fileURL,
            format: .m4aAAC,
            sampleRate: 48000,
            channels: 2,
            fragmentInterval: 1.0
        )

        let frameCount: Int = 1024
        let totalBuffers = 100 // ~2.13 seconds

        for i in 0..<totalBuffers {
            let pts = CMTime(value: Int64(i * frameCount), timescale: 48000)
            if let buffer = MockAudioGenerator.makeAudioSampleBuffer(frameCount: frameCount, presentationTime: pts) {
                _ = writer.append(buffer)
            }
        }

        // Flush without calling finish (simulating sudden power loss or process kill)
        writer.flush()

        // File should exist and have data on disk
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertGreaterThan(writer.currentFileSize, 0)
    }

    func testWavPCMRecording() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test_pcm.wav")
        let writer = try ResilientAudioWriter(
            outputURL: fileURL,
            format: .wavPCM,
            sampleRate: 48000,
            channels: 2
        )

        for i in 0..<20 {
            let pts = CMTime(value: Int64(i * 1024), timescale: 48000)
            if let buffer = MockAudioGenerator.makeAudioSampleBuffer(frameCount: 1024, presentationTime: pts) {
                _ = writer.append(buffer)
            }
        }

        let finalURL = try await writer.finish()
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.path))

        let asset = AVURLAsset(url: finalURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(tracks.isEmpty)
    }

    func testCafLosslessRecording() async throws {
        let fileURL = tempDirectory.appendingPathComponent("test_alac.caf")
        let writer = try ResilientAudioWriter(
            outputURL: fileURL,
            format: .cafLossless,
            sampleRate: 48000,
            channels: 2
        )

        for i in 0..<20 {
            let pts = CMTime(value: Int64(i * 1024), timescale: 48000)
            if let buffer = MockAudioGenerator.makeAudioSampleBuffer(frameCount: 1024, presentationTime: pts) {
                _ = writer.append(buffer)
            }
        }

        let finalURL = try await writer.finish()
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.path))
    }
}
