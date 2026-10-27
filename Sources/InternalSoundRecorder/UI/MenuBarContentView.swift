import SwiftUI
import AppKit
import InternalSoundRecorderCore

public struct MenuBarContentView: View {
    @ObservedObject var manager: RecordingManager
    @State private var showingSettings = false

    public init(manager: RecordingManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header
            headerView

            // Permission Warning if missing
            if !manager.permissionManager.hasScreenCapturePermission {
                PermissionBannerView(permissionManager: manager.permissionManager)
            }

            // Live Audio Level & Waveform
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("System Audio Monitor")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if manager.status == .recording {
                        Text(String(format: "%.0f dBFS", manager.audioLevels.decibels))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
                AudioWaveformView(
                    levels: manager.audioLevels,
                    isRecording: manager.status == .recording
                )
            }

            // Recording Status & Counter
            if manager.status.isRecordingOrPaused {
                recordingMetricsView
            }

            // Controls (Start / Pause / Stop)
            controlsView

            Divider()

            // Recent Recordings Section
            recentRecordingsSection

            Divider()

            // Footer
            footerView
        }
        .padding(14)
        .frame(width: 360)
        .sheet(isPresented: $showingSettings) {
            SettingsView(manager: manager)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("Internal Sound Recorder")
                .font(.headline)
            Spacer()
            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch manager.status {
        case .idle:
            Text("Ready")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        case .recording:
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("REC")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.15))
            .cornerRadius(4)
        case .paused:
            Text("PAUSED")
                .font(.caption2.weight(.bold))
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(4)
        case .recovering:
            Text("RECOVERING...")
                .font(.caption2.weight(.bold))
                .foregroundColor(.yellow)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.15))
                .cornerRadius(4)
        case .stopping:
            Text("SAVING...")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        case .error(let msg):
            Text("Error")
                .font(.caption2.weight(.bold))
                .foregroundColor(.red)
                .help(msg)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.15))
                .cornerRadius(4)
        }
    }

    // MARK: - Recording Metrics

    private var recordingMetricsView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DURATION")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Text(formatDuration(manager.recordedDuration))
                    .font(.title2.monospacedDigit().bold())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("FILE SIZE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: manager.currentFileSize, countStyle: .file))
                    .font(.subheadline.monospacedDigit().bold())
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - Controls

    private var controlsView: some View {
        HStack(spacing: 12) {
            if manager.status == .idle || isCaseError(manager.status) {
                Button(action: {
                    Task {
                        try? await manager.startRecording()
                    }
                }) {
                    HStack {
                        Image(systemName: "record.circle.fill")
                            .font(.title3)
                            .foregroundColor(.red)
                        Text("Start Recording")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.85))
            } else {
                // Pause / Resume Button
                Button(action: {
                    if manager.status == .paused {
                        manager.resumeRecording()
                    } else {
                        manager.pauseRecording()
                    }
                }) {
                    Image(systemName: manager.status == .paused ? "play.fill" : "pause.fill")
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.bordered)

                // Stop & Save Button
                Button(action: {
                    Task {
                        _ = try? await manager.stopRecording()
                    }
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.white)
                        Text("Stop & Save")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    // MARK: - Recent Recordings

    private var recentRecordingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent Recordings")
                    .font(.subheadline.bold())
                Spacer()
                if !manager.recentRecordings.isEmpty {
                    Text("\(manager.recentRecordings.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if manager.recentRecordings.isEmpty {
                Text("No recordings yet. Recorded audio is automatically saved to your disk.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(manager.recentRecordings.prefix(3)) { item in
                        recordingRow(item)
                    }
                }
            }
        }
    }

    private func recordingRow(_ item: RecordingItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundColor(.accentColor)
                .font(.caption)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.filename)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(item.formattedDuration)
                    Text("•")
                    Text(item.formattedSize)
                    Text("•")
                    Text(item.format.fileExtension.uppercased())
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }

            Spacer()

            // Play / Open
            Button(action: {
                NSWorkspace.shared.open(item.url)
            }) {
                Image(systemName: "play.circle")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Play recording")

            // Reveal in Finder
            Button(action: {
                manager.revealInFinder(url: item.url)
            }) {
                Image(systemName: "folder")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .padding(6)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(6)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button(action: {
                manager.openSaveDirectory()
            }) {
                Image(systemName: "folder")
                Text("Recordings Folder")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
            .help("Settings")

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Quit")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
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

    private func isCaseError(_ s: RecordingStatus) -> Bool {
        if case .error = s { return true }
        return false
    }
}
