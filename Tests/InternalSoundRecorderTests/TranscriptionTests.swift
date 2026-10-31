import XCTest
import WhisperKit
@testable import InternalSoundRecorderCore

final class TranscriptionTests: XCTestCase {

    func testWhisperKitInitialization() async throws {
        let recommended = WhisperKit.recommendedModels().default
        print("Recommended WhisperKit model: \(recommended)")
        XCTAssertFalse(recommended.isEmpty)

        let service = SpeechTranscriptionService()
        let testAudioURL = URL(fileURLWithPath: "/Users/aakpro/Music/InternalSoundRecordings/SystemRecording_2026-10-31T06-41-09Z.m4a")
        if FileManager.default.fileExists(atPath: testAudioURL.path) {
            let result = try await service.transcribe(
                audioURL: testAudioURL,
                engine: .whisper,
                primaryLocaleID: "fa",
                whisperModel: "openai_whisper-tiny"
            )
            print("Whisper fullText count: \(result.fullText.count), segments: \(result.segments.count)")
            XCTAssertFalse(result.fullText.isEmpty)
            XCTAssertFalse(result.segments.isEmpty)

            let markers = [
                MarkerItem(timestamp: 18.82, label: "Marker #1"),
                MarkerItem(timestamp: 73.82, label: "Marker #2"),
                MarkerItem(timestamp: 78.82, label: "Marker #3")
            ]
            try service.exportCompanionArtifacts(
                for: testAudioURL,
                result: result,
                markers: markers,
                audioDuration: 733.0
            )
        }
    }

    func testTranscriptionResultSRTFormatting() {
        let segments = [
            TranscriptSegment(timestamp: 1.5, duration: 2.0, text: "Welcome to the meeting."),
            TranscriptSegment(timestamp: 4.0, duration: 3.5, text: "Let's review the quarterly metrics.")
        ]
        let result = TranscriptionResult(
            fullText: "Welcome to the meeting. Let's review the quarterly metrics.",
            segments: segments
        )

        let srt = result.srtFormat
        XCTAssertTrue(srt.contains("1\n"))
        XCTAssertTrue(srt.contains("00:00:01,500 --> 00:00:03,500"))
        XCTAssertTrue(srt.contains("Welcome to the meeting."))
        XCTAssertTrue(srt.contains("2\n"))
        XCTAssertTrue(srt.contains("00:00:04,000 --> 00:00:07,500"))
    }

    func testWordLevelSegmentsAggregatedIntoSmartSubtitles() {
        // Simulates Apple Speech returning individual single-word tokens
        let words = [
            TranscriptSegment(timestamp: 0.1, duration: 0.2, text: "Welcome"),
            TranscriptSegment(timestamp: 0.3, duration: 0.2, text: "everyone"),
            TranscriptSegment(timestamp: 0.5, duration: 0.2, text: "to"),
            TranscriptSegment(timestamp: 0.7, duration: 0.2, text: "the"),
            TranscriptSegment(timestamp: 0.9, duration: 0.3, text: "meeting."),
            // Long pause > 0.65s (1.2s to 2.2s)
            TranscriptSegment(timestamp: 2.2, duration: 0.3, text: "Let's"),
            TranscriptSegment(timestamp: 2.5, duration: 0.3, text: "start.")
        ]

        let result = TranscriptionResult(
            fullText: "Welcome everyone to the meeting. Let's start.",
            segments: words
        )

        let phrases = result.aggregatedPhrases()
        // Must aggregate into 2 readable phrases separated by sentence ending and acoustic pause!
        XCTAssertEqual(phrases.count, 2)
        XCTAssertEqual(phrases[0].text, "Welcome everyone to the meeting.")
        XCTAssertEqual(phrases[1].text, "Let's start.")

        let srt = result.srtFormat
        XCTAssertTrue(srt.contains("1\n"))
        XCTAssertTrue(srt.contains("Welcome everyone to the meeting."))
        XCTAssertTrue(srt.contains("2\n"))
        XCTAssertTrue(srt.contains("Let's start."))
        // Ensure single-word subtitle spamming does NOT happen
        XCTAssertFalse(srt.contains("3\n"))
    }

