import SwiftUI
import InternalSoundRecorderCore

public struct PermissionBannerView: View {
    @ObservedObject var permissionManager: PermissionManager

    public init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
    }

    public var body: some View {
        if !permissionManager.hasScreenCapturePermission {
            screenCaptureBanner
        } else if !permissionManager.hasSpeechRecognitionPermission {
            speechRecognitionBanner
        }
    }

    private var screenCaptureBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission Required")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("macOS requires 'Screen & System Audio Recording' permission to capture internal audio without virtual drivers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button(action: {
                    permissionManager.openSystemSettings()
                }) {
                    Label("Open System Settings", systemImage: "gearshape")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    permissionManager.checkPermission()
                }) {
                    Text("Check Again")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var speechRecognitionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .foregroundColor(.purple)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speech Recognition Authorization")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text("Enable speech recognition to automatically generate meeting notes (.md), plain text (.txt), and subtitles (.srt).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                if permissionManager.speechRecognitionStatus == .denied || permissionManager.speechRecognitionStatus == .restricted {
                    Button(action: {
                        permissionManager.openSpeechRecognitionSettings()
                    }) {
                        Label("Open Speech Settings", systemImage: "gearshape")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                } else {
                    Button(action: {
                        permissionManager.requestSpeechRecognitionPermission()
                    }) {
                        Label("Authorize Speech Recognition", systemImage: "checkmark.shield")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }

                Button(action: {
                    permissionManager.checkPermission()
                }) {
                    Text("Check Again")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color.purple.opacity(0.12))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }
}
