import XCTest
@testable import StrandAnalytics

// Cases the fault injection of the stage 6 pure logic found no test for (fault C48 of the stage 6
// report). Every expected value is read from docs/personal/superapp/specs/stage-6.md §7.2; none is taken
// from what the implementation returns.
//
// C48, §7.2 step 1: "`minNightsPerWeek < 1` or greater than 7, or `maxWeeks < 1`: `.parameters`". The
// step has no condition on the nights, so it holds with none. An invalid result is empty.
//
// NOT PINNED (needs a ruling): whether a non-finite or out-of-range value on a night before the first
// shown week is counted (fault C46). Step 3 counts every dropped value and precedes step 4; step 5 says
// nights before `start` are "not counted as rejected".

/// A Wednesday; 2031-01-13 is a Monday on or before it.
private let gapToday = "2031-02-05"

private func weekly(minNights: Int = 4, maxWeeks: Int = 26,
                    firstWeekStart: String? = nil) -> CutStressResult {
    CutStressTrend.weekly(CutStressInput(nights: [], firstWeekStart: firstWeekStart, today: gapToday,
                                         minNightsPerWeek: minNights, maxWeeks: maxWeeks))
}

final class CutStressTrendRulingGapTests: XCTestCase {

    func testMinNightsZeroIsInvalidWithNoNights() {
        XCTAssertEqual(weekly(minNights: 0).invalidInput, .parameters)
    }

    func testEveryParameterLimitHoldsWithNoNights() {
        XCTAssertEqual(weekly(minNights: -1).invalidInput, .parameters)
        XCTAssertEqual(weekly(minNights: 8).invalidInput, .parameters)
        XCTAssertEqual(weekly(maxWeeks: 0).invalidInput, .parameters)
        XCTAssertEqual(weekly(maxWeeks: -1).invalidInput, .parameters)
    }

    func testMinNightsZeroWithNoNightsShowsNoWeeksEvenWithAFirstWeek() {
        let result = weekly(minNights: 0, firstWeekStart: "2031-01-13")
        XCTAssertEqual(result.invalidInput, .parameters)
        XCTAssertTrue(result.weeks.isEmpty)
        XCTAssertNil(result.restingHrChange)
        XCTAssertNil(result.hrvChange)
    }

    func testTheLimitsThemselvesAreValidWithNoNights() {
        // 1 and 7 nights and one week are inside the limits of step 1.
        XCTAssertNil(weekly(minNights: 1).invalidInput)
        XCTAssertNil(weekly(minNights: 7).invalidInput)
        XCTAssertNil(weekly(maxWeeks: 1).invalidInput)
    }
}
