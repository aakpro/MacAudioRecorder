import Foundation
@preconcurrency import Speech
import AVFoundation
@preconcurrency import WhisperKit

private final class RecognitionContext: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false
    private var task: SFSpeechRecognitionTask?
    private var latestResult: SFSpeechRecognitionResult?

    func setTask(_ t: SFSpeechRecognitionTask) {
        lock.lock()
        defer { lock.unlock() }
        self.task = t
    }

    func setLatestResult(_ r: SFSpeechRecognitionResult) {
        lock.lock()
        defer { lock.unlock() }
        self.latestResult = r
    }

    func resumeOnce(action: (SFSpeechRecognitionTask?, SFSpeechRecognitionResult?) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        action(task, latestResult)
    }
}

public struct SupportedLanguage: Identifiable, Sendable, Hashable {
    public let id: String // e.g. "en-US", "de-DE", "fr-FR"
    public let displayName: String // e.g. "English (United States)"

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public enum TranscriptionError: LocalizedError {
    case recognizerUnavailable(String)
    case notAuthorized
    case noTranscriptionResult
    case fileNotFound(URL)
    case unsupportedLanguage(String)

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable(let loc):
            return "Apple Speech Recognizer is not available for locale '\(loc)'."
        case .notAuthorized:
            return "Speech Recognition permission not granted in macOS Privacy & Security."
        case .noTranscriptionResult:
            return "No transcription text was recognized in the audio file."
        case .fileNotFound(let url):
            return "Audio file not found at: \(url.path)"
        case .unsupportedLanguage(let lang):
            return "Language '\(lang)' is not natively supported by Apple Speech Engine."
        }
    }
}

public final class SpeechTranscriptionService: @unchecked Sendable {

    public init() {}

    // MARK: - Supported Locales Discovery

    /// Returns all locales currently supported by Apple's Speech Recognizer on this Mac,
    /// sorted alphabetically with human-readable localized language names.
    public static func supportedLanguages() -> [SupportedLanguage] {
        let locales = SFSpeechRecognizer.supportedLocales()
        var items: [SupportedLanguage] = []

        for loc in locales {
            let identifier = loc.identifier
            let name = Locale.current.localizedString(forIdentifier: identifier)
                ?? loc.localizedString(forIdentifier: identifier)
                ?? identifier
            items.append(SupportedLanguage(id: identifier, displayName: name))
        }

        return items.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Resolves the best available locale identifier given a preferred ID or "auto"
    public static func resolveLocaleIdentifier(_ preferred: String) -> String {
        let supported = SFSpeechRecognizer.supportedLocales().map { $0.identifier }

        if preferred != "auto" && supported.contains(preferred) {
            return preferred
        }

        // Try exact match with current system locale
        let sysLocaleID = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        if supported.contains(sysLocaleID) {
            return sysLocaleID
        }

        // Try matching language prefix (e.g. "en" -> "en-US", "de" -> "de-DE")
        let langPrefix = Locale.current.language.languageCode?.identifier ?? "en"
        if let match = supported.first(where: { $0.hasPrefix("\(langPrefix)-") }) {
            return match
        }

        // Default fallback
        return "en-US"
    }

    /// Checks if the user's system locale is Persian (Farsi) or another unsupported locale
    public static func isPersianOrUnsupportedLocale(_ locale: Locale = .current) -> Bool {
        let code = locale.language.languageCode?.identifier.lowercased() ?? ""
        if code == "fa" || code == "pes" || code == "per" {
            return true
        }
        let sysID = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let supported = SFSpeechRecognizer.supportedLocales().map { $0.identifier }
        return !supported.contains(sysID) && !supported.contains { $0.hasPrefix("\(code)-") }
    }

    // MARK: - Permissions

    public static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - WhisperKit Engine

    private final class WhisperCache: @unchecked Sendable {
        static let shared = WhisperCache()
        private let queue = DispatchQueue(label: "com.internalsoundrecorder.whispercache")
        private var kit: WhisperKit?
        private var model: String?

        func getExisting(model: String) -> WhisperKit? {
            queue.sync {
                if let existing = kit, self.model == model {
                    return existing
                }
                return nil
            }
        }

        func store(kit: WhisperKit, model: String) {
            queue.sync {
                self.kit = kit
                self.model = model
            }
        }
    }

    public static func getWhisperKit(model: String = "openai_whisper-base") async throws -> WhisperKit {
        if let existing = WhisperCache.shared.getExisting(model: model) {
            return existing
        }
        let pipe = try await WhisperKit(model: model)
        WhisperCache.shared.store(kit: pipe, model: model)
        return pipe
    }

    public func transcribeWithWhisper(
        audioURL: URL,
        model: String = "openai_whisper-base",
        targetLanguage: String? = nil
    ) async throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.fileNotFound(audioURL)
        }

