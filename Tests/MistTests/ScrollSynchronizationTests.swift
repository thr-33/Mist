import XCTest
@testable import Mist

final class ScrollSynchronizationTests: XCTestCase {

    // MARK: - Progress mapping

    func testProgressAtTopIsZero() {
        let p = VerticalScrollMapping.progress(
            contentOffsetY: 0,
            contentHeight: 2000,
            viewportHeight: 500
        )
        XCTAssertEqual(p, 0, accuracy: 1e-9)
    }

    func testProgressAtBottomIsOne() {
        let p = VerticalScrollMapping.progress(
            contentOffsetY: 1500,
            contentHeight: 2000,
            viewportHeight: 500
        )
        XCTAssertEqual(p, 1, accuracy: 1e-9)
    }

    func testProgressMidway() {
        let p = VerticalScrollMapping.progress(
            contentOffsetY: 750,
            contentHeight: 2000,
            viewportHeight: 500
        )
        XCTAssertEqual(p, 0.5, accuracy: 1e-9)
    }

    func testProgressClampsAboveOne() {
        let p = VerticalScrollMapping.progress(
            contentOffsetY: 5000,
            contentHeight: 2000,
            viewportHeight: 500
        )
        XCTAssertEqual(p, 1, accuracy: 1e-9)
    }

    func testProgressClampsBelowZero() {
        let p = VerticalScrollMapping.progress(
            contentOffsetY: -40,
            contentHeight: 2000,
            viewportHeight: 500
        )
        XCTAssertEqual(p, 0, accuracy: 1e-9)
    }

    func testZeroRangeWhenContentFitsViewport() {
        let p = VerticalScrollMapping.progress(
            contentOffsetY: 0,
            contentHeight: 400,
            viewportHeight: 500
        )
        XCTAssertEqual(p, 0, accuracy: 1e-9)
        let range = VerticalScrollMapping.scrollableRange(
            contentHeight: 400,
            viewportHeight: 500
        )
        XCTAssertEqual(range, 0, accuracy: 1e-9)
        let y = VerticalScrollMapping.contentOffsetY(
            progress: 0.75,
            contentHeight: 400,
            viewportHeight: 500
        )
        XCTAssertEqual(y, 0, accuracy: 1e-9)
    }

    func testZeroRangeWithEqualHeights() {
        let p = VerticalScrollMapping.progress(
            contentOffsetY: 10,
            contentHeight: 500,
            viewportHeight: 500
        )
        XCTAssertEqual(p, 0, accuracy: 1e-9)
    }

