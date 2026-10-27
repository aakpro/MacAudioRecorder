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
    @Published public var settings: RecordingSettings = .default

    public let permissionManager = PermissionManager()

    private let captureService = AudioCaptureService()
    private let levelMeter = AudioLevelMeter()
    private let systemMonitor = SystemMonitor()
    private var activeWriter: ResilientAudioWriter?

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

    // MARK: - Recording Actions

    public func startRecording() async throws {
        guard status == .idle || (caseError(status)) else { return }

        // Verify permission
        if !permissionManager.checkPermission() {
            permissionManager.requestPermission()
            status = .error("Screen & System Audio Recording permission required.")
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "SystemRecording_\(timestamp).\(settings.audioFormat.fileExtension)"
        let outputURL = settings.saveDirectory.appendingPathComponent(filename)

        do {
            let writer = try ResilientAudioWriter(
                outputURL: outputURL,
                format: settings.audioFormat,
                sampleRate: settings.sampleRate,
                channels: settings.channelCount,
                fragmentInterval: settings.fragmentIntervalSeconds,
                bitRate: settings.aacBitRate
            )

            self.activeWriter = writer
            self.currentRecordingURL = outputURL
            self.recordedDuration = 0
            self.currentFileSize = 0
            self.isPaused = false
            self.retryCount = 0
            self.recordingStartTime = Date()

            let meter = self.levelMeter

            // Start hardware/system audio capture (with two-way microphone mix if enabled)
            try await captureService.startCapture(
                sampleRate: settings.sampleRate,
                channelCount: settings.channelCount,
                includeMicrophone: settings.includeMicrophone
            ) { [weak self, writer, meter] sampleBuffer in
                // Write audio off main thread for low latency
                writer.append(sampleBuffer)

                // Compute audio levels for visual feedback
                let levels = meter.processSampleBuffer(sampleBuffer)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.status == .recording else { return }
                    self.audioLevels = levels
                }
            }

            self.status = .recording
            startDurationTimer()
            systemMonitor.startDiskMonitoring(for: settings.saveDirectory)
        } catch {
            self.activeWriter = nil
            self.status = .error(error.localizedDescription)
            throw error
        }
    }

    public func pauseRecording() {
        guard status == .recording else { return }
        isPaused = true
        status = .paused
        activeWriter?.flush()
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

        // Gracefully finalize resilient writer
        let finalURL: URL
        do {
            finalURL = try await writer.finish()
        } catch {
            finalURL = writer.outputURL
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
        self.status = .idle
        self.recordedDuration = 0
        self.currentFileSize = 0
        self.currentRecordingURL = nil

        return finalURL
    }

    // MARK: - Fault Tolerance & Auto-Recovery

    nonisolated public func audioCaptureDidEncounterError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self = self, self.status.isRecordingOrPaused else { return }

            // Immediately flush audio buffers to disk
            self.activeWriter?.flush()

            if self.retryCount < self.maxRetries {
                self.retryCount += 1
                self.status = .recovering

                // Attempt reconnection after 1 second backoff
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let writer = self.activeWriter else { return }
                let meter = self.levelMeter

                do {
                    try await self.captureService.startCapture(
                        sampleRate: self.settings.sampleRate,
                        channelCount: self.settings.channelCount,
                        includeMicrophone: self.settings.includeMicrophone
                    ) { [weak self, writer, meter] sampleBuffer in
                        writer.append(sampleBuffer)
                        let levels = meter.processSampleBuffer(sampleBuffer)
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, self.status == .recording else { return }
                            self.audioLevels = levels
                        }
                    }
                    self.status = self.isPaused ? .paused : .recording
                } catch {
                    self.audioCaptureDidEncounterError(error)
                }
            } else {
                // Auto-save whatever has been captured so far
                _ = try? await self.stopRecording()
                self.status = .error("Capture interrupted: \(error.localizedDescription). File saved safely.")
            }
        }
    }

    nonisolated public func audioCaptureDidStop() {
        Task { @MainActor [weak self] in
            self?.activeWriter?.flush()
        }
    }

    nonisolated public func systemWillSleep() {
        Task { @MainActor [weak self] in
            guard let self = self, self.status == .recording else { return }
            self.pauseRecording()
            self.activeWriter?.flush()
        }
    }

    nonisolated public func systemDidWake() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // When waking, ensure writer is ready and resume if previously recording
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