        let pipe = try await Self.getWhisperKit(model: model)
        var decodeOptions = DecodingOptions()
        if let lang = targetLanguage, !lang.isEmpty, lang != "auto" {
            decodeOptions.language = lang.components(separatedBy: "-").first ?? lang
        } else if Self.isPersianOrUnsupportedLocale() {
            decodeOptions.language = "fa"
        } else {
            decodeOptions.detectLanguage = true
        }
        decodeOptions.skipSpecialTokens = true
        decodeOptions.wordTimestamps = true

        let results = try await pipe.transcribe(audioPath: audioURL.path, decodeOptions: decodeOptions)
        var fullTextParts: [String] = []
        var allSegments: [TranscriptSegment] = []
        var languages = Set<String>()

        for res in results {
            let cleanedResText = res.text.replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedResText.isEmpty {
                fullTextParts.append(cleanedResText)
            }
            if !res.language.isEmpty {
                languages.insert(res.language)
            }
            for seg in res.segments {
                let cleanedSeg = seg.text.replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedSeg.isEmpty else { continue }
                let duration = max(0.1, Double(seg.end - seg.start))
                allSegments.append(
                    TranscriptSegment(
                        timestamp: Double(seg.start),
                        duration: duration,
                        text: cleanedSeg,
                        confidence: 1.0 - seg.noSpeechProb,
                        languageCode: res.language
                    )
                )
            }
        }

