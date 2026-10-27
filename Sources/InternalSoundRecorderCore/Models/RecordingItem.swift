import Foundation

public struct RecordingItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let createdAt: Date
    public let duration: TimeInterval
    public let fileSize: Int64
    public let format: AudioFormat

    public init(
        id: UUID = UUID(),
        url: URL,
        createdAt: Date = Date(),
        duration: TimeInterval,
        fileSize: Int64,
        format: AudioFormat
    ) {
        self.id = id
        self.url = url
        self.createdAt = createdAt
        self.duration = duration
        self.fileSize = fileSize
        self.format = format
    }

    public var filename: String {
        url.lastPathComponent
    }

    public var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
