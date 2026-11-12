// Gap tests for `IntakeProgress`, written after the implementation's fault-injection run
// (docs/personal/superapp/specs/stage-3.md §6.5, §7.4, §7.5, §10.8, §13.4). Each test names the
// uncaught fault it closes. Expected values are worked from the specification, not from what the
// implementation returns.
//
// Faults closed here: G20, E16, E17, E18, W1.
// G9 is an equivalent mutant (floor(g) <= g < f <= ceil(f), so the difference is at least 1): no test.
// Left for a ruling, with only what both readings share pinned: G21, E19.
//
// `CutScorecard.quantize` rounds to three decimals, halves away from zero (stage 1 §7.1), so
// 2400.0004 compares as 2400.000 and 2400.0006 as 2400.001.
//
// Everything is the one Fixture Person's invented data (`IntakeFixture`): floor 100 g, range 2400 to
// 2600 kcal, hard floor 2100 kcal.

import XCTest
@testable import StrandAnalytics

private typealias X = IntakeFixture

/// The ruled and uncaught cases of `IntakeProgress` (stage 3 §7.4 and §7.5).
final class IntakeProgressRulingGapTests: XCTestCase {

    // MARK: - Helpers

    private func protein(_ grams: Double?, _ floorGrams: Double? = X.proteinFloorGrams) -> IntakeProteinProgress {
        IntakeProgress.protein(grams: grams, floorGrams: floorGrams)
    }

    private func targets(low: Double = X.energyLowKcal, high: Double = X.energyHighKcal,
                         hardFloor: Double = X.energyHardFloorKcal) -> IntakeTargets {
        IntakeTargets(proteinFloorGrams: X.proteinFloorGrams, energyLowKcal: low,
                      energyHighKcal: high, energyHardFloorKcal: hardFloor)
    }

    private func energy(_ kcal: Double?, open: Bool, _ t: IntakeTargets? = nil) -> IntakeEnergyProgress {
        IntakeProgress.energy(kcal: kcal, targets: t ?? targets(), dayIsOpen: open)
    }

    // MARK: - G20: not measured, with a floor

    /// Fault G20. §7.4: with no amount the state is `notMeasured`, "no number, no ring": the number
    /// is the amount. The floor is still the owner's floor: §10.8 draws "Nothing logged today" with
    /// the floor on the medium widget and says the widget's floor is nil only when no floor is set.
    /// So `shownFloorGrams` is 100 for the Fixture Person whenever the floor is usable.
    func testNotMeasuredStillCarriesTheShownFloor() {
        for grams in [nil, Double.nan, Double.infinity, -1.0] as [Double?] {
            let p = protein(grams)
            XCTAssertEqual(p.state, .notMeasured, "grams \(String(describing: grams))")
            XCTAssertEqual(p.shownFloorGrams, 100, "grams \(String(describing: grams))")
            XCTAssertNil(p.shownGrams, "no number")
            XCTAssertNil(p.ringFraction, "no ring")
        }
        // A floor that is not whole is shown rounded up, as for a measured day (§7.4).
        XCTAssertEqual(protein(nil, 99.5).shownFloorGrams, 100)
        XCTAssertEqual(protein(nil, 120).shownFloorGrams, 120)
    }

    // MARK: - E16: the low end is quantized

    /// Fault E16. §7.5 compares "with k = quantize(kcal) and the bounds quantized". A low end of
    /// 2400.0004 quantizes to 2400.000, so 2400 kcal is not under it: `inRange` on a closed day, and
    /// not `soFar` on an open one. A low end of 2400.0006 quantizes to 2400.001, so 2400 is under it.
    func testTheLowEndIsQuantizedBeforeTheComparison() {
        let justOver = targets(low: 2400.0004)
        XCTAssertTrue(justOver.isValid)
        XCTAssertEqual(energy(2400, open: false, justOver).state, .inRange)
        XCTAssertEqual(energy(2400, open: true, justOver).state, .inRange)

        let aQuantumOver = targets(low: 2400.0006)
        XCTAssertTrue(aQuantumOver.isValid)
        XCTAssertEqual(energy(2400, open: false, aQuantumOver).state, .belowRange)
        XCTAssertEqual(energy(2400, open: true, aQuantumOver).state, .soFar)
        XCTAssertEqual(energy(2400, open: true, aQuantumOver).toLowEndKcal, 1, "ceil(2400.001 - 2400)")
    }

    // MARK: - E17: the high end is quantized

    /// Fault E17. A high end of 2599.9996 quantizes to 2600.000, so 2600 kcal is not above it
    /// (`inRange`, bounds inclusive, §13.4). A high end of 2599.9994 quantizes to 2599.999, so 2600 is
    /// above it by ceil(0.001) = 1.
    func testTheHighEndIsQuantizedBeforeTheComparison() {
        let justUnder = targets(high: 2599.9996)
        XCTAssertTrue(justUnder.isValid)
        for open in [false, true] {
            XCTAssertEqual(energy(2600, open: open, justUnder).state, .inRange, "open \(open)")
        }

        let aQuantumUnder = targets(high: 2599.9994)
        XCTAssertTrue(aQuantumUnder.isValid)
        for open in [false, true] {
            let e = energy(2600, open: open, aQuantumUnder)
            XCTAssertEqual(e.state, .aboveRange, "open \(open)")
            XCTAssertEqual(e.overHighEndKcal, 1, "open \(open)")
        }
    }

    // MARK: - E18: the hard floor is quantized

