import XCTest
@testable import StrandAnalytics

// Tests added after fault injection (stage 4, faults B23, B25 and B26), from
// docs/personal/superapp/specs/stage-4.md §6.3, §7.3 and §7.4. No Kotlin twin, by ruling R43 of the
// stage 1 specification.
//
// NEEDS A RULING. For each of the three faults the specification's literal steps and the reading the
// implementation took disagree, so no test here asserts the disputed value:
//
//   B23  Two usable sides whose sum overflows (§7.4). Literal steps: the pair total is `left + right`
//        (infinite) with source `sumOfSides`, and arms 10 over it is `.value(0.0)`. Other reading: the
//        pair is `invalidComponent` with a nil source.
//   B25  `later - earlier` overflows (§7.3). Literal steps: `quantize` leaves a non-finite number
//        unchanged, so `delta` is infinite. Other reading: `delta` saturates at the largest finite
//        double.
//   B26  `delta / earlier * 100` overflows (§7.3). Literal steps: the percent is infinite, since the
//        earlier value is positive. Other reading: the percent is nil.
//
// What both readings share, and the finite cases next to each overflow that the specification does
// decide, are pinned below.

/// `BodyRecordComparison` and `BodyScanDerivation` at the edge of the double range: the parts of
/// §7.3 and §7.4 that hold whichever way the overflow cases are ruled.
final class BodyRecordGapTests: XCTestCase {

    private let huge = Double.greatestFiniteMagnitude
    private let dash = "—"

    private func delta(_ change: BodyRecordChange, file: StaticString = #filePath,
                       line: UInt = #line) -> BodyRecordDelta? {
        guard case .both(let d) = change else {
            XCTFail("expected .both, got \(change)", file: file, line: line)
            return nil
        }
        return d
    }

    // MARK: - B23: the sum of two sides

    /// §7.4: two usable sides with no printed total are summed. A sum that is still finite, however
    /// large, is a usable total from `sumOfSides`; arms 10 over it is 0.0 at one decimal.
    func testLargestFiniteSumOfSidesIsStillAUsableTotal() {
        let half = huge / 2
        XCTAssertEqual(half + half, huge, "the fixture sum must be exactly the largest finite double")
        let d = BodyScanDerivation.derive(BodyScanComponents(armsLean: 10, legLeftLean: half,
                                                             legRightLean: half))
        XCTAssertEqual(d.armsSource, .printedTotal)
        XCTAssertEqual(d.legsSource, .sumOfSides)
        XCTAssertEqual(d.armToLegLeanPercent, .value(0.0))
        if case .value(let x) = d.armToLegLeanPercent { XCTAssertEqual(x.sign, .plus) }
        XCTAssertEqual(d.legSideDifferencePercent, .value(0.0))
    }

    /// The parts of an overflowing legs sum that §7.4 decides under either reading: the legs are never
    /// "missing", the printed arms keep their source, no figure is non-finite, and the side difference
    /// of two equal usable sides is 0.0.
    func testOverflowingLegsSumIsNeverMissingAndNeverNonFinite() {
        let d = BodyScanDerivation.derive(BodyScanComponents(armsLean: 10, legLeftLean: huge,
                                                             legRightLean: huge))
        XCTAssertEqual(d.armsSource, .printedTotal)
        XCTAssertTrue(d.armToLegLeanPercent == .value(0.0)
                        || d.armToLegLeanPercent == .notAvailable(.invalidComponent),
                      "\(d.armToLegLeanPercent)")
        XCTAssertNotEqual(d.armToLegLeanPercent, .notAvailable(.missingComponent))
        XCTAssertEqual(d.legSideDifferencePercent, .value(0.0))
        XCTAssertEqual(d.armSideDifferencePercent, .notAvailable(.missingComponent))
    }

    /// An overflowing arms sum over ordinary legs: `r` is not finite, which §7.4 names
    /// `invalidComponent` under either reading. The printed legs keep their source.
    func testOverflowingArmsSumOverPrintedLegsIsInvalid() {
        let d = BodyScanDerivation.derive(BodyScanComponents(armLeftLean: huge, armRightLean: huge,
                                                             legsLean: 10))
        XCTAssertEqual(d.armToLegLeanPercent, .notAvailable(.invalidComponent))
        XCTAssertEqual(d.legsSource, .printedTotal)
        XCTAssertEqual(d.armSideDifferencePercent, .value(0.0))
    }

