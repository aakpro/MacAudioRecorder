import XCTest
@testable import InternalSoundRecorderCore

final class MeetingDetectorTests: XCTestCase {

    func testTargetAppInfoInitialization() {
        let app = TargetAppInfo(name: "Microsoft Teams", bundleIdentifier: "com.microsoft.teams2", processID: 1234)
        XCTAssertEqual(app.id, "com.microsoft.teams2")
        XCTAssertEqual(app.name, "Microsoft Teams")
        XCTAssertEqual(app.processID, 1234)
    }

    func testCaptureTargetModeSettings() {
        var settings = RecordingSettings.default
        XCTAssertEqual(settings.targetMode, .allSystem)
        XCTAssertTrue(settings.targetAppBundleIDs.isEmpty)

        settings.targetMode = .specificApps
        settings.targetAppBundleIDs = ["com.microsoft.teams2", "us.zoom.xos"]

        XCTAssertEqual(settings.targetMode, .specificApps)
        XCTAssertEqual(settings.targetAppBundleIDs.count, 2)
        XCTAssertTrue(settings.targetAppBundleIDs.contains("us.zoom.xos"))
    }
}
