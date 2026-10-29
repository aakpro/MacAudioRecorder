import XCTest
@testable import InternalSoundRecorderCore

@MainActor
final class SingleInstanceManagerTests: XCTestCase {

    func testSingleInstanceManagerConfiguration() {
        XCTAssertEqual(SingleInstanceManager.bundleIdentifier, "com.internalsoundrecorder.app")
        XCTAssertEqual(SingleInstanceManager.processName, "InternalSoundRecorder")
        XCTAssertNotNil(SingleInstanceManager.shared)
    }

    func testFindOtherRunningInstancesExcludesSelf() {
        let manager = SingleInstanceManager.shared
        let others = manager.findOtherRunningInstances()
        let currentPID = ProcessInfo.processInfo.processIdentifier

        // Running instances returned must never include the test runner process itself
        XCTAssertFalse(others.contains { $0.processIdentifier == currentPID })
    }

    func testEnforceSingleInstanceExecution() {
        let manager = SingleInstanceManager.shared
        // Running enforcement in test suite should execute cleanly without crashing
        let terminated = manager.enforceSingleInstance()
        XCTAssertGreaterThanOrEqual(terminated, 0)
    }
}
