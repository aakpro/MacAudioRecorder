import Foundation
import AppKit

public struct RunningAppSummary: Identifiable, Hashable, Sendable {
    public var id: String { bundleIdentifier }
    public let name: String
    public let bundleIdentifier: String

    public init(name: String, bundleIdentifier: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

@MainActor
public final class MeetingDetector: ObservableObject {
    @Published public private(set) var detectedMeetingApp: String? = nil
    @Published public private(set) var runningApps: [RunningAppSummary] = []

    private let knownMeetingApps: [String: String] = [
        "com.microsoft.teams": "Microsoft Teams",
        "com.microsoft.teams2": "Microsoft Teams",
        "us.zoom.xos": "Zoom",
        "com.cisco.webexmeetingsapp": "Cisco Webex",
        "com.apple.FaceTime": "FaceTime",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.google.Chrome": "Google Meet / Chrome",
        "com.brave.Browser": "Brave",
        "com.apple.Safari": "Safari"
    ]

    private var workspaceObserver: (any NSObjectProtocol)?

    public init() {
        scanRunningApps()
        setupWorkspaceObserver()
    }

    isolated deinit {
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    public func scanRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningAppSummary? in
                guard let bundleID = app.bundleIdentifier, let name = app.localizedName else { return nil }
                return RunningAppSummary(name: name, bundleIdentifier: bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        self.runningApps = apps
        checkForMeetingApps()
    }

    private func checkForMeetingApps() {
        for app in runningApps {
            if let friendlyName = knownMeetingApps[app.bundleIdentifier] {
                // Focus on primary meeting clients first
                if app.bundleIdentifier.contains("teams") || app.bundleIdentifier.contains("zoom") || app.bundleIdentifier.contains("webex") || app.bundleIdentifier.contains("FaceTime") {
                    self.detectedMeetingApp = friendlyName
                    return
                }
            }
        }
    }

    private func setupWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanRunningApps()
            }
        }
    }
}
