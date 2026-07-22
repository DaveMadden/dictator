import CoreGraphics
import XCTest
@testable import Dictator

final class HotkeyStateMachineTests: XCTestCase {
    func testHotkeyPressEnablesGuardTapAndEmitsPress() {
        let machine = HotkeyStateMachine()

        let outcome = machine.handleMonitorEvent(
            type: .flagsChanged,
            keyCode: Hotkey.fn.keyCode,
            flags: [.maskSecondaryFn]
        )

        XCTAssertTrue(outcome.emitPress)
        XCTAssertFalse(outcome.emitRelease)
        XCTAssertEqual(outcome.tapActions, [.enableGuardTap])
        XCTAssertFalse(outcome.swallowEvent)
    }

    func testHotkeyReleaseDisablesGuardTapAndEmitsRelease() {
        let machine = HotkeyStateMachine()
        _ = machine.handleMonitorEvent(
            type: .flagsChanged,
            keyCode: Hotkey.fn.keyCode,
            flags: [.maskSecondaryFn]
        )

        let outcome = machine.handleMonitorEvent(
            type: .flagsChanged,
            keyCode: Hotkey.fn.keyCode,
            flags: []
        )

        XCTAssertFalse(outcome.emitPress)
        XCTAssertTrue(outcome.emitRelease)
        XCTAssertEqual(outcome.tapActions, [.disableGuardTap])
        XCTAssertFalse(outcome.swallowEvent)
    }

    func testSpaceWhileHotkeyHeldSwallowsAndEmitsLock() {
        let machine = HotkeyStateMachine()
        _ = machine.handleMonitorEvent(
            type: .flagsChanged,
            keyCode: Hotkey.fn.keyCode,
            flags: [.maskSecondaryFn]
        )

        let outcome = machine.handleGuardEvent(
            type: .keyDown,
            keyCode: HotkeyStateMachine.spaceKeyCode
        )

        XCTAssertTrue(outcome.emitLock)
        XCTAssertTrue(outcome.swallowEvent)
        XCTAssertEqual(outcome.tapActions, [])
    }

    func testPendingSpaceUpKeepsGuardTapAliveUntilSpaceReleases() {
        let machine = HotkeyStateMachine()
        _ = machine.handleMonitorEvent(
            type: .flagsChanged,
            keyCode: Hotkey.fn.keyCode,
            flags: [.maskSecondaryFn]
        )
        _ = machine.handleGuardEvent(
            type: .keyDown,
            keyCode: HotkeyStateMachine.spaceKeyCode
        )

        let releaseHotkey = machine.handleMonitorEvent(
            type: .flagsChanged,
            keyCode: Hotkey.fn.keyCode,
            flags: []
        )
        let releaseSpace = machine.handleGuardEvent(
            type: .keyUp,
            keyCode: HotkeyStateMachine.spaceKeyCode
        )

        XCTAssertTrue(releaseHotkey.emitRelease)
        XCTAssertEqual(releaseHotkey.tapActions, [])
        XCTAssertTrue(releaseSpace.swallowEvent)
        XCTAssertEqual(releaseSpace.tapActions, [.disableGuardTap])
    }

    func testDisabledTapEventsRequestReenableForMatchingTap() {
        let machine = HotkeyStateMachine()

        let monitorOutcome = machine.handleMonitorEvent(
            type: .tapDisabledByTimeout,
            keyCode: 0,
            flags: []
        )
        let guardOutcome = machine.handleGuardEvent(
            type: .tapDisabledByUserInput,
            keyCode: 0
        )

        XCTAssertEqual(monitorOutcome.tapActions, [.reenableMonitorTap])
        XCTAssertEqual(guardOutcome.tapActions, [.reenableGuardTap])
    }
}
