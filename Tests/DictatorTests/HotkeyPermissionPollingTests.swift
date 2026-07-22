import XCTest
@testable import Dictator

final class HotkeyPermissionPollingTests: XCTestCase {
    func testDoesNothingUntilAccessibilityIsGranted() {
        XCTAssertNil(
            HotkeyPermissionPollOutcome.evaluate(
                accessibilityGranted: false,
                startSucceeded: false
            )
        )
    }

    func testStopsPollingAfterSuccessfulRestart() {
        let outcome = HotkeyPermissionPollOutcome.evaluate(
            accessibilityGranted: true,
            startSucceeded: true
        )

        XCTAssertEqual(
            outcome,
            HotkeyPermissionPollOutcome(
                listenerActive: true,
                stopPolling: true
            )
        )
    }

    func testKeepsPollingIfRestartStillFails() {
        let outcome = HotkeyPermissionPollOutcome.evaluate(
            accessibilityGranted: true,
            startSucceeded: false
        )

        XCTAssertEqual(
            outcome,
            HotkeyPermissionPollOutcome(
                listenerActive: false,
                stopPolling: false
            )
        )
    }
}
