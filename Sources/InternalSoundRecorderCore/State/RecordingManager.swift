import Foundation
import Combine
import CoreMedia
import AppKit

public enum RecordingStatus: Equatable, Sendable {
    case idle
    case recording
    case paused
    case recovering
    case stopping
    case error(String)

    public var isRecordingOrPaused: Bool {
        self == .recording || self == .paused || self == .recovering
    }
}

@MainActor
public final class RecordingManager: ObservableObject, AudioCaptureServiceDelegate, SystemMonitorDelegate {
    @Published public private(set) var status: RecordingStatus = .idle
    @Published public private(set) var recordedDuration: TimeInterval = 0
    @Published public private(set) var currentFileSize: Int64 = 0
    @Published public private(set) var audioLevels: AudioLevels = .zero
    @Published public private(set) var currentRecordingURL: URL?
    @Published public private(set) var recentRecordings: [RecordingItem] = []
    @Published public private(set) var activeMarkers: [MarkerItem] = []
    @Published public private(set) var lastDroppedMarker: MarkerItem?
    @Published public private(set) var isTranscribing: Bool = false
    @Published public private(set) var lastTranscriptionError: String? = nil
    @Published public var settings: RecordingSettings = .default

    public let permissionManager = PermissionManager()
    public let meetingDetector = MeetingDetector()
    public let transcriptionService = SpeechTranscriptionService()

    private let captureService = AudioCaptureService()
    private let levelMeter = AudioLevelMeter()
    private let systemMonitor = SystemMonitor()

    private var activeWriter: ResilientAudioWriter?
    private var systemStemWriter: ResilientAudioWriter?
    private var micStemWriter: ResilientAudioWriter?

    private var durationTimer: Timer?
    private var isPaused = false
    private var recordingStartTime: Date?
    private var retryCount = 0
    private let maxRetries = 3

    private let userDefaultsKey = "com.internalsoundrecorder.recent_recordings"

    public init() {
        captureService.delegate = self
        systemMonitor.delegate = self
        loadRecentRecordings()
    }

    // MARK: - Volume Controls

    public func updateVolumes(system: Float? = nil, mic: Float? = nil) {
        if let s = system { settings.systemVolume = s }
        if let m = mic { settings.microphoneVolume = m }
        captureService.setVolumes(system: settings.systemVolume, mic: settings.microphoneVolume)
    }

    // MARK: - Marker / Bookmark Controls