        return TranscriptionResult(
            fullText: fullTextParts.joined(separator: "\n\n"),
            segments: allSegments,
            detectedLanguages: Array(languages)
        )
    }

    // MARK: - Core Transcription Engine

    /// Transcribes an audio file into timestamped phrases, sentences, and structured notes.
    /// Supports Whisper AI (Neural Engine / Persian & Multilingual) and Apple Speech with graceful fallback.
    public func transcribe(
        audioURL: URL,
        engine: TranscriptionEngine = .whisper,
        primaryLocaleID: String = "auto",
        secondaryLocaleID: String? = nil,
        preferOnDevice: Bool = true,
        whisperModel: String = "openai_whisper-base"
    ) async throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.fileNotFound(audioURL)
        }

        if engine == .whisper {
            do {
                return try await transcribeWithWhisper(
                    audioURL: audioURL,
                    model: whisperModel,
                    targetLanguage: primaryLocaleID
                )
            } catch {
                // If WhisperKit encounters an issue, fallback to Apple Speech
                return try await transcribeWithAppleSpeech(
                    audioURL: audioURL,
                    primaryLocaleID: primaryLocaleID,
                    secondaryLocaleID: secondaryLocaleID,
                    preferOnDevice: preferOnDevice
                )
            }
        } else {
            return try await transcribeWithAppleSpeech(
                audioURL: audioURL,
                primaryLocaleID: primaryLocaleID,
                secondaryLocaleID: secondaryLocaleID,
                preferOnDevice: preferOnDevice
            )
        }
    }

    public func transcribeWithAppleSpeech(
        audioURL: URL,
        primaryLocaleID: String = "auto",
        secondaryLocaleID: String? = nil,
        preferOnDevice: Bool = true
    ) async throws -> TranscriptionResult {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.fileNotFound(audioURL)
        }

        // Check or request speech recognition permission
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus != .authorized {
            let granted = await Self.requestAuthorization()
            guard granted else { throw TranscriptionError.notAuthorized }
        }

        let resolvedPrimary = Self.resolveLocaleIdentifier(primaryLocaleID)
        guard let primaryRecognizer = SFSpeechRecognizer(locale: Locale(identifier: resolvedPrimary)),
              primaryRecognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable(resolvedPrimary)
        }

        // Execute primary recognition pass
        do {
            let result = try await executeRecognitionTask(
                audioURL: audioURL,
                recognizer: primaryRecognizer,
                preferOnDevice: preferOnDevice
            )

            // If primary pass produced substantial text, return result
            if !result.segments.isEmpty {
                return result
            }

            // If primary yielded empty text and a secondary locale is configured, attempt secondary pass
            if let secID = secondaryLocaleID, !secID.isEmpty, secID != "none" && secID != resolvedPrimary {
                let resolvedSec = Self.resolveLocaleIdentifier(secID)
                if let secRecognizer = SFSpeechRecognizer(locale: Locale(identifier: resolvedSec)), secRecognizer.isAvailable {
                    let secResult = try? await executeRecognitionTask(
                        audioURL: audioURL,
                        recognizer: secRecognizer,
                        preferOnDevice: preferOnDevice
                    )
                    if let s = secResult, !s.segments.isEmpty {
                        return s
                    }
                }
            }

            return result
        } catch {
            // Handle silence or no speech detected (kAFAssistantErrorDomain Code=1110)
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                return TranscriptionResult(fullText: "", segments: [], detectedLanguages: [resolvedPrimary])
            }
            throw error
        }
    }

    private func executeRecognitionTask(
        audioURL: URL,
        recognizer: SFSpeechRecognizer,
        preferOnDevice: Bool
    ) async throws -> TranscriptionResult {
        if preferOnDevice && recognizer.supportsOnDeviceRecognition {
            do {
                return try await performSingleRecognition(
                    audioURL: audioURL,
                    recognizer: recognizer,
                    requireOnDevice: true
                )
            } catch {
                // If on-device recognition fails for ANY reason (model asset missing, offline engine error, etc.),
                // automatically fall back to standard recognition so the user always gets their transcript!
                return try await performSingleRecognition(
                    audioURL: audioURL,
                    recognizer: recognizer,
                    requireOnDevice: false
                )
            }
        } else {
            return try await performSingleRecognition(
                audioURL: audioURL,
                recognizer: recognizer,
                requireOnDevice: false
            )
        }
    }

    private func performSingleRecognition(
        audioURL: URL,
        recognizer: SFSpeechRecognizer,
        requireOnDevice: Bool
    ) async throws -> TranscriptionResult {
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = requireOnDevice

        return try await withCheckedThrowingContinuation { continuation in
            let context = RecognitionContext()
            let localeID = recognizer.locale.identifier

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let r = result {
                    context.setLatestResult(r)
                }

                if let error = error {
                    context.resumeOnce { _, savedResult in
                        // If we already captured valid speech transcription segments before the error/EOF,
                        // return what was captured rather than discarding the transcript!
                        if let best = savedResult?.bestTranscription, !best.segments.isEmpty {
                            let segments = best.segments.map { s in
                                TranscriptSegment(
                                    timestamp: s.timestamp,
                                    duration: s.duration,
                                    text: s.substring,
                                    confidence: s.confidence,
                                    languageCode: localeID
                                )
                            }
                            let res = TranscriptionResult(
                                fullText: best.formattedString,
                                segments: segments,
                                detectedLanguages: [localeID]
                            )
                            continuation.resume(returning: res)
                            return
                        }

                        let nsErr = error as NSError
                        // Silence or no speech detected (kAFAssistantErrorDomain Code=1110)
                        if nsErr.domain == "kAFAssistantErrorDomain" && nsErr.code == 1110 {
                            continuation.resume(returning: TranscriptionResult(fullText: "", segments: [], detectedLanguages: [localeID]))
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                    return
                }

                guard let finalResult = result, finalResult.isFinal else { return }

                context.resumeOnce { _, _ in
                    let best = finalResult.bestTranscription
                    let segments = best.segments.map { s in
                        TranscriptSegment(
                            timestamp: s.timestamp,
                            duration: s.duration,
                            text: s.substring,
                            confidence: s.confidence,
                            languageCode: localeID
                        )
                    }
                    let res = TranscriptionResult(
                        fullText: best.formattedString,
                        segments: segments,
                        detectedLanguages: [localeID]
                    )
                    continuation.resume(returning: res)
                }
            }

            context.setTask(task)

            // Safety timeout: If recognition takes longer than 90 seconds without callback, cancel safely
            DispatchQueue.global().asyncAfter(deadline: .now() + 90.0) {
                context.resumeOnce { currentTask, savedResult in
                    currentTask?.cancel()

                    if let best = savedResult?.bestTranscription, !best.segments.isEmpty {
                        let segments = best.segments.map { s in
                            TranscriptSegment(
                                timestamp: s.timestamp,
                                duration: s.duration,
                                text: s.substring,
                                confidence: s.confidence,
                                languageCode: localeID
                            )
                        }
                        continuation.resume(returning: TranscriptionResult(
                            fullText: best.formattedString,
                            segments: segments,
                            detectedLanguages: [localeID]
                        ))
                    } else {
                        continuation.resume(returning: TranscriptionResult(fullText: "", segments: [], detectedLanguages: [localeID]))
                    }
                }
            }
        }
    }

    // MARK: - Companion Artifact Export

    /// Saves companion files (.srt, _Notes.md, _Transcript.txt) alongside the audio recording.
    /// Standardized for auto-loading in media players (VLC, QuickTime, IINA).
    @discardableResult
    public func exportCompanionArtifacts(
        for audioURL: URL,
        result: TranscriptionResult,
        markers: [MarkerItem] = [],
        audioDuration: TimeInterval? = nil
    ) throws -> (srtURL: URL?, notesURL: URL, transcriptURL: URL?) {
        let parentDir = audioURL.deletingLastPathComponent()
        let baseFilename = audioURL.deletingPathExtension().lastPathComponent

        // 1. Subtitle File: [BaseName].srt (exact same basename for auto-loading in players)
        var finalSrtURL: URL? = nil
        let srtURL = parentDir.appendingPathComponent("\(baseFilename).srt")
        if !result.segments.isEmpty || !result.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let srtContent = result.srtFormat
            if !srtContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try srtContent.write(to: srtURL, atomically: true, encoding: .utf8)
                finalSrtURL = srtURL
            }
        }

        // 2. Plain Text Transcript: [BaseName]_Transcript.txt
        var finalTxtURL: URL? = nil
        let txtURL = parentDir.appendingPathComponent("\(baseFilename)_Transcript.txt")
        if !result.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try result.fullText.write(to: txtURL, atomically: true, encoding: .utf8)
            finalTxtURL = txtURL
        }

        // 3. Structured Markdown Meeting Notes: [BaseName]_Notes.md
        // ALWAYS generated even if speech recognition is empty, ensuring markers & metadata are preserved!
        let notesURL = parentDir.appendingPathComponent("\(baseFilename)_Notes.md")
        let langName = result.detectedLanguages.first.flatMap { Locale.current.localizedString(forIdentifier: $0) }
        let notesContent = result.markdownMeetingNotes(
            recordingName: audioURL.lastPathComponent,
            markers: markers,
            audioDuration: audioDuration,
            languageName: langName
        )
        try notesContent.write(to: notesURL, atomically: true, encoding: .utf8)

        return (finalSrtURL, notesURL, finalTxtURL)
    }
}
