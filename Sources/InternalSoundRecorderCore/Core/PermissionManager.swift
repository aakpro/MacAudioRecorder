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
    @Published public private(set) var speechRecognitionStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published public private(set) var microphoneStatus: AVAuthorizationStatus = .notDetermined

    public init() {
        checkPermission()
    }

    @discardableResult
    public func checkPermission() -> Bool {
        let authorizedScreen = CGPreflightScreenCaptureAccess()
        self.hasScreenCapturePermission = authorizedScreen

        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        self.microphoneStatus = mic
        self.hasMicrophonePermission = (mic == .authorized)

        let speech = SFSpeechRecognizer.authorizationStatus()
        self.speechRecognitionStatus = speech
        self.hasSpeechRecognitionPermission = (speech == .authorized)

        return authorizedScreen
    }

    public func requestPermission() {
        if !hasScreenCapturePermission {
            _ = CGRequestScreenCaptureAccess()
        }

        if !hasMicrophonePermission && microphoneStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.checkPermission()
                }
            }
        }

        if !hasSpeechRecognitionPermission && speechRecognitionStatus == .notDetermined {
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

    @discardableResult
    public func requestSpeechRecognitionPermission() async -> Bool {
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        self.checkPermission()
        return authorized
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

    public func openMicrophoneSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
