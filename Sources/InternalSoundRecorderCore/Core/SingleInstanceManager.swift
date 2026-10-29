import Foundation
import AppKit

/// Manages application process lifecycle to ensure only a single instance of InternalSoundRecorder runs at any time.
@MainActor
public final class SingleInstanceManager: Sendable {
    public static let shared = SingleInstanceManager()

    public static let bundleIdentifier = "com.internalsoundrecorder.app"
    public static let processName = "InternalSoundRecorder"

    public init() {}

    /// Finds any running instances of InternalSoundRecorder other than the current process.
    public func findOtherRunningInstances() -> [NSRunningApplication] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != currentPID else { return false }

            if let bundleID = app.bundleIdentifier, bundleID == Self.bundleIdentifier {
                return true
            }

            if let execURL = app.executableURL, execURL.lastPathComponent == Self.processName {
                return true
            }

            if let localizedName = app.localizedName, localizedName == Self.processName {
                return true
            }

            return false
        }
    }

    /// Enforces that only one instance of InternalSoundRecorder is running.
    /// If duplicate instances are found, terminates them so this freshly launched instance takes over.
    /// Returns the number of other instances terminated.
    @discardableResult
    public func enforceSingleInstance() -> Int {
        let others = findOtherRunningInstances()
        guard !others.isEmpty else { return 0 }

        var terminatedCount = 0
        for app in others {
            let pid = app.processIdentifier
            app.terminate()
            terminatedCount += 1

            // Fallback: If not terminated within a brief grace period, force terminate
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                if let stillRunning = NSRunningApplication(processIdentifier: pid), !stillRunning.isTerminated {
                    stillRunning.forceTerminate()
                }
            }
        }

        return terminatedCount
    }
}
