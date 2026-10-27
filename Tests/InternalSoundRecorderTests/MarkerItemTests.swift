import XCTest
@testable import InternalSoundRecorderCore

final class MarkerItemTests: XCTestCase {

    func testMarkerTimestampFormatting() {
        let m1 = MarkerItem(timestamp: 45, label: "Point A")
        XCTAssertEqual(m1.formattedTimestamp, "00:45")

        let m2 = MarkerItem(timestamp: 3665, label: "Point B")
        XCTAssertEqual(m2.formattedTimestamp, "01:01:05")

        let m3 = MarkerItem(timestamp: 615, label: "Budget Discussion")
        XCTAssertEqual(m3.formattedTimestamp, "10:15")
    }

    func testMarkerSerialization() throws {
        let markers = [
            MarkerItem(timestamp: 10, label: "Intro"),
            MarkerItem(timestamp: 120, label: "Presentation"),
            MarkerItem(timestamp: 300, label: "Q&A")
        ]

        let encoded = try JSONEncoder().encode(markers)
        let decoded = try JSONDecoder().decode([MarkerItem].self, from: encoded)

        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].label, "Intro")
        XCTAssertEqual(decoded[1].formattedTimestamp, "02:00")
        XCTAssertEqual(decoded[2].timestamp, 300)
    }
}
