import XCTest
@testable import InternalSoundRecorderCore

final class TranscriptionTests: XCTestCase {

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

        let notes = result.markdownMeetingNotes(recordingName: "Quarterly_Review.m4a", markers: markers)

        XCTAssertTrue(notes.contains("# Meeting Notes — Quarterly_Review.m4a"))
        XCTAssertTrue(notes.contains("## 📍 Key Discussion Markers"))
        XCTAssertTrue(notes.contains("**[00:10]** Quarterly Target"))
        XCTAssertTrue(notes.contains("**[01:00]** Decision reached"))
        XCTAssertTrue(notes.contains("## 📝 Full Transcript"))
        XCTAssertTrue(notes.contains("Discussion about our target for Q4."))
    }

    func testSpeechTranscriptionServiceInitialization() {
        let service = SpeechTranscriptionService()
        // Availability will reflect the system locale support
        XCTAssertNotNil(service)
    }
}
