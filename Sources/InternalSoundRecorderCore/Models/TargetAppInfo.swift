import Foundation

public struct TargetAppInfo: Identifiable, Hashable, Codable, Sendable {
    public var id: String { bundleIdentifier.isEmpty ? "\(processID)" : bundleIdentifier }
    public let name: String
    public let bundleIdentifier: String
    public let processID: Int32

    public init(name: String, bundleIdentifier: String, processID: Int32) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
    }
}
