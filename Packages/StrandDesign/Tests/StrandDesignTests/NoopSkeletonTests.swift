import XCTest
@testable import StrandDesign

/// The skeleton is held for at least `NoopTheme.Motion.skeletonMinimum` once shown, so a fast load never
/// flickers, and a skeleton that never appeared adds no delay.
final class NoopSkeletonTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let accuracy = 1e-6

    func testMinimumIsThreeHundredMilliseconds() {
        XCTAssertEqual(NoopTheme.Motion.skeletonMinimum, 0.3, accuracy: accuracy)
    }

    func testNeverShownNeedsNoHold() {
        XCTAssertEqual(NoopSkeletonTiming.remainingHold(shownAt: nil, now: t0), 0)
        XCTAssertFalse(NoopSkeletonTiming.isVisible(isLoading: false, shownAt: nil, now: t0))
    }

    func testFastLoadIsHeldForTheRemainder() {
        let hold = NoopSkeletonTiming.remainingHold(shownAt: t0, now: t0.addingTimeInterval(0.1))
        XCTAssertEqual(hold, 0.2, accuracy: accuracy)
        XCTAssertTrue(NoopSkeletonTiming.isVisible(isLoading: false, shownAt: t0, now: t0.addingTimeInterval(0.1)))
    }

    func testImmediateFinishHoldsTheFullMinimum() {
        XCTAssertEqual(NoopSkeletonTiming.remainingHold(shownAt: t0, now: t0), 0.3, accuracy: accuracy)
    }

    func testSlowLoadHidesImmediately() {
        XCTAssertEqual(NoopSkeletonTiming.remainingHold(shownAt: t0, now: t0.addingTimeInterval(0.3)), 0)
        XCTAssertEqual(NoopSkeletonTiming.remainingHold(shownAt: t0, now: t0.addingTimeInterval(2)), 0)
        XCTAssertFalse(NoopSkeletonTiming.isVisible(isLoading: false, shownAt: t0, now: t0.addingTimeInterval(2)))
    }

    func testStillLoadingIsAlwaysVisible() {
        XCTAssertTrue(NoopSkeletonTiming.isVisible(isLoading: true, shownAt: t0, now: t0.addingTimeInterval(10)))
        XCTAssertTrue(NoopSkeletonTiming.isVisible(isLoading: true, shownAt: nil, now: t0))
    }

    func testClockGoingBackwardsHoldsNoLongerThanTheMinimum() {
        XCTAssertEqual(NoopSkeletonTiming.remainingHold(shownAt: t0, now: t0.addingTimeInterval(-5)), 0.3, accuracy: accuracy)
    }

    func testSubMillisecondResidueCountsAsDone() {
        XCTAssertEqual(NoopSkeletonTiming.remainingHold(shownAt: t0, now: t0.addingTimeInterval(0.2995)), 0)
        XCTAssertEqual(NoopSkeletonTiming.remainingHold(shownAt: t0, now: t0.addingTimeInterval(0.298)), 0.002,
                       accuracy: accuracy)
    }

    func testCustomAndZeroMinimum() {
        XCTAssertEqual(NoopSkeletonTiming.remainingHold(shownAt: t0, now: t0.addingTimeInterval(0.25), minimum: 1), 0.75,
                       accuracy: accuracy)
        XCTAssertEqual(NoopSkeletonTiming.remainingHold(shownAt: t0, now: t0, minimum: 0), 0)
    }
}
