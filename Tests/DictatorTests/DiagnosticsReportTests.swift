import Foundation
import XCTest
@testable import Dictator

final class DiagnosticsReportTests: XCTestCase {
    func testFormattedIncludesCurrentStateAndOmitsTranscriptBody() {
        let report = DiagnosticsReport(
            timestamp: Date(timeIntervalSince1970: 1_752_975_600),
            appVersion: "0.1.0",
            buildVersion: "1",
            bundlePath: "/tmp/Dictator.app",
            processID: 12345,
            hotkeyTitle: "fn (globe)",
            activationTitle: "Hold to Talk",
            dictationState: "idle",
            sessionLocked: false,
            hotkeyListenerActive: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false,
            microphonePermission: "authorized",
            launchAtLoginEnabled: false,
            modelStatus: "Model: ready (Parakeet TDT v3)",
            polishStatus: "AI polish: not built in",
            historyCount: 2,
            lastHistoryApp: "Notes",
            lastHistoryDate: Date(timeIntervalSince1970: 1_752_975_660),
            setupWarning: nil
        )

        let formatted = report.formatted

        XCTAssertTrue(formatted.contains("Dictator Diagnostics"))
        XCTAssertTrue(formatted.contains("hotkey: fn (globe)"))
        XCTAssertTrue(formatted.contains("input monitoring granted: false"))
        XCTAssertTrue(formatted.contains("last dictation app: Notes"))
        XCTAssertTrue(formatted.contains("setup warning: none"))
        XCTAssertTrue(formatted.contains("note: transcript text omitted for privacy"))
        XCTAssertFalse(formatted.contains("raw transcript"))
    }

    func testFormattedIncludesWarningWhenSetupIsIncomplete() {
        let report = DiagnosticsReport(
            timestamp: Date(timeIntervalSince1970: 0),
            appVersion: "0.1.0",
            buildVersion: "1",
            bundlePath: "/tmp/Dictator.app",
            processID: 1,
            hotkeyTitle: "fn (globe)",
            activationTitle: "Hold to Talk",
            dictationState: "idle",
            sessionLocked: false,
            hotkeyListenerActive: false,
            accessibilityGranted: false,
            inputMonitoringGranted: false,
            microphonePermission: "denied",
            launchAtLoginEnabled: true,
            modelStatus: "Model: loading…",
            polishStatus: "AI polish: not built in",
            historyCount: 0,
            lastHistoryApp: nil,
            lastHistoryDate: nil,
            setupWarning: "⚠️ Accessibility not granted — open settings to finish setup"
        )

        let formatted = report.formatted

        XCTAssertTrue(formatted.contains("history count: 0"))
        XCTAssertTrue(formatted.contains("last dictation app: none"))
        XCTAssertTrue(formatted.contains("last dictation at: none"))
        XCTAssertTrue(formatted.contains("setup warning: ⚠️ Accessibility not granted"))
    }
}
