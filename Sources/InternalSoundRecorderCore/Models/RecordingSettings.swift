import Foundation
import AVFoundation

public enum AudioFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case m4aAAC = "M4A (AAC, Fragmented)"
    case wavPCM = "WAV (Uncompressed PCM)"
    case cafLossless = "CAF (Core Audio Format)"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .m4aAAC: return "m4a"
        case .wavPCM: return "wav"
        case .cafLossless: return "caf"
        }
    }

    public var avFileType: AVFileType {
        switch self {
        case .m4aAAC: return .m4a
        case .wavPCM: return .wav
        case .cafLossless: return .caf
        }
    }

    public var description: String {
        switch self {
        case .m4aAAC:
            return "Highly compatible, crash-resistant fragmented MP4/AAC. Small file size."
        case .wavPCM:
            return "Industry-standard uncompressed audio. Larger file size."
        case .cafLossless:
            return "Apple 64-bit Core Audio Format, naturally immune to unfinalized header corruption."
        }
    }
}

public struct RecordingSettings: Codable, Sendable {
    public var saveDirectory: URL
    public var audioFormat: AudioFormat
    public var sampleRate: Double
    public var channelCount: Int
    public var fragmentIntervalSeconds: Double
    public var aacBitRate: Int

    public init(
        saveDirectory: URL? = nil,
        audioFormat: AudioFormat = .m4aAAC,
        sampleRate: Double = 48000.0,
        channelCount: Int = 2,
        fragmentIntervalSeconds: Double = 2.0,
        aacBitRate: Int = 256000
    ) {
        if let saveDirectory = saveDirectory {
            self.saveDirectory = saveDirectory
        } else {
            let musicURL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.saveDirectory = musicURL.appendingPathComponent("InternalSoundRecordings", isDirectory: true)
        }
        self.audioFormat = audioFormat
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.fragmentIntervalSeconds = fragmentIntervalSeconds
        self.aacBitRate = aacBitRate
    }

    public static let `default` = RecordingSettings()
}
