import Foundation
import AVFoundation
import CoreMedia
import os

public enum ResilientWriterError: LocalizedError {
    case writerCreationFailed(Error)
    case cannotAddInput
    case startWritingFailed(String)
    case notWriting
    case appendFailed(String)
    case invalidSampleBuffer

    public var errorDescription: String? {
        switch self {
        case .writerCreationFailed(let error):
            return "Failed to initialize AVAssetWriter: \(error.localizedDescription)"
        case .cannotAddInput:
            return "Asset writer rejected the audio input configuration."
        case .startWritingFailed(let reason):
            return "Could not start asset writing: \(reason)"
        case .notWriting:
            return "Audio writer is not in writing state."
        case .appendFailed(let reason):
            return "Failed to append audio sample: \(reason)"
        case .invalidSampleBuffer:
            return "Sample buffer is missing format or timing information."
        }
    }
}

public final class ResilientAudioWriter: @unchecked Sendable {
    public let outputURL: URL
    public let format: AudioFormat
    public let fragmentInterval: TimeInterval

    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?

    private struct WriterState {
        var isStarted = false
        var firstSampleTime: CMTime = .invalid
        var lastSampleTime: CMTime = .invalid
        var samplesWritten: Int64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: WriterState())

    public init(
        outputURL: URL,
        format: AudioFormat = .m4aAAC,
        sampleRate: Double = 48000.0,
        channels: Int = 2,
        fragmentInterval: TimeInterval = 2.0,
        bitRate: Int = 256000
    ) throws {
        self.outputURL = outputURL
        self.format = format
        self.fragmentInterval = fragmentInterval

        // Ensure parent directory exists
        let parentDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Remove any stale file at destination
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        do {
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: format.avFileType)

            // CRITICAL FOR FAULT TOLERANCE:
            // Setting movieFragmentInterval creates Fragmented MP4 (fMP4)
            // It writes self-contained movie fragments (moof + mdat) periodically.
            // If the app is killed or crashes, all fragments flushed up to that point
            // remain fully valid and immediately playable!
            if format == .m4aAAC {
                writer.movieFragmentInterval = CMTime(seconds: fragmentInterval, preferredTimescale: 600)
                writer.shouldOptimizeForNetworkUse = false
            }

            let outputSettings: [String: Any]
            switch format {
            case .m4aAAC:
                outputSettings = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: bitRate
                ]
            case .wavPCM:
                outputSettings = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            case .cafLossless:
                outputSettings = [
                    AVFormatIDKey: kAudioFormatAppleLossless,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitDepthHintKey: 16
                ]
            }

            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
            input.expectsMediaDataInRealTime = true

            guard writer.canAdd(input) else {
                throw ResilientWriterError.cannotAddInput
            }

            writer.add(input)

            self.assetWriter = writer
            self.writerInput = input
        } catch {
            throw ResilientWriterError.writerCreationFailed(error)
        }
    }

    /// Appends a CMSampleBuffer to the resilient audio stream.
    @discardableResult
    public func append(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let writer = assetWriter, let input = writerInput else {
            return false
        }

        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return false
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid else {
            return false
        }

        let shouldStart = state.withLock { s -> Bool in
            if !s.isStarted {
                s.isStarted = true
                s.firstSampleTime = presentationTime
                return true
            }
            return false
        }

        if shouldStart {
            guard writer.startWriting() else {
                state.withLock { $0.isStarted = false }
                return false
            }
            writer.startSession(atSourceTime: presentationTime)
        }

        guard writer.status == .writing else {
            return false
        }

        if input.isReadyForMoreMediaData {
            if input.append(sampleBuffer) {
                state.withLock {
                    $0.lastSampleTime = presentationTime
                    $0.samplesWritten += 1
                }
                return true
            }
        }
        return false
    }

    /// Flushes any pending fragments and syncs file to disk
    public func flush() {
        // With fragmented MP4 (movieFragmentInterval), fragments are emitted automatically.
        // Synchronizing the file descriptor ensures disk writes are pushed to physical storage.
        if let fileHandle = try? FileHandle(forUpdating: outputURL) {
            try? fileHandle.synchronize()
            try? fileHandle.close()
        }
    }

    /// Finalizes the recording gracefully
    public func finish() async throws -> URL {
        guard let writer = assetWriter, let input = writerInput else {
            throw ResilientWriterError.notWriting
        }

        let started = state.withLock { $0.isStarted }
        guard started else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw ResilientWriterError.notWriting
        }

        input.markAsFinished()

        return try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume(returning: self.outputURL)
                } else if let error = writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: self.outputURL)
                }
            }
        }
    }

    public var recordedDuration: TimeInterval {
        state.withLock { s in
            guard s.isStarted, s.firstSampleTime.isValid, s.lastSampleTime.isValid else { return 0 }
            let duration = CMTimeSubtract(s.lastSampleTime, s.firstSampleTime)
            return max(0, CMTimeGetSeconds(duration))
        }
    }

    public var currentFileSize: Int64 {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            return (attrs[.size] as? Int64) ?? 0
        } catch {
            return 0
        }
    }
}