    func testOffsetFromProgressRoundTrip() {
        let content: CGFloat = 2400
        let viewport: CGFloat = 600
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let y = VerticalScrollMapping.contentOffsetY(
                progress: fraction,
                contentHeight: content,
                viewportHeight: viewport
            )
            let back = VerticalScrollMapping.progress(
                contentOffsetY: y,
                contentHeight: content,
                viewportHeight: viewport
            )
            XCTAssertEqual(back, fraction, accuracy: 1e-9)
        }
    }

    func testDifferentPaneHeightsShareNormalizedProgress() {
        // Source taller than preview: same progress → different absolute offsets.
        let sourceY = VerticalScrollMapping.contentOffsetY(
            progress: 0.4,
            contentHeight: 3000,
            viewportHeight: 500
        )
        let previewY = VerticalScrollMapping.contentOffsetY(
            progress: 0.4,
            contentHeight: 1200,
            viewportHeight: 500
        )
        XCTAssertEqual(sourceY, 1000, accuracy: 1e-6)
        XCTAssertEqual(previewY, 280, accuracy: 1e-6)
        XCTAssertNotEqual(sourceY, previewY, accuracy: 1e-6)
    }

    func testClampProgressHandlesNaNAndInfinity() {
        XCTAssertEqual(VerticalScrollMapping.clampProgress(.nan), 0)
        XCTAssertEqual(VerticalScrollMapping.clampProgress(.infinity), 0)
        XCTAssertEqual(VerticalScrollMapping.clampProgress(-.infinity), 0)
        XCTAssertEqual(VerticalScrollMapping.clampProgress(-0.2), 0)
        XCTAssertEqual(VerticalScrollMapping.clampProgress(1.2), 1)
        XCTAssertEqual(VerticalScrollMapping.clampProgress(0.3), 0.3, accuracy: 1e-12)
    }

    func testIsNearlyEqualRespectsEpsilon() {
        XCTAssertTrue(VerticalScrollMapping.isNearlyEqual(0.5, 0.5))
        XCTAssertTrue(VerticalScrollMapping.isNearlyEqual(0.5, 0.5 + 0.000_4))
        XCTAssertFalse(VerticalScrollMapping.isNearlyEqual(0.5, 0.5 + 0.001))
    }

    // MARK: - Feedback / driver policy

    func testPolicyRejectsEchoFromProgrammaticTargetOnly() {
        // Follower receiving apply is rejected; driving pane stays accepted.
        XCTAssertFalse(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: .preview,
                activeDriver: .source,
                reportingPane: .preview
            )
        )
        XCTAssertTrue(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: .preview,
                activeDriver: .source,
                reportingPane: .source
            )
        )
    }

    func testPolicyRejectsFollowerWhileOtherPaneDrives() {
        XCTAssertFalse(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: nil,
                activeDriver: .source,
                reportingPane: .preview
            )
        )
        XCTAssertTrue(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: nil,
                activeDriver: .source,
                reportingPane: .source
            )
        )
    }

    func testPolicyAcceptsWhenIdle() {
        XCTAssertTrue(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: nil,
                activeDriver: nil,
                reportingPane: .preview
            )
        )
    }

    func testShouldPropagateIgnoresTinyDeltas() {
        XCTAssertFalse(ScrollSyncPolicy.shouldPropagate(from: 0.5, to: 0.5))
        XCTAssertFalse(ScrollSyncPolicy.shouldPropagate(from: 0.5, to: 0.5 + 0.000_1))
        XCTAssertTrue(ScrollSyncPolicy.shouldPropagate(from: 0.5, to: 0.6))
    }

    func testEndDriverClearsOnlyMatchingPane() {
        XCTAssertNil(ScrollSyncPolicy.endDriver(activeDriver: .source, endingPane: .source))
        XCTAssertEqual(
            ScrollSyncPolicy.endDriver(activeDriver: .source, endingPane: .preview),
            .source
        )
        XCTAssertNil(ScrollSyncPolicy.endDriver(activeDriver: nil, endingPane: .preview))
    }

    // MARK: - Sticky driver lifecycle (T2)

    func testNonLiveDoesNotEstablishStickyDriver() {
        let next = ScrollSyncPolicy.driverAfterAccepting(
            activeDriver: nil,
            reportingPane: .source,
            kind: .nonLive
        )
        XCTAssertNil(next)
    }

    func testNonLivePreservesExistingSamePaneLiveDriver() {
        let next = ScrollSyncPolicy.driverAfterAccepting(
            activeDriver: .source,
            reportingPane: .source,
            kind: .nonLive
        )
        XCTAssertEqual(next, .source)
    }

    func testLiveEstablishesStickyDriver() {
        let next = ScrollSyncPolicy.driverAfterAccepting(
            activeDriver: nil,
            reportingPane: .preview,
            kind: .live
        )
        XCTAssertEqual(next, .preview)
    }

    func testBoundsOnlySequenceAllowsOppositePaneTakeover() {
        // Simulate: source keyboard/bounds scroll → no sticky lock → preview can drive.
        var driver: ScrollSyncPane? = nil
        XCTAssertTrue(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: nil,
                activeDriver: driver,
                reportingPane: .source
            )
        )
        driver = ScrollSyncPolicy.driverAfterAccepting(
            activeDriver: driver,
            reportingPane: .source,
            kind: .nonLive
        )
        XCTAssertNil(driver, "bounds-only must not sticky-lock")

        // Follower echo during apply is rejected; driver rapid event still accepted.
        XCTAssertFalse(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: .preview,
                activeDriver: driver,
                reportingPane: .preview
            )
        )
        XCTAssertTrue(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: .preview,
                activeDriver: driver,
                reportingPane: .source
            )
        )

        // After apply clears, opposite pane can take over.
        XCTAssertTrue(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: nil,
                activeDriver: driver,
                reportingPane: .preview
            )
        )
        driver = ScrollSyncPolicy.driverAfterAccepting(
            activeDriver: driver,
            reportingPane: .preview,
            kind: .live
        )
        XCTAssertEqual(driver, .preview)
    }

    func testNoProgressNonLiveDoesNotLockOppositePane() {
        var driver: ScrollSyncPane? = nil
        driver = ScrollSyncPolicy.driverAfterAccepting(
            activeDriver: driver,
            reportingPane: .source,
            kind: .nonLive
        )
        XCTAssertNil(driver)
        XCTAssertFalse(ScrollSyncPolicy.shouldPropagate(from: 0.4, to: 0.4))
        XCTAssertTrue(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: nil,
                activeDriver: driver,
                reportingPane: .preview
            )
        )
    }

    func testLiveGestureStickyUntilEndThenOppositeCanDrive() {
        var driver: ScrollSyncPane? = nil
        driver = ScrollSyncPolicy.driverAfterAccepting(
            activeDriver: driver,
            reportingPane: .source,
            kind: .live
        )
        XCTAssertEqual(driver, .source)
        XCTAssertFalse(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: nil,
                activeDriver: driver,
                reportingPane: .preview
            )
        )

        // Bounds notifications during the same live gesture keep the lock.
        driver = ScrollSyncPolicy.driverAfterAccepting(
            activeDriver: driver,
            reportingPane: .source,
            kind: .nonLive
        )
        XCTAssertEqual(driver, .source)

        driver = ScrollSyncPolicy.endDriver(activeDriver: driver, endingPane: .source)
        XCTAssertNil(driver)
        XCTAssertTrue(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: nil,
                activeDriver: driver,
                reportingPane: .preview
            )
        )
    }

    func testRapidConsecutiveDriverEventsAcceptedDuringFollowerApply() {
        // Old global applyingProgrammatic flag would reject the driver here.
        XCTAssertTrue(
            ScrollSyncPolicy.shouldAcceptUserScroll(
                programmaticTarget: .preview,
                activeDriver: .source,
                reportingPane: .source
            )
        )
        // Second rapid live tick still owns the driver.
        let next = ScrollSyncPolicy.driverAfterAccepting(
            activeDriver: .source,
            reportingPane: .source,
            kind: .live
        )
        XCTAssertEqual(next, .source)
    }
}
