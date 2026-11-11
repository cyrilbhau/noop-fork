import XCTest
@testable import StrandAnalytics

// Tests for ruling A16 of docs/personal/superapp/specs/RULINGS-ADDENDUM.md ("Stage 4 overflow and
// sign"), which settles fault-injection gaps B23, B25 and B26 over
// docs/personal/superapp/specs/stage-4.md §7.3 and §7.4. Every expected value is derived from the
// ruling and those two sections. No Kotlin twin, by ruling R43 of the stage 1 specification.
//
//   B23  "A sum of sides that overflows is notAvailable(.invalidComponent) with no source."
//   B25  "A delta that overflows saturates at ±greatestFiniteMagnitude."
//   B26  "A percent that overflows is nil."
//   All  "No output is ever infinite or NaN."
//
// NOT ASSERTED, still needing a ruling:
//
//   1. The percent beside a SATURATED delta when the earlier value is positive, for example
//      earlier `greatestFiniteMagnitude`, later `-greatestFiniteMagnitude`. Reading one: §7.3 step 4
//      on the saturated delta, which is -100.0. Reading two: the percent of the true change, -200.0.
//      Reading three: nil, because the change itself overflowed. Only "nil or finite" is asserted.
//   2. `BodyRecordMath.quantize` on a non-finite input. §6.3 says the input is returned unchanged;
//      A16 says no output is ever infinite or NaN. Reading one: A16 speaks of `compare`, `derive` and
//      the unit table, and `quantize` keeps its pass-through. Reading two: A16 covers `quantize`
//      too, and then its replacement value is not stated. Not asserted here.

/// `BodyScanDerivation.derive` and `BodyRecordComparison.compare` at the points ruling A16 decides.
final class BodyRecordRulingGapTests: XCTestCase {

    private let huge = Double.greatestFiniteMagnitude

    private func delta(_ change: BodyRecordChange, file: StaticString = #filePath,
                       line: UInt = #line) -> BodyRecordDelta? {
        guard case .both(let d) = change else {
            XCTFail("expected .both, got \(change)", file: file, line: line)
            return nil
        }
        return d
    }

    private func reading(_ value: Double, _ decimals: Int) -> BodyRecordReading {
        BodyRecordReading(value: value, decimals: decimals)
    }

    // MARK: - B23: a sum of sides that overflows

    /// Fault B23. Two usable leg sides whose sum is infinite, with printed arms: the ratio is
    /// `invalidComponent` and the legs have no source. The mutant gives `.value(0.0)` from
    /// `sumOfSides`. The side difference of two equal usable sides is still 0.0 (§7.4).
    func testOverflowingLegsSumIsInvalidWithNoSource() {
        XCTAssertTrue((huge + huge).isInfinite, "the fixture sum must overflow")
        let d = BodyScanDerivation.derive(BodyScanComponents(armsLean: 10, legLeftLean: huge,
                                                             legRightLean: huge))
        XCTAssertEqual(d.armToLegLeanPercent, .notAvailable(.invalidComponent))
        XCTAssertNil(d.legsSource)
        XCTAssertEqual(d.armsSource, .printedTotal)
        XCTAssertEqual(d.legSideDifferencePercent, .value(0.0))
    }

    /// Fault B23, the arms pair. Two usable arm sides whose sum is infinite, with printed legs: the
    /// ratio is `invalidComponent` and the arms have no source, never `sumOfSides`.
    func testOverflowingArmsSumIsInvalidWithNoSource() {
        let d = BodyScanDerivation.derive(BodyScanComponents(armLeftLean: huge, armRightLean: huge,
                                                             legsLean: 10))
        XCTAssertEqual(d.armToLegLeanPercent, .notAvailable(.invalidComponent))
        XCTAssertNil(d.armsSource)
        XCTAssertEqual(d.legsSource, .printedTotal)
        XCTAssertEqual(d.armSideDifferencePercent, .value(0.0))
    }

    /// Fault B23 through the §7.4 precedence. An overflowing pair is `invalidComponent`, and an
    /// invalid pair outranks a missing one, so legs that overflow beside arms that were never entered
    /// read `invalidComponent`. A pair treated as a usable infinite total would read
    /// `missingComponent` here.
    func testOverflowingSumOutranksAMissingPair() {
        let legs = BodyScanDerivation.derive(BodyScanComponents(legLeftLean: huge, legRightLean: huge))
        XCTAssertEqual(legs.armToLegLeanPercent, .notAvailable(.invalidComponent))
        XCTAssertNil(legs.armsSource)
        XCTAssertNil(legs.legsSource)

        let arms = BodyScanDerivation.derive(BodyScanComponents(armLeftLean: huge, armRightLean: huge))
        XCTAssertEqual(arms.armToLegLeanPercent, .notAvailable(.invalidComponent))
        XCTAssertNil(arms.armsSource)
        XCTAssertNil(arms.legsSource)
    }

