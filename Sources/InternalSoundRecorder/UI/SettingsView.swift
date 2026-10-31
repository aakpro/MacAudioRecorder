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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recorder Settings")
                    .font(.title3.bold())
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Two-Way Meeting Mode (Microphone Input)
                    microphoneSection

                    Divider()

                    // Multilingual Transcription & Notes
                    transcriptionSection

                    Divider()

                    // Capture Scope & App Filtering
                    captureScopeSection

                    Divider()

                    // Audio Format Picker
                    audioFormatSection

                    Divider()

                    // Stem Mode Picker
                    stemModeSection

                    Divider()

                    // Fault Tolerance & Fragment Interval
                    if manager.settings.audioFormat == .m4aAAC {
                        faultToleranceSection
                        Divider()
                    }

                    // Save Directory Picker
                    saveLocationSection
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 540)
    }

    // MARK: - Sections

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Record My Voice (Two-Way Meeting Mode)", isOn: $manager.settings.includeMicrophone)
                .font(.subheadline.bold())
                .disabled(manager.status.isRecordingOrPaused)

            Text("When enabled, your microphone is mixed with the internal system audio so both you and the other participants in MS Teams, Zoom, or calls are saved in the same recording.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Generate Meeting Notes & Subtitles (On-Device AI)", isOn: $manager.settings.autoTranscribe)
                .font(.subheadline.bold())

            Text("Automatically generates paired subtitles (.srt), plain text transcript (.txt), and structured Markdown notes (.md) alongside your audio.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if manager.settings.autoTranscribe {
                VStack(alignment: .leading, spacing: 8) {
                    // Transcription Engine Selector
                    HStack {
                        Text("AI Engine:")
                            .font(.caption.bold())
                            .frame(width: 140, alignment: .leading)

                        Picker("", selection: $manager.settings.transcriptionEngine) {
                            ForEach(TranscriptionEngine.allCases, id: \.self) { engine in
                                Text(engine.displayName).tag(engine)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if manager.settings.transcriptionEngine == .whisper {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                                .font(.caption)
                            Text("WhisperKit runs directly on Apple Silicon Neural Engine offline. Natively transcribes Persian (Farsi), English, German, and 99+ languages.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.purple.opacity(0.12))
                        .cornerRadius(6)

                        HStack {
                            Text("Whisper Model:")
                                .font(.caption.bold())
                                .frame(width: 140, alignment: .leading)

                            Picker("", selection: $manager.settings.whisperModel) {
                                Text("Base (~140MB - Balanced & Accurate)").tag("openai_whisper-base")
                                Text("Tiny (~75MB - Fastest)").tag("openai_whisper-tiny")
                                Text("Small (~400MB - High Precision)").tag("openai_whisper-small")
                            }
                            .pickerStyle(.menu)
                        }
                    } else {
                        // Speech Recognition Permission Check (Apple Engine only)
                        if !manager.permissionManager.hasSpeechRecognitionPermission {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                                Text("Speech Recognition permission required.")
                                    .font(.caption2.bold())
                                Spacer()
                                Button("Authorize") {
                                    manager.permissionManager.requestSpeechRecognitionPermission()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .padding(6)
                            .background(Color.yellow.opacity(0.12))
                            .cornerRadius(6)
                        }

                        // Unsupported System Locale Notice (e.g. Persian)
                        if SpeechTranscriptionService.isPersianOrUnsupportedLocale() {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("Note: Persian (Farsi) is not natively supported by Apple's Speech Framework. Switch to Whisper AI above or select a supported meeting language.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(6)
                        }
                    }

                    // Primary Language Picker
                    HStack {
                        Text("Primary Language:")
                            .font(.caption.bold())
                            .frame(width: 140, alignment: .leading)

                        Picker("", selection: $manager.settings.transcriptionPrimaryLocale) {
                            Text("Auto-detect / System Locale").tag("auto")
                            Divider()
                            ForEach(SpeechTranscriptionService.supportedLanguages()) { lang in
                                Text(lang.displayName).tag(lang.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Secondary Language Picker (for bilingual/multilingual meetings)
                    HStack {
                        Text("Secondary Language:")
                            .font(.caption.bold())
                            .frame(width: 140, alignment: .leading)

                        Picker("", selection: Binding(
                            get: { manager.settings.transcriptionSecondaryLocale ?? "none" },
                            set: { manager.settings.transcriptionSecondaryLocale = ($0 == "none" ? nil : $0) }
                        )) {
                            Text("None (Single Language)").tag("none")
                            Divider()
                            ForEach(SpeechTranscriptionService.supportedLanguages()) { lang in
                                Text(lang.displayName).tag(lang.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Prefer On-Device Toggle
                    Toggle("Prefer On-Device Processing (Apple Neural Engine)", isOn: $manager.settings.preferOnDeviceRecognition)
                        .font(.caption)

                    Text("Processes speech entirely on your Mac. If offline assets are missing for the language, seamlessly falls back to standard recognition.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(8)
            }
        }
    }

    private var captureScopeSection: some View {
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
    }

    private var audioFormatSection: some View {
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
    }

    private var stemModeSection: some View {
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
    }

    private var faultToleranceSection: some View {
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
    }

    private var saveLocationSection: some View {
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
