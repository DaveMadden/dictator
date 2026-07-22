import XCTest
@testable import Dictator

final class HotkeySetupStateTests: XCTestCase {
    func testAccessibilityMissingStillShowsRecoveryActionsWhenListenerIsRunning() {
        let state = HotkeySetupState(listenerActive: true, accessibilityGranted: false)

        XCTAssertTrue(state.needsAccessibility)
        XCTAssertTrue(state.showRecoveryActions)
        XCTAssertTrue(state.shouldPromptForAccessibility)
        XCTAssertEqual(
            state.warningText,
            "⚠️ Accessibility not granted — open settings to finish setup"
        )
    }

    func testListenerFailureShowsRecoveryActionsEvenWithAccessibilityGranted() {
        let state = HotkeySetupState(listenerActive: false, accessibilityGranted: true)

        XCTAssertFalse(state.needsAccessibility)
        XCTAssertTrue(state.showRecoveryActions)
        XCTAssertFalse(state.shouldPromptForAccessibility)
        XCTAssertEqual(
            state.warningText,
            "⚠️ Hotkey inactive — use Retry Hotkey Listener"
        )
    }

    func testReadyStateNeedsNoWarningOrRecoveryActions() {
        let state = HotkeySetupState(listenerActive: true, accessibilityGranted: true)

        XCTAssertFalse(state.needsAccessibility)
        XCTAssertFalse(state.showRecoveryActions)
        XCTAssertFalse(state.shouldPromptForAccessibility)
        XCTAssertNil(state.warningText)
    }
}
