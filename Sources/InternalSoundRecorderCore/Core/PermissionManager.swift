import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit
import AVFoundation
import Speech

@MainActor
public final class PermissionManager: ObservableObject {
    @Published public private(set) var hasScreenCapturePermission: Bool = false
    @Published public private(set) var hasMicrophonePermission: Bool = false
    @Published public private(set) var hasSpeechRecognitionPermission: Bool = false

    public init() {
        checkPermission()
    }

    @discardableResult
    public func checkPermission() -> Bool {
        let authorizedScreen = CGPreflightScreenCaptureAccess()
        self.hasScreenCapturePermission = authorizedScreen

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        self.hasMicrophonePermission = (micStatus == .authorized)

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        self.hasSpeechRecognitionPermission = (speechStatus == .authorized)

        return authorizedScreen
    }

    public func requestPermission() {
        if !hasScreenCapturePermission {
            _ = CGRequestScreenCaptureAccess()
        }

        if !hasMicrophonePermission {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.checkPermission()
                }
            }
        }

        if !hasSpeechRecognitionPermission {
            SFSpeechRecognizer.requestAuthorization { [weak self] _ in
                DispatchQueue.main.async {
                    self?.checkPermission()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkPermission()
        }
    }

    public func requestSpeechRecognitionPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkPermission()
            }
        }
    }

    public func openSystemSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    public func openSpeechRecognitionSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