    /// The limit of the ruling: it speaks of a SUM of sides. §7.4 step 1 uses a usable printed total
    /// and never adds the sides, so sides that would overflow change nothing: 10 over 20 is 50.0 from
    /// two printed totals.
    func testAPrintedTotalIsUsedEvenWhenTheSidesWouldOverflow() {
        let d = BodyScanDerivation.derive(BodyScanComponents(armsLean: 10, armLeftLean: huge,
                                                             armRightLean: huge, legsLean: 20,
                                                             legLeftLean: huge, legRightLean: huge))
        XCTAssertEqual(d.armToLegLeanPercent, .value(50.0))
        XCTAssertEqual(d.armsSource, .printedTotal)
        XCTAssertEqual(d.legsSource, .printedTotal)
    }

    // MARK: - B25: a delta that overflows

    /// Fault B25. `later - earlier` overflows upward: the change is exactly the largest finite
    /// double, upward. The earlier value is not positive, so there is no percent (§7.3 step 4). The
    /// mutant returns an infinite change.
    func testOverflowingDeltaSaturatesAtTheLargestFiniteDoubleUpward() {
        for decimals in [0, 2, 6] {
            guard let d = delta(BodyRecordComparison.compare(earlier: reading(-huge, decimals),
                                                             later: reading(huge, decimals)))
            else { return }
            XCTAssertEqual(d.delta, huge, "decimals \(decimals)")
            XCTAssertTrue(d.delta.isFinite, "decimals \(decimals)")
            XCTAssertEqual(d.direction, .up, "decimals \(decimals)")
            XCTAssertEqual(d.earlier, -huge, "decimals \(decimals)")
            XCTAssertEqual(d.later, huge, "decimals \(decimals)")
            XCTAssertNil(d.percent, "decimals \(decimals)")
        }
    }

    /// Fault B25, downward. The change is exactly the largest finite double negated, downward. The
    /// percent beside it is not ruled (see the file header) and is asserted only to be nil or finite.
    func testOverflowingDeltaSaturatesAtTheLargestFiniteDoubleDownward() {
        guard let d = delta(BodyRecordComparison.compare(earlier: reading(huge, 0),
                                                         later: reading(-huge, 0)))
        else { return }
        XCTAssertEqual(d.delta, -huge)
        XCTAssertTrue(d.delta.isFinite)
        XCTAssertEqual(d.direction, .down)
        XCTAssertEqual(d.earlier, huge)
        XCTAssertEqual(d.later, -huge)
        if let p = d.percent { XCTAssertTrue(p.isFinite, "\(p)") }
    }

    /// Fault B25 with unequal ends: any overflow saturates, not only the symmetric one. 1e308 minus
    /// the most negative double is beyond the range, so the change is the largest finite double.
    func testOverflowingDeltaWithUnequalEndsSaturates() {
        XCTAssertTrue((1e308 - (-huge)).isInfinite, "the fixture difference must overflow")
        guard let up = delta(BodyRecordComparison.compare(earlier: reading(-huge, 0),
                                                          later: reading(1e308, 0)))
        else { return }
        XCTAssertEqual(up.delta, huge)
        XCTAssertEqual(up.direction, .up)
        XCTAssertNil(up.percent)

        guard let down = delta(BodyRecordComparison.compare(earlier: reading(-1e308, 0),
                                                            later: reading(-huge, 0)))
        else { return }
        // -huge - (-1e308) is finite (about -7.98e307): no saturation applies to a finite change.
        XCTAssertEqual(down.delta, -huge + 1e308)
        XCTAssertEqual(down.direction, .down)
    }

    // MARK: - B26: a percent that overflows

    /// Fault B26. The change is finite (the largest finite double, since one millionth is absorbed)
    /// but `delta / earlier * 100` is infinite: the percent is nil. The mutant returns infinity.
    func testOverflowingPercentIsNil() {
        guard let d = delta(BodyRecordComparison.compare(earlier: reading(0.000001, 6),
                                                         later: reading(huge, 0)))
        else { return }
        XCTAssertEqual(d.earlier, 0.000001)
        XCTAssertEqual(d.later, huge)
        XCTAssertEqual(d.delta, huge)
        XCTAssertEqual(d.direction, .up)
        XCTAssertNil(d.percent)
    }