    @discardableResult
    public func addMarker(label: String? = nil) -> MarkerItem {
        let count = activeMarkers.count + 1
        let finalLabel = label ?? "Marker #\(count)"
        let marker = MarkerItem(timestamp: recordedDuration, label: finalLabel)
        activeMarkers.append(marker)
        lastDroppedMarker = marker

        // Auto-clear last dropped marker toast after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.lastDroppedMarker?.id == marker.id {
                self?.lastDroppedMarker = nil
            }
        }
        return marker
    }

    // MARK: - Recording Actions

    public func clearTranscriptionError() {
        lastTranscriptionError = nil
    }

    public func startRecording() async throws {
        guard status == .idle || (caseError(status)) else { return }

        // Verify permission
        if !permissionManager.checkPermission() {
            permissionManager.requestPermission()
            status = .error("Screen & System Audio Recording permission required.")
            return
        }

        // Proactively request speech recognition permission if auto-transcribe is enabled with Apple Speech engine
        if settings.autoTranscribe && settings.transcriptionEngine == .apple && !permissionManager.hasSpeechRecognitionPermission {
            _ = await permissionManager.requestSpeechRecognitionPermission()
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let baseFilename = "SystemRecording_\(timestamp)"
        let outputURL = settings.saveDirectory.appendingPathComponent("\(baseFilename).\(settings.audioFormat.fileExtension)")

        do {
            let writer = try ResilientAudioWriter(
                outputURL: outputURL,
                format: settings.audioFormat,
                sampleRate: settings.sampleRate,
                channels: settings.channelCount,
                fragmentInterval: settings.fragmentIntervalSeconds,
                bitRate: settings.aacBitRate
            )

            // Optional stem writers if separate stems are enabled
            var sysWriter: ResilientAudioWriter? = nil
            var micWriter: ResilientAudioWriter? = nil

            if settings.stemMode == .separateStems {
                let sysURL = settings.saveDirectory.appendingPathComponent("\(baseFilename)_system.\(settings.audioFormat.fileExtension)")
                let mURL = settings.saveDirectory.appendingPathComponent("\(baseFilename)_mic.\(settings.audioFormat.fileExtension)")
                sysWriter = try? ResilientAudioWriter(outputURL: sysURL, format: settings.audioFormat, sampleRate: settings.sampleRate, channels: settings.channelCount)
                micWriter = try? ResilientAudioWriter(outputURL: mURL, format: settings.audioFormat, sampleRate: settings.sampleRate, channels: settings.channelCount)
            }

            self.activeWriter = writer
            self.systemStemWriter = sysWriter
            self.micStemWriter = micWriter
            self.currentRecordingURL = outputURL
            self.recordedDuration = 0
            self.currentFileSize = 0
            self.activeMarkers = []
            self.lastDroppedMarker = nil
            self.isPaused = false
            self.retryCount = 0
            self.recordingStartTime = Date()

            let meter = self.levelMeter

            // Start hardware/system audio capture (with two-way microphone mix if enabled)
            try await captureService.startCapture(
                sampleRate: settings.sampleRate,
                channelCount: settings.channelCount,
                includeMicrophone: settings.includeMicrophone,
                systemVolume: settings.systemVolume,
                microphoneVolume: settings.microphoneVolume,
                targetAppBundleIDs: (settings.targetMode == .specificApps ? settings.targetAppBundleIDs : []),
                onAudioSample: { [weak self, writer, meter] sampleBuffer in
                    writer.append(sampleBuffer)
                    let levels = meter.processSampleBuffer(sampleBuffer)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, self.status == .recording else { return }
                        self.audioLevels = levels
                    }
                },
                onSystemSample: { [sysWriter] buffer in
                    sysWriter?.append(buffer)
                },
                onMicSample: { [micWriter] buffer in
                    micWriter?.append(buffer)
                }
            )

            self.status = .recording
            startDurationTimer()
            systemMonitor.startDiskMonitoring(for: settings.saveDirectory)
        } catch {
            self.activeWriter = nil
            self.systemStemWriter = nil
            self.micStemWriter = nil
            self.status = .error(error.localizedDescription)
            throw error
        }
    }

    public func pauseRecording() {
        guard status == .recording else { return }
        isPaused = true
        status = .paused
        activeWriter?.flush()
        systemStemWriter?.flush()
        micStemWriter?.flush()
    }

    public func resumeRecording() {
        guard status == .paused else { return }
        isPaused = false
        status = .recording
    }

    public func stopRecording() async throws -> URL? {
        guard status.isRecordingOrPaused, let writer = activeWriter else { return nil }

        status = .stopping
        stopDurationTimer()
        systemMonitor.stopDiskMonitoring()
        levelMeter.reset()
        audioLevels = .zero

        // Stop capture stream
        try? await captureService.stopCapture()

        // Gracefully finalize resilient writers
        let finalURL: URL
        do {
            finalURL = try await writer.finish()
        } catch {
            finalURL = writer.outputURL
        }

        if let sysWriter = systemStemWriter {
            _ = try? await sysWriter.finish()
        }
        if let mWriter = micStemWriter {
            _ = try? await mWriter.finish()
        }

        // Export Companion Markers File if markers were dropped
        exportMarkersIfPresent(for: finalURL)

        // Trigger On-Device AI Transcription if enabled
        if settings.autoTranscribe {
            self.isTranscribing = true
            self.lastTranscriptionError = nil
            let capturedMarkers = self.activeMarkers
            let service = self.transcriptionService
            let engine = self.settings.transcriptionEngine
            let whisperModel = self.settings.whisperModel
            let primaryLocale = self.settings.transcriptionPrimaryLocale
            let secondaryLocale = self.settings.transcriptionSecondaryLocale
            let preferOnDevice = self.settings.preferOnDeviceRecognition
            let duration = recordedDuration

            Task {
                do {
                    let result = try await service.transcribe(
                        audioURL: finalURL,
                        engine: engine,
                        primaryLocaleID: primaryLocale,
                        secondaryLocaleID: secondaryLocale,
                        preferOnDevice: preferOnDevice,
                        whisperModel: whisperModel
                    )
                    try service.exportCompanionArtifacts(
                        for: finalURL,
                        result: result,
                        markers: capturedMarkers,
                        audioDuration: duration
                    )
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.isTranscribing = false
                        self.lastTranscriptionError = nil
                        self.loadRecentRecordings()
                        self.objectWillChange.send()
                    }
                } catch {
                    let errorMsg = error.localizedDescription
                    // Even if transcription fails, ALWAYS export meeting notes with markers & metadata!
                    let emptyResult = TranscriptionResult(fullText: "", segments: [])
                    _ = try? service.exportCompanionArtifacts(
                        for: finalURL,
                        result: emptyResult,
                        markers: capturedMarkers,
                        audioDuration: duration
                    )
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.isTranscribing = false
                        self.lastTranscriptionError = errorMsg
                        self.loadRecentRecordings()
                        self.objectWillChange.send()
                    }
                }
            }
        }

        let duration = recordedDuration
        let fileSize = writer.currentFileSize

        let item = RecordingItem(
            url: finalURL,
            createdAt: recordingStartTime ?? Date(),
            duration: duration,
            fileSize: fileSize,
            format: settings.audioFormat
        )
        addRecentRecording(item)

        self.activeWriter = nil
        self.systemStemWriter = nil
        self.micStemWriter = nil
        self.status = .idle
        self.recordedDuration = 0
        self.currentFileSize = 0
        self.currentRecordingURL = nil

        return finalURL
    }

    // MARK: - Marker Export

    private func exportMarkersIfPresent(for audioURL: URL) {
        guard !activeMarkers.isEmpty else { return }

        let baseURL = audioURL.deletingPathExtension()
        let txtURL = baseURL.appendingPathExtension("markers.txt")
        let jsonURL = baseURL.appendingPathExtension("markers.json")

        // 1. Text Summary
        var txtContent = "MacAudioRecorder — Meeting Markers\n"
        txtContent += "Recording: \(audioURL.lastPathComponent)\n"
        txtContent += "Date: \(Date().formatted())\n"
        txtContent += "Total Markers: \(activeMarkers.count)\n"
        txtContent += "----------------------------------------\n\n"
        for m in activeMarkers {
            txtContent += "[\(m.formattedTimestamp)] \(m.label)\n"
        }
        try? txtContent.write(to: txtURL, atomically: true, encoding: .utf8)

        // 2. JSON Data
        if let jsonData = try? JSONEncoder().encode(activeMarkers) {
            try? jsonData.write(to: jsonURL)
        }
    }

    // MARK: - Fault Tolerance & Auto-Recovery

    nonisolated public func audioCaptureDidEncounterError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self = self, self.status.isRecordingOrPaused else { return }

            self.activeWriter?.flush()
            self.systemStemWriter?.flush()
            self.micStemWriter?.flush()

            if self.retryCount < self.maxRetries {
                self.retryCount += 1
                self.status = .recovering

                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let writer = self.activeWriter else { return }
                let meter = self.levelMeter
                let sysWriter = self.systemStemWriter
                let micWriter = self.micStemWriter

                do {
                    try await self.captureService.startCapture(
                        sampleRate: self.settings.sampleRate,
                        channelCount: self.settings.channelCount,
                        includeMicrophone: self.settings.includeMicrophone,
                        systemVolume: self.settings.systemVolume,
                        microphoneVolume: self.settings.microphoneVolume,
                        targetAppBundleIDs: (self.settings.targetMode == .specificApps ? self.settings.targetAppBundleIDs : []),
                        onAudioSample: { [weak self, writer, meter] sampleBuffer in
                            writer.append(sampleBuffer)
                            let levels = meter.processSampleBuffer(sampleBuffer)
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self, self.status == .recording else { return }
                                self.audioLevels = levels
                            }
                        },
                        onSystemSample: { [sysWriter] buffer in
                            sysWriter?.append(buffer)
                        },
                        onMicSample: { [micWriter] buffer in
                            micWriter?.append(buffer)
                        }
                    )
                    self.status = self.isPaused ? .paused : .recording
                } catch {
                    self.audioCaptureDidEncounterError(error)
                }
            } else {
                _ = try? await self.stopRecording()
                self.status = .error("Capture interrupted: \(error.localizedDescription). File saved safely.")
            }
        }
    }

    nonisolated public func audioCaptureDidStop() {
        Task { @MainActor [weak self] in
            self?.activeWriter?.flush()
            self?.systemStemWriter?.flush()
            self?.micStemWriter?.flush()
        }
    }

    nonisolated public func systemWillSleep() {
        Task { @MainActor [weak self] in
            guard let self = self, self.status == .recording else { return }
            self.pauseRecording()
            self.activeWriter?.flush()
            self.systemStemWriter?.flush()
            self.micStemWriter?.flush()
        }
    }

    nonisolated public func systemDidWake() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if self.status == .paused && !self.isPaused {
                self.resumeRecording()
            }
        }
    }

    nonisolated public func lowDiskSpaceDetected(availableBytes: Int64) {
        Task { @MainActor [weak self] in
            guard let self = self, self.status.isRecordingOrPaused else { return }
            _ = try? await self.stopRecording()
            self.status = .error("Stopped recording: Low disk space (< 200MB available). File saved safely.")
        }
    }

    // MARK: - Utilities & Persistence

    private func startDurationTimer() {
        stopDurationTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let writer = self.activeWriter else { return }
                if self.status == .recording {
                    self.recordedDuration = writer.recordedDuration
                    self.currentFileSize = writer.currentFileSize
                }
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func addRecentRecording(_ item: RecordingItem) {
        recentRecordings.insert(item, at: 0)
        if recentRecordings.count > 10 {
            recentRecordings = Array(recentRecordings.prefix(10))
        }
        saveRecentRecordings()
    }

    private func loadRecentRecordings() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let items = try? JSONDecoder().decode([RecordingItem].self, from: data) {
            self.recentRecordings = items
        }
    }

    private func saveRecentRecordings() {
        if let data = try? JSONEncoder().encode(recentRecordings) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    public func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openSaveDirectory() {
        NSWorkspace.shared.open(settings.saveDirectory)
    }

    private func caseError(_ s: RecordingStatus) -> Bool {
        if case .error = s { return true }
        return false
    }
}
