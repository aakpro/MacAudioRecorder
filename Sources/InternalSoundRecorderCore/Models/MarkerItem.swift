import Foundation

public struct MarkerItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: TimeInterval
    public var label: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        label: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.label = label
        self.createdAt = createdAt
    }

    public var formattedTimestamp: String {
        let totalSeconds = Int(timestamp)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