    /// Fault B26, downward: a positive earlier value and a change whose percent is negative
    /// infinity. The percent is nil; the change and direction are as §7.3 gives them.
    func testOverflowingNegativePercentIsNil() {
        guard let d = delta(BodyRecordComparison.compare(earlier: reading(0.000001, 6),
                                                         later: reading(-huge, 0)))
        else { return }
        XCTAssertEqual(d.delta, -huge)
        XCTAssertEqual(d.direction, .down)
        XCTAssertNil(d.percent)
    }

    /// Fault B26 where only the last step overflows: `delta / earlier` is finite and the
    /// multiplication by 100 is what leaves the range. Earlier 1, later a fiftieth of the largest
    /// double: the change is the later value (1 is absorbed), and 100 times it is infinite.
    func testPercentThatOverflowsOnlyAtTheTimesHundredStepIsNil() {
        let later = huge / 50
        XCTAssertEqual(later - 1, later, "1 must be absorbed by the fixture value")
        XCTAssertTrue((later / 1 * 100).isInfinite, "the fixture percent must overflow")
        guard let d = delta(BodyRecordComparison.compare(earlier: reading(1, 0), later: reading(later, 0)))
        else { return }
        XCTAssertEqual(d.delta, later)
        XCTAssertEqual(d.direction, .up)
        XCTAssertNil(d.percent)
    }

    // MARK: - No output is ever infinite or NaN

    /// Ruling A16, last sentence, for `compare`: over every pair of extreme readings, every number in
    /// the result is finite, the change is never negative zero (§6.3), and a percent is nil or
    /// finite. A reading that is not finite is absent (§7.3 step 1), so it never reaches an output.
    func testCompareNeverReturnsANonFiniteNumber() {
        let values: [Double] = [-.infinity, -huge, -1e308, -1e300, -1e15, -1, -1e-6, -.leastNonzeroMagnitude,
                                -0.0, 0, .leastNonzeroMagnitude, 1e-6, 1, 1e15, 1e300, 1e308, huge,
                                .infinity, .nan]
        for a in values {
            for b in values {
                for (da, db) in [(0, 0), (1, 0), (6, 6), (0, 6)] {
                    let label = "earlier \(a) at \(da), later \(b) at \(db)"
                    switch BodyRecordComparison.compare(earlier: reading(a, da), later: reading(b, db)) {
                    case .neither:
                        XCTAssertFalse(a.isFinite || b.isFinite, label)
                    case .onlyEarlier(let q):
                        XCTAssertTrue(q.isFinite, label)
                        XCTAssertTrue(a.isFinite && !b.isFinite, label)
                    case .onlyLater(let q):
                        XCTAssertTrue(q.isFinite, label)
                        XCTAssertTrue(b.isFinite && !a.isFinite, label)
                    case .both(let d):
                        XCTAssertTrue(a.isFinite && b.isFinite, label)
                        XCTAssertTrue(d.earlier.isFinite, label)
                        XCTAssertTrue(d.later.isFinite, label)
                        XCTAssertTrue(d.delta.isFinite, "\(label): delta \(d.delta)")
                        XCTAssertFalse(d.delta == 0 && d.delta.sign == .minus, "\(label): negative zero")
                        if let p = d.percent { XCTAssertTrue(p.isFinite, "\(label): percent \(p)") }
                        if !(d.earlier > 0) { XCTAssertNil(d.percent, label) }
                    }
                }
            }
        }
    }

    /// Ruling A16, last sentence, for `derive`: over every combination of absent, unusable, tiny,
    /// ordinary, largest and non-finite components, no figure is infinite or NaN, and a figure is
    /// never negative zero. A pair with no source never yields a ratio value.
    func testDeriveNeverReturnsANonFiniteNumber() {
        let values: [Double?] = [nil, -1, 0, .leastNonzeroMagnitude, 1, huge, .infinity, .nan]
        var failures = 0
        for armsLean in values { for armLeft in values { for armRight in values {
            for legsLean in values { for legLeft in values { for legRight in values {
                let c = BodyScanComponents(armsLean: armsLean, armLeftLean: armLeft, armRightLean: armRight,
                                           legsLean: legsLean, legLeftLean: legLeft, legRightLean: legRight)
                let d = BodyScanDerivation.derive(c)
                var bad = false
                for figure in [d.armToLegLeanPercent, d.armSideDifferencePercent, d.legSideDifferencePercent] {
                    if case .value(let x) = figure, !x.isFinite || (x == 0 && x.sign == .minus) { bad = true }
                }
                if case .value = d.armToLegLeanPercent, d.armsSource == nil || d.legsSource == nil { bad = true }
                if bad {
                    failures += 1
                    if failures <= 5 { XCTFail("\(c) gave \(d)") }
                }
            } } }
        } } }
        XCTAssertEqual(failures, 0)
    }
}
