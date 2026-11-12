import XCTest
import WhoopStore
@testable import StrandAnalytics

// The amount finding of the independent C12 review (packet version 2), pinned by tests that failed
// on the defect before its fix (ruling A25).
//
// The renderer turned an intake amount that rounded above a private 99,999 into "not measured",
// although the quick-add store accepts any finite amount through 100,000 and a day's entries may sum
// beyond that. The packet never turns a stored value into absence: any amount the app accepted
// prints as a whole number, and only the general rule F1 (not finite, or above 10^15) is absent.
//
// The amounts are boundary fixtures, not claims about plausible nutrition. Synthetic values only.

final class CodexReviewPacketV2AmountTests: XCTestCase {

    private typealias F = CoachPacketFixture
    private typealias V = CoachPacketV2Fixture

    private func row(protein: Double?, energy: Double?) -> String? {
        let text = V.full { $0.intake = .days([V.intakeDay("2031-03-05", protein, energy, .quickAdd)]) }.text
        return F.lines(startingWith: "  2031-03-05: protein", in: text).first
    }

    func testTheQuickAddStoresLargestAcceptedAmountIsPrinted() {
        XCTAssertEqual(row(protein: 100_000, energy: nil), "  2031-03-05: protein 100000 g, energy — [quick-add]")
        XCTAssertEqual(row(protein: nil, energy: 100_000), "  2031-03-05: protein —, energy 100000 kcal [quick-add]")
    }

    func testAnAmountRoundingUpToTheStoreLimitIsPrinted() {
        XCTAssertEqual(row(protein: 99_999.5, energy: 99_999.5),
                       "  2031-03-05: protein 100000 g, energy 100000 kcal [quick-add]")
        XCTAssertEqual(row(protein: 99_999.4, energy: 99_999.4),
                       "  2031-03-05: protein 99999 g, energy 99999 kcal [quick-add]")
    }

    func testADayWhoseEntriesSumPastTheStoreLimitIsStillPrinted() {
        // Three accepted entries of 100,000 on one day.
        XCTAssertEqual(row(protein: 300_000, energy: 300_000),
                       "  2031-03-05: protein 300000 g, energy 300000 kcal [quick-add]")
    }

    func testOnlyRuleF1MakesAnAmountAbsent() {
        // At the general limit the amount prints; past it, or not finite, it is absent.
        XCTAssertEqual(row(protein: 1e15, energy: nil),
                       "  2031-03-05: protein 1000000000000000 g, energy — [quick-add]")
        for value in [1e15 * 1.0000001, 1e300, .infinity, -.infinity, .nan] {
            XCTAssertEqual(row(protein: value, energy: nil), "  2031-03-05: protein —, energy —", "\(value)")
        }
        // Below zero is not an amount the app accepts; a negative zero is zero.
        XCTAssertEqual(row(protein: -1, energy: nil), "  2031-03-05: protein —, energy —")
        XCTAssertEqual(row(protein: -0.0, energy: nil), "  2031-03-05: protein 0 g, energy — [quick-add]")
    }
}
