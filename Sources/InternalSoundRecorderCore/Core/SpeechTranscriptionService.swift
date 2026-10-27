import Foundation
import Speech
import AVFoundation

public enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case notAuthorized
    case noTranscriptionResult
    case fileNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Apple Speech Recognizer is not available for the current system locale."
        case .notAuthorized:
            return "Speech Recognition permission not granted."
        case .noTranscriptionResult:
            return "No transcription text was recognized in the audio file."
        case .fileNotFound(let url):
            return "Audio file not found at: \(url.path)"
        }
    }
}

public final class SpeechTranscriptionService: @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer?

    public init(locale: Locale = Locale.current) {
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    public static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    /// Transcribes an audio file on-device into full text and timestamped segments
    public func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.fileNotFound(audioURL)
        }

        guard let recognizer = self.recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus != .authorized {
            let granted = await Self.requestAuthorization()
            guard granted else { throw TranscriptionError.notAuthorized }
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let finalResult = result, finalResult.isFinal else { return }

                if !hasResumed {
                    hasResumed = true
                    let best = finalResult.bestTranscription
                    let segments = best.segments.map { s in
                        TranscriptSegment(
                            timestamp: s.timestamp,
                            duration: s.duration,
                            text: s.substring
                        )
                    }
                    let res = TranscriptionResult(
                        fullText: best.formattedString,
                        segments: segments
                    )
                    continuation.resume(returning: res)
                }
            }
        }
    }

    /// Saves companion files (.txt, .srt, .md) alongside the audio recording
    @discardableResult
    public func exportCompanionArtifacts(
        for audioURL: URL,
        result: TranscriptionResult,
        markers: [MarkerItem] = []
    ) throws -> (txtURL: URL, srtURL: URL, mdURL: URL) {
        let baseURL = audioURL.deletingPathExtension()
        let txtURL = baseURL.appendingPathExtension("transcript.txt")
        let srtURL = baseURL.appendingPathExtension("transcript.srt")
        let mdURL = baseURL.appendingPathExtension("meeting_notes.md")

        try result.fullText.write(to: txtURL, atomically: true, encoding: .utf8)
        try result.srtFormat.write(to: srtURL, atomically: true, encoding: .utf8)

        let notes = result.markdownMeetingNotes(recordingName: audioURL.lastPathComponent, markers: markers)
        try notes.write(to: mdURL, atomically: true, encoding: .utf8)

        return (txtURL, srtURL, mdURL)
    }
}
