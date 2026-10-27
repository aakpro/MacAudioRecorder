import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit

@MainActor
public final class PermissionManager: ObservableObject {
    @Published public private(set) var hasScreenCapturePermission: Bool = false

    public init() {
        checkPermission()
    }

    @discardableResult
    public func checkPermission() -> Bool {
        let authorized = CGPreflightScreenCaptureAccess()
        self.hasScreenCapturePermission = authorized
        return authorized
    }

    public func requestPermission() {
        if !hasScreenCapturePermission {
            // Triggers macOS permission prompt if not yet granted
            _ = CGRequestScreenCaptureAccess()
            // Check again after triggering
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkPermission()
            }
        }
    }

    public func openSystemSettings() {
        // macOS System Settings Screen Recording Privacy pane
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
