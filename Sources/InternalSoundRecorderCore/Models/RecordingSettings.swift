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

public enum StemRecordingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case mixedOnly = "Single Unified Master Track (Recommended)"
    case separateStems = "Separate Stems (Master + Isolated Mic & System Files)"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .mixedOnly:
            return "Saves one perfectly balanced stereo audio file ready for instant listening and sharing."
        case .separateStems:
            return "Saves the master file PLUS isolated _system.m4a and _mic.m4a files for audio editing in Logic/Audacity."
        }
    }
}

public enum CaptureTargetMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case allSystem = "All System Audio (Entire Mac)"
    case specificApps = "Selected Apps Only"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .allSystem:
            return "Records all sound playing across your Mac, regardless of app."
        case .specificApps:
            return "Records only chosen applications (e.g. MS Teams, Zoom), filtering out Spotify or Slack notification dings."
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
    public var includeMicrophone: Bool
    public var systemVolume: Float
    public var microphoneVolume: Float
    public var stemMode: StemRecordingMode
    public var targetMode: CaptureTargetMode
    public var targetAppBundleIDs: [String]

    public init(
        saveDirectory: URL? = nil,
        audioFormat: AudioFormat = .m4aAAC,
        sampleRate: Double = 48000.0,
        channelCount: Int = 2,
        fragmentIntervalSeconds: Double = 2.0,
        aacBitRate: Int = 256000,
        includeMicrophone: Bool = true,
        systemVolume: Float = 1.0,
        microphoneVolume: Float = 1.0,
        stemMode: StemRecordingMode = .mixedOnly,
        targetMode: CaptureTargetMode = .allSystem,
        targetAppBundleIDs: [String] = []
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
        self.includeMicrophone = includeMicrophone
        self.systemVolume = systemVolume
        self.microphoneVolume = microphoneVolume
        self.stemMode = stemMode
        self.targetMode = targetMode
        self.targetAppBundleIDs = targetAppBundleIDs
    }

    public static let `default` = RecordingSettings()
}
