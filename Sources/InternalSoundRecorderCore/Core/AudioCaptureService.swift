import Foundation
import ScreenCaptureKit
import CoreMedia
import os

public protocol AudioCaptureServiceDelegate: AnyObject, Sendable {
    func audioCaptureDidEncounterError(_ error: Error)
    func audioCaptureDidStop()
}

public final class AudioCaptureService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public weak var delegate: AudioCaptureServiceDelegate?

    private var stream: SCStream?
    private let audioProcessingQueue = DispatchQueue(label: "com.internalsoundrecorder.audioprocessing", qos: .userInteractive)
    public let audioMixer = AudioMixer()

    private struct State {
        var isCapturing = false
        var isMicrophoneEnabled = false
        var onAudioSample: (@Sendable (CMSampleBuffer) -> Void)?
        var onSystemSample: (@Sendable (CMSampleBuffer) -> Void)?
        var onMicSample: (@Sendable (CMSampleBuffer) -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public var isCapturing: Bool {
        state.withLock { $0.isCapturing }
    }

    public override init() {
        super.init()
    }

    public func setVolumes(system: Float, mic: Float) {
        audioMixer.setVolumes(system: system, mic: mic)
    }

    /// Starts capturing internal system audio (and optional microphone) across whatever output route is active
    public func startCapture(
        sampleRate: Double = 48000.0,
        channelCount: Int = 2,
        includeMicrophone: Bool = true,
        systemVolume: Float = 1.0,
        microphoneVolume: Float = 1.0,
        onAudioSample: @escaping @Sendable (CMSampleBuffer) -> Void,
        onSystemSample: (@Sendable (CMSampleBuffer) -> Void)? = nil,
        onMicSample: (@Sendable (CMSampleBuffer) -> Void)? = nil
    ) async throws {
        let alreadyCapturing = state.withLock { state -> Bool in
            if state.isCapturing { return true }
            state.onAudioSample = onAudioSample
            state.onSystemSample = onSystemSample
            state.onMicSample = onMicSample
            state.isMicrophoneEnabled = includeMicrophone
            return false
        }
        guard !alreadyCapturing else { return }

        audioMixer.reset()
        audioMixer.setVolumes(system: systemVolume, mic: microphoneVolume)

        // 1. Fetch available displays via SCShareableContent
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(
                domain: "InternalSoundRecorder",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "No active display found for ScreenCaptureKit audio tap."]
            )
        }

        // 2. Configure content filter (captures system output, excludes nothing except our own app)
        let filter = SCContentFilter(display: display, excludingWindows: [])

        // 3. Configure audio capture parameters
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = Int(sampleRate)
        configuration.channelCount = channelCount

        // Minimal video footprint (audio capture requires an active stream)
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 5

        // Two-way meeting mode: capture microphone input simultaneously
        if #available(macOS 15.0, *) {
            configuration.captureMicrophone = includeMicrophone
        }

        // 4. Create SCStream and register audio outputs
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioProcessingQueue)

        if #available(macOS 15.0, *) {
            if includeMicrophone {
                try newStream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: audioProcessingQueue)
            }
        }

        // 5. Start audio stream capture
        try await newStream.startCapture()

        self.stream = newStream
        state.withLock { $0.isCapturing = true }
    }

    /// Stops audio capture and frees ScreenCaptureKit resources
    public func stopCapture() async throws {
        let currentStream = self.stream
        self.stream = nil

        let wasCapturing = state.withLock { state -> Bool in
            let was = state.isCapturing
            state.isCapturing = false
            state.onAudioSample = nil
            state.onSystemSample = nil
            state.onMicSample = nil
            return was
        }

        guard wasCapturing, let activeStream = currentStream else {
            return
        }

        try await activeStream.stopCapture()
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if #available(macOS 15.0, *) {
            if type == .microphone {
                let micHandler = state.withLock { $0.onMicSample }
                micHandler?(sampleBuffer)
                audioMixer.ingestMicrophoneBuffer(sampleBuffer)
                return
            }
        }

        guard type == .audio else { return }

        let (handler, sysHandler, micEnabled) = state.withLock {
            ($0.onAudioSample, $0.onSystemSample, $0.isMicrophoneEnabled)
        }
        guard let outputHandler = handler else { return }

        // If isolated system stem is needed, forward clean buffer
        sysHandler?(sampleBuffer)

        if micEnabled {
            let mixed = audioMixer.mixSystemAudioBuffer(sampleBuffer)
            outputHandler(mixed)
        } else {
            outputHandler(sampleBuffer)
        }
    }

    // MARK: - SCStreamDelegate (Fault-tolerance & Route change detection)

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        state.withLock {
            $0.isCapturing = false
        }

        delegate?.audioCaptureDidEncounterError(error)
    }
}
