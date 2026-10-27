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
        .frame(width: 420, height: 380)
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
