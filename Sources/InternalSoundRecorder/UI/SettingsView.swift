import SwiftUI
import AppKit
import InternalSoundRecorderCore

public struct SettingsView: View {
    @ObservedObject var manager: RecordingManager
    @Environment(\.dismiss) private var dismiss

    public init(manager: RecordingManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recorder Settings")
                    .font(.title3.bold())
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            // Two-Way Meeting Mode (Microphone Input)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Record My Voice (Two-Way Meeting Mode)", isOn: $manager.settings.includeMicrophone)
                    .font(.subheadline.bold())
                    .disabled(manager.status.isRecordingOrPaused)

                Text("When enabled, your microphone is mixed with the internal system audio so both you and the other participants in MS Teams, Zoom, or calls are saved in the same recording.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Capture Scope & App Filtering
            VStack(alignment: .leading, spacing: 6) {
                Text("Capture Scope")
                    .font(.subheadline.bold())

                Picker("Scope", selection: $manager.settings.targetMode) {
                    ForEach(CaptureTargetMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(manager.status.isRecordingOrPaused)

                Text(manager.settings.targetMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if manager.settings.targetMode == .specificApps {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Record only these running apps:")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(manager.meetingDetector.runningApps) { app in
                                    Toggle(isOn: Binding(
                                        get: { manager.settings.targetAppBundleIDs.contains(app.bundleIdentifier) },
                                        set: { isSelected in
                                            if isSelected {
                                                if !manager.settings.targetAppBundleIDs.contains(app.bundleIdentifier) {
                                                    manager.settings.targetAppBundleIDs.append(app.bundleIdentifier)
                                                }
                                            } else {
                                                manager.settings.targetAppBundleIDs.removeAll { $0 == app.bundleIdentifier }
                                            }
                                        }
                                    )) {
                                        Text(app.name)
                                            .font(.caption)
                                    }
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: 90)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .padding(.top, 2)
                }
            }

            Divider()

            // Audio Format Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Audio Container & Codec")
                    .font(.subheadline.bold())

                Picker("Format", selection: $manager.settings.audioFormat) {
                    ForEach(AudioFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(manager.settings.audioFormat.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Stem Mode Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Stem Recording Mode")
                    .font(.subheadline.bold())

                Picker("Stem Mode", selection: $manager.settings.stemMode) {
                    ForEach(StemRecordingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(manager.status.isRecordingOrPaused)

                Text(manager.settings.stemMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Fault Tolerance & Fragment Interval
            if manager.settings.audioFormat == .m4aAAC {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Fault-Tolerant Fragment Interval:")
                            .font(.subheadline.bold())
                        Text(String(format: "%.1f seconds", manager.settings.fragmentIntervalSeconds))
                            .foregroundColor(.accentColor)
                    }

                    Slider(
                        value: $manager.settings.fragmentIntervalSeconds,
                        in: 1.0...5.0,
                        step: 0.5
                    )

                    Text("Audio is committed to disk every \(String(format: "%.1f", manager.settings.fragmentIntervalSeconds))s. If interrupted, recorded data up to the last interval is preserved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
            }

            // Save Directory Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Save Location")
                    .font(.subheadline.bold())

                HStack {
                    Text(manager.settings.saveDirectory.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)

                    Button("Choose...") {
                        selectSaveDirectory()
                    }
                }
            }

            Spacer()
        }
        .padding(18)
        .frame(width: 440, height: 480)
    }

    private func selectSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Output Folder"

        if panel.runModal() == .OK, let selectedURL = panel.url {
            manager.settings.saveDirectory = selectedURL
        }
    }
}
