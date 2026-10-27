import XCTest
@testable import InternalSoundRecorderCore

final class RecordingSessionTests: XCTestCase {

    func testRecordingItemFormatting() {
        let item1 = RecordingItem(
            url: URL(fileURLWithPath: "/tmp/sample.m4a"),
            createdAt: Date(),
            duration: 65, // 1 min 5 sec
            fileSize: 1024 * 1024 * 5, // 5 MB
            format: .m4aAAC
        )

        XCTAssertEqual(item1.filename, "sample.m4a")
        XCTAssertEqual(item1.formattedDuration, "01:05")
        XCTAssertTrue(item1.formattedSize.contains("MB") || item1.formattedSize.contains("5"))

        let item2 = RecordingItem(
            url: URL(fileURLWithPath: "/tmp/long.m4a"),
            createdAt: Date(),
            duration: 3665, // 1 hour 1 min 5 sec
            fileSize: 1024 * 500,
            format: .m4aAAC
        )

        XCTAssertEqual(item2.formattedDuration, "01:01:05")
    }

    func testRecordingSettingsDefaultValues() {
        let settings = RecordingSettings.default
        XCTAssertEqual(settings.sampleRate, 48000.0)
        XCTAssertEqual(settings.channelCount, 2)
        XCTAssertEqual(settings.audioFormat, .m4aAAC)
        XCTAssertEqual(settings.fragmentIntervalSeconds, 2.0)
        XCTAssertEqual(settings.aacBitRate, 256000)
        XCTAssertTrue(settings.saveDirectory.path.contains("InternalSoundRecordings"))
    }

    func testRecordingStatusProperties() {
        XCTAssertFalse(RecordingStatus.idle.isRecordingOrPaused)
        XCTAssertTrue(RecordingStatus.recording.isRecordingOrPaused)
        XCTAssertTrue(RecordingStatus.paused.isRecordingOrPaused)
        XCTAssertTrue(RecordingStatus.recovering.isRecordingOrPaused)
        XCTAssertFalse(RecordingStatus.stopping.isRecordingOrPaused)
        XCTAssertFalse(RecordingStatus.error("Something went wrong").isRecordingOrPaused)
    }
}
