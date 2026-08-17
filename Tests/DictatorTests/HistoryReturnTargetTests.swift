import XCTest
@testable import Dictator

final class HistoryReturnTargetTests: XCTestCase {
    func testCaptureReturnsFrontmostAppWhenItIsNotDictator() {
        let target = HistoryReturnTarget.capture(
            frontmostProcessIdentifier: 4242,
            frontmostBundleIdentifier: "com.apple.TextEdit",
            appProcessIdentifier: 1111,
            appBundleIdentifier: "com.davidmadden.dictator"
        )

        XCTAssertEqual(
            target,
            HistoryReturnTarget(
                processIdentifier: 4242,
                bundleIdentifier: "com.apple.TextEdit"
            )
        )
    }

    func testCaptureIgnoresDictatorWhenItIsAlreadyFrontmost() {
        let target = HistoryReturnTarget.capture(
            frontmostProcessIdentifier: 1111,
            frontmostBundleIdentifier: "com.davidmadden.dictator",
            appProcessIdentifier: 1111,
            appBundleIdentifier: "com.davidmadden.dictator"
        )

        XCTAssertNil(target)
    }

    func testCaptureIgnoresMatchingBundleEvenIfProcessDiffers() {
        let target = HistoryReturnTarget.capture(
            frontmostProcessIdentifier: 2222,
            frontmostBundleIdentifier: "com.davidmadden.dictator",
            appProcessIdentifier: 1111,
            appBundleIdentifier: "com.davidmadden.dictator"
        )

        XCTAssertNil(target)
    }

    func testUpdatedPreservesLastExternalAppWhenDictatorActivates() {
        let current = HistoryReturnTarget(
            processIdentifier: 4242,
            bundleIdentifier: "com.apple.TextEdit"
        )

        let updated = HistoryReturnTarget.updated(
            current: current,
            activatedProcessIdentifier: 1111,
            activatedBundleIdentifier: "com.davidmadden.dictator",
            appProcessIdentifier: 1111,
            appBundleIdentifier: "com.davidmadden.dictator"
        )

        XCTAssertEqual(updated, current)
    }

    func testUpdatedReplacesLastExternalAppWhenNewExternalAppActivates() {
        let current = HistoryReturnTarget(
            processIdentifier: 4242,
            bundleIdentifier: "com.apple.TextEdit"
        )

        let updated = HistoryReturnTarget.updated(
            current: current,
            activatedProcessIdentifier: 4343,
            activatedBundleIdentifier: "com.todesktop.230313mzl4w4u92",
            appProcessIdentifier: 1111,
            appBundleIdentifier: "com.davidmadden.dictator"
        )

        XCTAssertEqual(
            updated,
            HistoryReturnTarget(
                processIdentifier: 4343,
                bundleIdentifier: "com.todesktop.230313mzl4w4u92"
            )
        )
    }
}
