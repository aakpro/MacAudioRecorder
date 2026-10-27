import SwiftUI
import AppKit
import InternalSoundRecorderCore

@main
struct InternalSoundRecorderApp: App {
    @StateObject private var manager = RecordingManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(manager: manager)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            if manager.status == .recording {
                Image(systemName: "record.circle.fill")
                    .foregroundColor(.red)
                Text(formatDuration(manager.recordedDuration))
                    .monospacedDigit()
                    .font(.system(size: 11, weight: .semibold))
            } else if manager.status == .paused {
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.orange)
            } else if manager.status == .recovering {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundColor(.yellow)
            } else {
                Image(systemName: "waveform")
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
