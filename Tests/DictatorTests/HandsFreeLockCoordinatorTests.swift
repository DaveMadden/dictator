import XCTest
@testable import Dictator

final class HandsFreeLockCoordinatorTests: XCTestCase {
    func testLockWhileRecordingShowsImmediatelyAndPreventsReleaseStop() {
        var coordinator = HandsFreeLockCoordinator()
        coordinator.beginSession()

        let showLock = coordinator.requestLock(
            activationMode: .hold,
            dictationState: .recording
        )

        XCTAssertTrue(showLock)
        XCTAssertTrue(coordinator.sessionLocked)
        XCTAssertFalse(coordinator.pendingLock)
        XCTAssertFalse(coordinator.shouldEndOnRelease(activationMode: .hold))
    }

    func testLockDuringStartupDefersIndicatorButStillPreventsReleaseStop() {
        var coordinator = HandsFreeLockCoordinator()
        coordinator.beginSession()

        let showImmediately = coordinator.requestLock(
            activationMode: .hold,
            dictationState: .idle
        )
        let showWhenRecordingStarts = coordinator.recordingDidStart()

        XCTAssertFalse(showImmediately)
        XCTAssertTrue(coordinator.sessionLocked)
        XCTAssertFalse(coordinator.pendingLock)
        XCTAssertFalse(coordinator.shouldEndOnRelease(activationMode: .hold))
        XCTAssertTrue(showWhenRecordingStarts)
    }

    func testNewSessionClearsOldLockState() {
        var coordinator = HandsFreeLockCoordinator()
        coordinator.beginSession()
        _ = coordinator.requestLock(
            activationMode: .hold,
            dictationState: .idle
        )

        coordinator.beginSession()

        XCTAssertFalse(coordinator.sessionLocked)
        XCTAssertFalse(coordinator.pendingLock)
        XCTAssertTrue(coordinator.shouldEndOnRelease(activationMode: .hold))
    }
}