    func testMarkdownMeetingNotesWithMarkers() {
        let markers = [
            MarkerItem(timestamp: 10, label: "Quarterly Target"),
            MarkerItem(timestamp: 60, label: "Decision reached")
        ]
        let segments = [
            TranscriptSegment(timestamp: 5, duration: 15, text: "Discussion about our target for Q4."),
            TranscriptSegment(timestamp: 55, duration: 10, text: "Everyone agrees to proceed.")
        ]
        let result = TranscriptionResult(fullText: "All text", segments: segments)

        let notes = result.markdownMeetingNotes(
            recordingName: "Quarterly_Review.m4a",
            markers: markers,
            audioDuration: 75.0,
            languageName: "English (US)"
        )

        XCTAssertTrue(notes.contains("# Meeting Notes — Quarterly_Review.m4a"))
        XCTAssertTrue(notes.contains("## 📍 Key Discussion Markers"))
        XCTAssertTrue(notes.contains("**[00:10]** Quarterly Target"))
        XCTAssertTrue(notes.contains("**[01:00]** Decision reached"))
        XCTAssertTrue(notes.contains("## 📝 Full Meeting Transcript"))
        XCTAssertTrue(notes.contains("Discussion about our target for Q4."))
        XCTAssertTrue(notes.contains("**Duration**: 1m 15s"))
        XCTAssertTrue(notes.contains("**Language**: English (US)"))
    }

    func testMeetingNotesResilienceWhenAudioIsSilent() {
        let markers = [
            MarkerItem(timestamp: 5, label: "Silent Bookmark")
        ]
        let result = TranscriptionResult(fullText: "", segments: [])
        let notes = result.markdownMeetingNotes(recordingName: "Silent_Call.m4a", markers: markers)

        // Notes must be exported without crashing even if speech is completely silent!
        XCTAssertTrue(notes.contains("# Meeting Notes — Silent_Call.m4a"))
        XCTAssertTrue(notes.contains("**[00:05]** Silent Bookmark"))
        XCTAssertTrue(notes.contains("No spoken dialogue was detected"))
    }

    func testSpeechTranscriptionServiceInitializationAndLocales() {
        let service = SpeechTranscriptionService()
        XCTAssertNotNil(service)

        let supported = SpeechTranscriptionService.supportedLanguages()
        XCTAssertFalse(supported.isEmpty)

        let autoResolved = SpeechTranscriptionService.resolveLocaleIdentifier("auto")
        XCTAssertFalse(autoResolved.isEmpty)

        // Verify Persian detection
        let isPersian = SpeechTranscriptionService.isPersianOrUnsupportedLocale(Locale(identifier: "fa_IR"))
        XCTAssertTrue(isPersian)

        let isEnglish = SpeechTranscriptionService.isPersianOrUnsupportedLocale(Locale(identifier: "en_US"))
        XCTAssertFalse(isEnglish)
    }

    func testExportCompanionArtifactsStandardFileNaming() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ISR_ArtifactTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let audioURL = tempDir.appendingPathComponent("Meeting_2026-10-29.m4a")
        try Data("mock audio data".utf8).write(to: audioURL)

        let service = SpeechTranscriptionService()
        let segments = [
            TranscriptSegment(timestamp: 0.5, duration: 2.0, text: "Good morning team.")
        ]
        let result = TranscriptionResult(fullText: "Good morning team.", segments: segments)

        let (srtURL, notesURL, txtURL) = try service.exportCompanionArtifacts(
            for: audioURL,
            result: result,
            markers: [MarkerItem(timestamp: 1.0, label: "Introduction")],
            audioDuration: 2.5
        )

        // Check standard naming for media player auto-loading
        XCTAssertNotNil(srtURL)
        XCTAssertEqual(srtURL?.lastPathComponent, "Meeting_2026-10-29.srt")
        XCTAssertEqual(notesURL.lastPathComponent, "Meeting_2026-10-29_Notes.md")
        XCTAssertEqual(txtURL?.lastPathComponent, "Meeting_2026-10-29_Transcript.txt")

        // Verify file contents exist on disk
        XCTAssertTrue(FileManager.default.fileExists(atPath: srtURL!.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: notesURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: txtURL!.path))

        let notesContent = try String(contentsOf: notesURL)
        XCTAssertTrue(notesContent.contains("Introduction"))
        XCTAssertTrue(notesContent.contains("Good morning team."))
    }
}