    /// Fault E18. A hard floor of 2100.0004 quantizes to 2100.000, so 2100 kcal on a closed day is not
    /// below it and is `belowRange` (§13.4: "the hard floor itself is not below it"). A hard floor of
    /// 2100.0006 quantizes to 2100.001, so 2100 is below it.
    func testTheHardFloorIsQuantizedBeforeTheComparison() {
        let justOver = targets(hardFloor: 2100.0004)
        XCTAssertTrue(justOver.isValid)
        XCTAssertEqual(energy(2100, open: false, justOver).state, .belowRange)

        let aQuantumOver = targets(hardFloor: 2100.0006)
        XCTAssertTrue(aQuantumOver.isValid)
        XCTAssertEqual(energy(2100, open: false, aQuantumOver).state, .belowHardFloor)
        XCTAssertEqual(energy(2100, open: true, aQuantumOver).state, .soFar, "no judgement on an open day")
    }

    // MARK: - W1: amounts above Int.max

    /// Fault W1. `aggregate` admits any amount up to 1e100 (§6.4), so a stored total can exceed
    /// `Int.max`, and §7.4 and §7.5 define a state for every finite, non-negative amount. The
    /// functions must therefore return for such an amount; a plain `Int(_:)` conversion traps, which
    /// fails this test by crashing. The states and the fraction follow from §7.4 and §7.5. The exact
    /// whole numbers shown are not specified at this size, so only their direction is asserted.
    func testAmountsAboveIntMaxAreJudgedWithoutTrapping() {
        for grams in [1e19, 1e100, Double.greatestFiniteMagnitude] {
            let p = protein(grams)
            XCTAssertEqual(p.state, .above, "\(grams) g")
            XCTAssertEqual(p.grams, grams, "as given")
            XCTAssertEqual(p.ringFraction, 1, "\(grams) g")
            XCTAssertEqual(p.remainingGrams, 0, "\(grams) g")
            XCTAssertEqual(p.shownFloorGrams, 100, "\(grams) g")
            XCTAssertGreaterThan(p.shownGrams ?? 0, 100, "\(grams) g")
            XCTAssertGreaterThan(p.overGrams ?? 0, 0, "\(grams) g")
            XCTAssertTrue(IntakeProgress.meetsFloor(grams: grams, floorGrams: X.proteinFloorGrams))

            let unfloored = protein(grams, nil)
            XCTAssertEqual(unfloored.state, .noFloor, "\(grams) g")
            XCTAssertNotNil(unfloored.shownGrams, "§7.4: shownGrams is still set when grams are known")
        }

        for kcal in [1e19, 1e100, Double.greatestFiniteMagnitude] {
            for open in [false, true] {
                let e = energy(kcal, open: open)
                XCTAssertEqual(e.state, .aboveRange, "\(kcal) kcal, open \(open)")
                XCTAssertEqual(e.kcal, kcal, "as given")
                XCTAssertGreaterThan(e.shownKcal ?? 0, 2600, "\(kcal) kcal")
                XCTAssertGreaterThan(e.overHighEndKcal ?? 0, 0, "\(kcal) kcal")
            }
            let alone = IntakeProgress.energy(kcal: kcal, targets: IntakeTargets(), dayIsOpen: false)
            XCTAssertEqual(alone.state, .noRange, "\(kcal) kcal")
            XCTAssertNotNil(alone.shownKcal, "§7.5: the amount is shown alone")
        }
    }

    // MARK: - G21 (needs a ruling): a floor that is not finite

    /// G21 is NOT decided by the specification. §6.5 says `floorGrams` is reported "as given", which
    /// read literally returns NaN or infinity; the implementation reports nil so that no output holds
    /// a non-finite number. This test pins only what both readings share: the state is `noFloor`,
    /// nothing about the floor is shown, and `floorGrams` is either nil or the argument itself.
    func testANonFiniteFloorIsNoFloorAndIsNeverReportedAsAnotherNumber() {
        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            let p = protein(105, bad)
            XCTAssertEqual(p.state, .noFloor, "floor \(bad)")
            XCTAssertEqual(p.shownGrams, 105, "floor \(bad)")
            XCTAssertNil(p.shownFloorGrams, "floor \(bad)")
            XCTAssertNil(p.ringFraction, "floor \(bad)")
            if let reported = p.floorGrams {
                XCTAssertTrue(bad.isNaN ? reported.isNaN : reported == bad, "floor \(bad) reported as \(reported)")
            }
        }
    }

    // MARK: - E19 (needs a ruling): the distance to the low end on a closed day

    /// E19 is NOT decided by the specification. §7.5 gives `toLowEndKcal = ceil(low - k)` under
    /// `soFar` only; §6.5 describes the field as "> 0 only when a low end exists and the amount is
    /// under it", which names no state. This test pins only what both readings share: on a closed day
    /// under the low end the field is absent, zero, or exactly ceil(low - k), never another number.
    func testOnAClosedDayTheDistanceToTheLowEndIsAbsentZeroOrExact() {
        let belowRange = energy(2100, open: false)
        XCTAssertEqual(belowRange.state, .belowRange)
        XCTAssertTrue([nil, 0, 300].contains(belowRange.toLowEndKcal), "\(String(describing: belowRange.toLowEndKcal))")

        let belowHardFloor = energy(1500, open: false)
        XCTAssertEqual(belowHardFloor.state, .belowHardFloor)
        XCTAssertTrue([nil, 0, 900].contains(belowHardFloor.toLowEndKcal), "\(String(describing: belowHardFloor.toLowEndKcal))")
    }
}