    // MARK: - B25: the change between two readings

    /// §7.3 step 3 on a difference that is exactly the largest finite double: nothing overflows, so
    /// the change is that number, upward, with no percent (the earlier value is not positive).
    func testLargestFiniteDifferenceIsReportedAsItIs() {
        let half = huge / 2
        guard let d = delta(BodyRecordComparison.compare(earlier: BodyRecordReading(value: -half, decimals: 0),
                                                         later: BodyRecordReading(value: half, decimals: 0)))
        else { return }
        XCTAssertEqual(d.earlier, -half)
        XCTAssertEqual(d.later, half)
        XCTAssertEqual(d.delta, huge)
        XCTAssertEqual(d.direction, .up)
        XCTAssertNil(d.percent)
    }

    /// The parts of an overflowing difference that §7.3 decides under either reading: both ends are
    /// reported unchanged, the direction follows the sign, the change displays as a dash, it is never
    /// NaN, and there is no percent of a negative base.
    func testOverflowingDifferenceKeepsItsDirectionAndDisplaysADash() {
        guard let up = delta(BodyRecordComparison.compare(earlier: BodyRecordReading(value: -huge, decimals: 0),
                                                          later: BodyRecordReading(value: huge, decimals: 0)))
        else { return }
        XCTAssertEqual(up.earlier, -huge)
        XCTAssertEqual(up.later, huge)
        XCTAssertFalse(up.delta.isNaN)
        XCTAssertGreaterThanOrEqual(up.delta, huge)
        XCTAssertEqual(up.direction, .up)
        XCTAssertEqual(BodyRecordMath.displayString(up.delta, decimals: 0), dash)
        XCTAssertNil(up.percent)

        guard let down = delta(BodyRecordComparison.compare(earlier: BodyRecordReading(value: huge, decimals: 0),
                                                            later: BodyRecordReading(value: -huge, decimals: 0)))
        else { return }
        XCTAssertFalse(down.delta.isNaN)
        XCTAssertLessThanOrEqual(down.delta, -huge)
        XCTAssertEqual(down.direction, .down)
        XCTAssertEqual(BodyRecordMath.displayString(down.delta, decimals: 0), dash)
    }

    // MARK: - B26: the percent

    /// §7.3 step 4 on a percent too large to display but still finite: `quantize` leaves a number at
    /// or above 1e15 unchanged, so the percent is that number and not nil. 1 to 1e14 at no decimals is
    /// a change of 99,999,999,999,999, which is 9,999,999,999,999,900 percent.
    func testAFinitePercentAboveTheDisplayLimitIsStillReported() {
        guard let d = delta(BodyRecordComparison.compare(earlier: BodyRecordReading(value: 1, decimals: 0),
                                                         later: BodyRecordReading(value: 1e14, decimals: 0)))
        else { return }
        XCTAssertEqual(d.delta, 99_999_999_999_999)
        XCTAssertEqual(d.percent, 9_999_999_999_999_900)
        XCTAssertEqual(d.direction, .up)
    }

    /// The parts of an overflowing percent that §7.3 decides under either reading: the displayed ends,
    /// the change and the direction are as written, and the percent is absent or infinite, never NaN
    /// and never a finite number.
    func testOverflowingPercentIsNeverAFiniteNumberOrNaN() {
        guard let d = delta(BodyRecordComparison.compare(earlier: BodyRecordReading(value: 0.000001, decimals: 6),
                                                         later: BodyRecordReading(value: huge, decimals: 0)))
        else { return }
        XCTAssertEqual(d.earlier, 0.000001)
        XCTAssertEqual(d.later, huge)
        XCTAssertEqual(d.delta, huge)
        XCTAssertEqual(d.direction, .up)
        XCTAssertTrue(d.percent == nil || d.percent == .infinity, "\(String(describing: d.percent))")
    }
}
