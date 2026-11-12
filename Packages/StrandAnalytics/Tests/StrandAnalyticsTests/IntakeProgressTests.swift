// API ASSUMED BY THESE TESTS
//
// Written before the implementation exists, from docs/personal/superapp/specs/stage-3.md §6.5, §7.4
// and §7.5. Every type, initialiser, member and function the tests in this file call:
//
//   public struct IntakeTargets: Equatable, Sendable {
//       public var proteinFloorGrams: Double?
//       public var energyLowKcal: Double?
//       public var energyHighKcal: Double?
//       public var energyHardFloorKcal: Double?
//       public init(proteinFloorGrams: Double? = nil, energyLowKcal: Double? = nil,
//                   energyHighKcal: Double? = nil, energyHardFloorKcal: Double? = nil)
//       public var isValid: Bool { get }
//   }
//
//   public enum IntakeProteinState: String, Sendable { case noFloor, notMeasured, below, atFloor, above }
//
//   public struct IntakeProteinProgress: Equatable, Sendable {     // read only; never constructed here
//       public let state: IntakeProteinState
//       public let grams: Double?
//       public let floorGrams: Double?
//       public let shownGrams: Int?
//       public let shownFloorGrams: Int?
//       public let remainingGrams: Int?
//       public let overGrams: Int?
//       public let ringFraction: Double?
//   }
//
//   public enum IntakeEnergyState: String, Sendable {
//       case notMeasured, noRange, soFar, belowHardFloor, belowRange, inRange, aboveRange
//   }
//
//   public struct IntakeEnergyProgress: Equatable, Sendable {      // read only
//       public let state: IntakeEnergyState
//       public let kcal: Double?
//       public let shownKcal: Int?
//       public let toLowEndKcal: Int?
//       public let overHighEndKcal: Int?
//   }
//
//   public enum IntakeProgress {
//       public static func meetsFloor(grams: Double, floorGrams: Double) -> Bool
//       public static func protein(grams: Double?, floorGrams: Double?) -> IntakeProteinProgress
//       public static func energy(kcal: Double?, targets: IntakeTargets, dayIsOpen: Bool) -> IntakeEnergyProgress
//   }
//
// Existing API used as the reference for the floor comparison (stage 1, already in the package):
//   CutScorecard.quantize(_:) -> Double
//   CutScorecard.evaluate(_:) -> CutScorecardResult, `.signals.protein.daysAtOrAboveFloor`, `.daysLogged`
//   CutScorecardInput, CutScorecardProteinDay, CutScorecardParameters.proteinFloorGrams
// Existing test helpers used: `IntakeFixture` (this stage) and `CutScorecardFixture`
// (`scenario(weights:proteinDays:parameters:)`, `protein(before:_:)`, `params(_:)`).

import XCTest
@testable import StrandAnalytics

private typealias X = IntakeFixture
private typealias F = CutScorecardFixture

/// `IntakeProgress` and `IntakeTargets`: protein against the floor and energy against the range
/// (`docs/personal/superapp/specs/stage-3.md` §6.5, §7.4, §7.5, test plan §12.1, fixture §13.4).
///
/// The Fixture Person's floor is 100 g, the range 2400 to 2600 kcal and the hard floor 2100 kcal. Every
/// threshold is tried at its value and one quantum (0.001) either side, so `>` for `>=`, a missing
/// quantize or a nudged bound fails here. Expected values were worked by hand from §7.4 and §7.5.
final class IntakeProgressTests: XCTestCase {

    // MARK: - Helpers

    private func protein(_ grams: Double?, _ floorGrams: Double? = X.proteinFloorGrams) -> IntakeProteinProgress {
        IntakeProgress.protein(grams: grams, floorGrams: floorGrams)
    }

    /// Assert every field of a measured protein reading against a usable floor.
    private func assertProtein(_ grams: Double, floor floorGrams: Double = X.proteinFloorGrams,
                               _ state: IntakeProteinState, shown: Int, shownFloor: Int = 100,
                               remaining: Int, over: Int, ring: Double,
                               file: StaticString = #filePath, line: UInt = #line) {
        let p = protein(grams, floorGrams)
        XCTAssertEqual(p.state, state, "state for \(grams) g", file: file, line: line)
        XCTAssertEqual(p.grams, grams, "grams are passed through as given", file: file, line: line)
        XCTAssertEqual(p.floorGrams, floorGrams, "the floor is passed through as given", file: file, line: line)
        XCTAssertEqual(p.shownGrams, shown, "shown grams for \(grams) g", file: file, line: line)
        XCTAssertEqual(p.shownFloorGrams, shownFloor, "shown floor for \(grams) g", file: file, line: line)
        XCTAssertEqual(p.remainingGrams, remaining, "remaining for \(grams) g", file: file, line: line)
        XCTAssertEqual(p.overGrams, over, "over for \(grams) g", file: file, line: line)
        guard let fraction = p.ringFraction else {
            return XCTFail("a measured amount against a floor has a ring (\(grams) g)", file: file, line: line)
        }
        XCTAssertEqual(fraction, ring, accuracy: 1e-12, "ring for \(grams) g", file: file, line: line)
    }

    /// The Fixture Person's targets (§13.1).
    private var targets: IntakeTargets {
        IntakeTargets(proteinFloorGrams: X.proteinFloorGrams, energyLowKcal: X.energyLowKcal,
                      energyHighKcal: X.energyHighKcal, energyHardFloorKcal: X.energyHardFloorKcal)
    }

    private func energy(_ kcal: Double?, open: Bool, _ t: IntakeTargets? = nil) -> IntakeEnergyProgress {
        IntakeProgress.energy(kcal: kcal, targets: t ?? targets, dayIsOpen: open)
    }

    /// A detail figure that does not apply in a state is nil or zero; the specification says only when
    /// it is positive. Either way it must not be positive.
    private func assertNotPositive(_ value: Int?, _ message: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value ?? 0, 0, message, file: file, line: line)
    }

    // MARK: - The floor predicate (§7.4)

    func testMeetsFloorIsInclusiveAtTheQuantizedFloor() {
        XCTAssertTrue(IntakeProgress.meetsFloor(grams: 100, floorGrams: 100))
        XCTAssertFalse(IntakeProgress.meetsFloor(grams: 99.999, floorGrams: 100))
        XCTAssertTrue(IntakeProgress.meetsFloor(grams: 100.001, floorGrams: 100))
        // Both sides are quantized to three decimals: 99.9996 reads as 100.000, 99.9994 as 99.999.
        XCTAssertTrue(IntakeProgress.meetsFloor(grams: 99.9996, floorGrams: 100))
        XCTAssertFalse(IntakeProgress.meetsFloor(grams: 99.9994, floorGrams: 100))
        XCTAssertTrue(IntakeProgress.meetsFloor(grams: 100, floorGrams: 100.0004))
        XCTAssertFalse(IntakeProgress.meetsFloor(grams: 100, floorGrams: 100.0006))
        XCTAssertTrue(IntakeProgress.meetsFloor(grams: 0, floorGrams: 0))
        XCTAssertFalse(IntakeProgress.meetsFloor(grams: 0, floorGrams: 0.001))
        // A value that is not a number meets nothing and is met by nothing.
        XCTAssertFalse(IntakeProgress.meetsFloor(grams: .nan, floorGrams: 100))
        XCTAssertFalse(IntakeProgress.meetsFloor(grams: 100, floorGrams: .nan))
    }

    func testMeetsFloorAgreesWithTheScorecardSignalOverASpread() {
        // Seven generated protein days per round, clustered within a few quanta of the floor so the
        // comparison's rounding is what is exercised. The scorecard's count of days at or above the
        // floor must equal the count `meetsFloor` gives, so the ring and the scorecard cannot disagree.
        var generator = X.Generator(state: 0x5EED_0304)
        let floors: [Double] = [100, 100, 100, 99.5, 120.25, 1, 150.0004, 0.001]
        var met = 0, missed = 0
        for round in 0..<400 {
            let floorGrams = floors[generator.next(floors.count)]
            let grams: [Double] = (0..<7).map { _ in
                switch generator.next(4) {
                case 0: return max(0, floorGrams + Double(generator.next(41) - 20) * 0.0001)   // sub-quantum
                case 1: return max(0, floorGrams + Double(generator.next(41) - 20) * 0.001)    // whole quanta
                case 2: return max(0, floorGrams + Double(generator.next(41) - 20))            // whole grams
                default: return Double(generator.next(300))
                }
            }
            let input = F.scenario(weights: [100.0, 99.2], proteinDays: F.protein(before: "2031-01-15", grams),
                                   parameters: F.params { $0.proteinFloorGrams = floorGrams })
            let signal = CutScorecard.evaluate(input).signals.protein
            XCTAssertEqual(signal.daysLogged, 7, "round \(round): every generated day must reach the signal")
            let expected = grams.filter { IntakeProgress.meetsFloor(grams: $0, floorGrams: floorGrams) }.count
            XCTAssertEqual(signal.daysAtOrAboveFloor, expected, "round \(round): floor \(floorGrams), grams \(grams)")
            for g in grams {
                let meets = IntakeProgress.meetsFloor(grams: g, floorGrams: floorGrams)
                XCTAssertEqual(meets, CutScorecard.quantize(g) >= CutScorecard.quantize(floorGrams),
                               "\(g) against \(floorGrams)")
                // The ring is complete exactly when the day counts toward the scorecard.
                let state = IntakeProgress.protein(grams: g, floorGrams: floorGrams).state
                XCTAssertEqual(state == .atFloor || state == .above, meets, "\(g) against \(floorGrams): \(state)")
                XCTAssertEqual(state == .below, !meets, "\(g) against \(floorGrams): \(state)")
                if meets { met += 1 } else { missed += 1 }
            }
        }
        // The spread must hold plenty of both outcomes or it proves nothing.
        XCTAssertGreaterThan(met, 500)
        XCTAssertGreaterThan(missed, 500)
    }

    // MARK: - Protein against the floor (§7.4, §13.4)

    func testBelowAtAndAboveTheFloor() {
        // §13.4, row by row.
        assertProtein(95, .below, shown: 95, remaining: 5, over: 0, ring: 0.95)
        assertProtein(99.9994, .below, shown: 99, remaining: 1, over: 0, ring: 0.99999)
        assertProtein(99.9996, .atFloor, shown: 100, remaining: 0, over: 0, ring: 1)
        assertProtein(100, .atFloor, shown: 100, remaining: 0, over: 0, ring: 1)
        assertProtein(105, .above, shown: 105, remaining: 0, over: 5, ring: 1)
        // One quantum either side of the floor.
        assertProtein(99.999, .below, shown: 99, remaining: 1, over: 0, ring: 0.99999)
        assertProtein(100.001, .atFloor, shown: 100, remaining: 0, over: 0, ring: 1)
        // `above` starts where the shown number passes the shown floor, one whole gram on.
        assertProtein(100.999, .atFloor, shown: 100, remaining: 0, over: 0, ring: 1)
        assertProtein(101, .above, shown: 101, remaining: 0, over: 1, ring: 1)
        assertProtein(100.9996, .above, shown: 101, remaining: 0, over: 1, ring: 1)
        // A measured zero is below the floor, not "not measured".
        assertProtein(0, .below, shown: 0, remaining: 100, over: 0, ring: 0)
        // The same at the smallest whole floor.
        assertProtein(0.999, floor: 1, .below, shown: 0, shownFloor: 1, remaining: 1, over: 0, ring: 0.999)
        assertProtein(1, floor: 1, .atFloor, shown: 1, shownFloor: 1, remaining: 0, over: 0, ring: 1)
        assertProtein(2, floor: 1, .above, shown: 2, shownFloor: 1, remaining: 0, over: 1, ring: 1)
    }

    func testRingIsCompleteAtTheFloorAndStaysComplete() {
        for grams in [100.0, 100.001, 100.5, 101, 105, 150, 200, 250, 1000, 99.9996] {
            let p = protein(grams)
            XCTAssertEqual(p.ringFraction, 1, "\(grams) g: complete, with no second lap")
        }
        // Below the floor the ring is the quantized share and never reaches 1.
        for grams in [0.0, 1, 50, 95, 99.5, 99.999, 99.9994] {
            guard let fraction = protein(grams).ringFraction else { return XCTFail("\(grams) g has a ring") }
            XCTAssertEqual(fraction, CutScorecard.quantize(grams) / 100, accuracy: 1e-12, "\(grams) g")
            XCTAssertLessThan(fraction, 1, "\(grams) g")
            XCTAssertGreaterThanOrEqual(fraction, 0, "\(grams) g")
        }
        // Over a generated spread of amounts and floors the fraction is always within 0 ... 1.
        var generator = X.Generator(state: 0x5EED_0305)
        for _ in 0..<500 {
            let floorGrams = Double(1 + generator.next(400))
            let grams = Double(generator.next(900_000)) / 1000
            guard let fraction = protein(grams, floorGrams).ringFraction else {
                return XCTFail("\(grams) g against \(floorGrams) g has a ring")
            }
            XCTAssertTrue((0...1).contains(fraction), "\(grams) g against \(floorGrams) g: \(fraction)")
            XCTAssertEqual(fraction == 1, IntakeProgress.meetsFloor(grams: grams, floorGrams: floorGrams),
                           "\(grams) g against \(floorGrams) g")
        }
    }

    func testGramsKeepCountingPastTheFloor() {
        assertProtein(150, .above, shown: 150, remaining: 0, over: 50, ring: 1)
        assertProtein(250, .above, shown: 250, remaining: 0, over: 150, ring: 1)
        assertProtein(250.7, .above, shown: 250, remaining: 0, over: 150, ring: 1)
        assertProtein(1000, .above, shown: 1000, remaining: 0, over: 900, ring: 1)
        // Each further gram shows: the number is never held at the floor.
        var last = 100
        for grams in stride(from: 101.0, through: 140.0, by: 1.0) {
            let p = protein(grams)
            XCTAssertEqual(p.shownGrams, last + 1)
            XCTAssertEqual(p.overGrams, last + 1 - 100)
            XCTAssertEqual(p.grams, grams)
            last += 1
        }
    }

    func testNoFloorHidesTheRingButKeepsTheNumber() {
        let p = protein(105, nil)
        XCTAssertEqual(p.state, .noFloor)
        XCTAssertEqual(p.grams, 105)
        XCTAssertEqual(p.shownGrams, 105)
        XCTAssertNil(p.floorGrams)
        XCTAssertNil(p.shownFloorGrams)
        XCTAssertNil(p.ringFraction)
        assertNotPositive(p.remainingGrams, "nothing remains against a floor that is not set")
        assertNotPositive(p.overGrams, "nothing is over a floor that is not set")
        // A measured zero keeps its number too.
        let zero = protein(0, nil)
        XCTAssertEqual(zero.state, .noFloor)
        XCTAssertEqual(zero.shownGrams, 0)
        XCTAssertNil(zero.ringFraction)
        XCTAssertEqual(protein(105.4, nil).shownGrams, 105)
    }

    func testNoFloorWithNothingMeasuredShowsNoNumber() {
        // SPEC-AMBIGUITY: §7.4 lists `noFloor` before `notMeasured` and does not say which wins when
        // there is neither a floor nor an amount. The listed order is followed (`noFloor`); what both
        // readings share, and what the rulings require, is that no number and no ring appear.
        for grams in [nil, Double.nan, Double.infinity, -1] as [Double?] {
            let p = protein(grams, nil)
            XCTAssertEqual(p.state, .noFloor, "\(String(describing: grams))")
            XCTAssertNil(p.shownGrams, "\(String(describing: grams)): not measured is never shown as a number")
            XCTAssertNil(p.ringFraction)
            XCTAssertNil(p.shownFloorGrams)
        }
    }

    func testAZeroOrNegativeFloorIsNoFloor() {
        // SPEC-AMBIGUITY: §7.4 says an unusable floor is `noFloor` with no ring, and does not say what
        // `shownFloorGrams` holds then. It is read as nil: a floor that is not a floor is never printed.
        for floorGrams in [0, -0.0, -1, -100, -0.001, Double.nan, Double.infinity, -Double.infinity] {
            let p = protein(105, floorGrams)
            XCTAssertEqual(p.state, .noFloor, "floor \(floorGrams)")
            XCTAssertEqual(p.shownGrams, 105, "floor \(floorGrams): the number is kept")
            XCTAssertNil(p.ringFraction, "floor \(floorGrams)")
            XCTAssertNil(p.shownFloorGrams, "floor \(floorGrams): an unusable floor is never printed")
            assertNotPositive(p.remainingGrams, "floor \(floorGrams)")
            assertNotPositive(p.overGrams, "floor \(floorGrams)")
        }
        // The smallest whole floor is a floor.
        XCTAssertEqual(protein(105, 1).state, .above)
        XCTAssertEqual(protein(0, 1).state, .below)
    }

    func testNotMeasuredHasNoNumberAndNoRing() {
        let p = protein(nil)
        XCTAssertEqual(p.state, .notMeasured)
        XCTAssertNil(p.grams)
        XCTAssertNil(p.shownGrams, "not measured is never zero")
        XCTAssertNil(p.ringFraction)
        XCTAssertEqual(p.floorGrams, 100, "the floor is passed through as given")
        assertNotPositive(p.remainingGrams, "no remaining figure without a measurement")
        assertNotPositive(p.overGrams, "no over figure without a measurement")
        // An amount that is not a usable number is not a measurement.
        for grams in [Double.nan, .infinity, -.infinity, -1, -0.001, -100] {
            let bad = protein(grams)
            XCTAssertEqual(bad.state, .notMeasured, "\(grams)")
            XCTAssertNil(bad.shownGrams, "\(grams)")
            XCTAssertNil(bad.ringFraction, "\(grams)")
            assertNotPositive(bad.remainingGrams, "\(grams)")
            assertNotPositive(bad.overGrams, "\(grams)")
        }
        // Zero is a measurement.
        XCTAssertEqual(protein(0).state, .below)
        XCTAssertEqual(protein(0).shownGrams, 0)
    }

    func testRemainingIsNeverZeroBeforeTheFloorIsMet() {
        // Amounts whose distance to the floor would round to zero if it were rounded to nearest.
        for grams in [99.5, 99.6, 99.9, 99.99, 99.999, 99.9994, 99.4999] {
            let p = protein(grams)
            XCTAssertEqual(p.state, .below, "\(grams) g")
            XCTAssertEqual(p.shownGrams, 99, "\(grams) g is shown rounded down")
            XCTAssertEqual(p.remainingGrams, 1, "\(grams) g")
        }
        // Rounded down, never to nearest, further from the floor as well.
        XCTAssertEqual(protein(95.7).shownGrams, 95)
        XCTAssertEqual(protein(95.7).remainingGrams, 5)
        XCTAssertEqual(protein(0.4).remainingGrams, 100)
        // And once the floor is met, exactly zero remains.
        for grams in [99.9996, 100, 100.001, 100.6, 250] {
            XCTAssertEqual(protein(grams).remainingGrams, 0, "\(grams) g")
        }
        // Generated amounts and floors, whole and fractional: below the floor, at least one gram remains.
        var generator = X.Generator(state: 0x5EED_0306)
        var belowSeen = 0
        for _ in 0..<1000 {
            let floorGrams = Double(1_000 + generator.next(399_000)) / 1000        // 1.000 ... 399.999
            let grams = max(0, floorGrams - Double(generator.next(3_000)) / 1000 + 1)
            let p = protein(grams, floorGrams)
            if p.state == .below {
                belowSeen += 1
                XCTAssertGreaterThanOrEqual(p.remainingGrams ?? 0, 1, "\(grams) g against \(floorGrams) g")
                XCTAssertEqual(p.overGrams ?? 0, 0, "\(grams) g against \(floorGrams) g")
            } else {
                XCTAssertEqual(p.remainingGrams, 0, "\(grams) g against \(floorGrams) g")
            }
        }
        XCTAssertGreaterThan(belowSeen, 300)
    }

    func testShownGramsPlusRemainingEqualsTheShownFloor() {
        var generator = X.Generator(state: 0x5EED_0307)
        var checked = 0
        for _ in 0..<1000 {
            let floorGrams = Double(1 + generator.next(400))                       // a whole floor
            let grams = Double(generator.next(Int(floorGrams) * 1000)) / 1000      // 0 ..< floor, to the quantum
            let p = protein(grams, floorGrams)
            XCTAssertEqual(p.state, .below, "\(grams) g against \(floorGrams) g")
            guard let shown = p.shownGrams, let remaining = p.remainingGrams, let shownFloor = p.shownFloorGrams else {
                XCTFail("\(grams) g against \(floorGrams) g: a below reading has all three figures")
                continue
            }
            XCTAssertEqual(shown + remaining, shownFloor, "\(grams) g against \(floorGrams) g")
            XCTAssertEqual(shownFloor, Int(floorGrams))
            checked += 1
        }
        XCTAssertEqual(checked, 1000)
        // The fixture's own rows.
        XCTAssertEqual((protein(95).shownGrams ?? 0) + (protein(95).remainingGrams ?? 0), 100)
        XCTAssertEqual((protein(99.9994).shownGrams ?? 0) + (protein(99.9994).remainingGrams ?? 0), 100)
    }

    func testShownFloorEqualsTheStoredFloorForEveryWholeValue() {
        for whole in 1...400 {
            let floorGrams = Double(whole)
            for grams in [50.0, 0, 400.5] {
                let p = protein(grams, floorGrams)
                XCTAssertEqual(p.shownFloorGrams, whole, "floor \(whole), \(grams) g")
                XCTAssertEqual(p.shownFloorGrams, Int(floorGrams.rounded()), "floor \(whole), \(grams) g")
                XCTAssertEqual(p.floorGrams, floorGrams)
            }
        }
    }

    func testAFractionalFloorIsShownRoundedUp() {
        // The pure function's defined behaviour for an argument no caller passes (§7.4): the floor is
        // shown rounded up, so the printed floor is never under the real one.
        assertProtein(99.4, floor: 99.5, .below, shown: 99, shownFloor: 100, remaining: 1, over: 0,
                      ring: 99.4 / 99.5)
        assertProtein(100.2, floor: 100.4, .below, shown: 100, shownFloor: 101, remaining: 1, over: 0,
                      ring: 100.2 / 100.4)
        // Met by the comparison, and the shown number has not passed the shown floor: at the floor.
        assertProtein(99.5, floor: 99.5, .atFloor, shown: 99, shownFloor: 100, remaining: 0, over: 0, ring: 1)
        assertProtein(100.4, floor: 100.4, .atFloor, shown: 100, shownFloor: 101, remaining: 0, over: 0, ring: 1)
        assertProtein(102, floor: 100.4, .above, shown: 102, shownFloor: 101, remaining: 0, over: 1, ring: 1)
    }

    func testProteinProgressIsDeterministic() {
        for grams in [nil, 0, 95, 99.9994, 100, 105] as [Double?] {
            for floorGrams in [nil, 0, 100] as [Double?] {
                XCTAssertEqual(protein(grams, floorGrams), protein(grams, floorGrams))
            }
        }
    }

    // MARK: - Energy against the range (§7.5, §13.4)

    func testEnergyNotMeasuredHasNoNumber() {
        for open in [true, false] {
            let e = energy(nil, open: open)
            XCTAssertEqual(e.state, .notMeasured)
            XCTAssertNil(e.kcal)
            XCTAssertNil(e.shownKcal, "not measured is never zero")
            assertNotPositive(e.toLowEndKcal, "no distance to the low end without a measurement")
            assertNotPositive(e.overHighEndKcal, "nothing over without a measurement")
            // The same with no range at all.
            XCTAssertEqual(energy(nil, open: open, IntakeTargets()).state, .notMeasured)
        }
    }

    func testEnergyThatIsNotAUsableNumberIsNotMeasured() {
        // SPEC-AMBIGUITY: §7.5 names only nil as `notMeasured`. §7.4 treats a non-finite or negative
        // protein amount as not measured, and the rulings forbid showing an unmeasured figure as a
        // number, so the same reading is taken for energy.
        for kcal in [Double.nan, .infinity, -.infinity, -1, -0.001] {
            for open in [true, false] {
                let e = energy(kcal, open: open)
                XCTAssertEqual(e.state, .notMeasured, "\(kcal) kcal")
                XCTAssertNil(e.shownKcal, "\(kcal) kcal")
                assertNotPositive(e.toLowEndKcal, "\(kcal) kcal")
                assertNotPositive(e.overHighEndKcal, "\(kcal) kcal")
            }
        }
    }

    func testEnergySoFarMakesNoJudgementWhileTheDayIsOpen() {
        let e = energy(1450, open: true)
        XCTAssertEqual(e.state, .soFar)
        XCTAssertEqual(e.kcal, 1450)
        XCTAssertEqual(e.shownKcal, 1450)
        XCTAssertEqual(e.toLowEndKcal, 950)
        assertNotPositive(e.overHighEndKcal, "an amount under the low end is not over the high end")
        // Under the hard floor, at it, and between it and the low end: an open day is only ever "so far".
        for kcal in [0.0, 1, 1500, 2099.999, 2100, 2399, 2399.999] {
            XCTAssertEqual(energy(kcal, open: true).state, .soFar, "\(kcal) kcal on an open day")
        }
        XCTAssertEqual(energy(0, open: true).toLowEndKcal, 2400)
        XCTAssertEqual(energy(0, open: true).shownKcal, 0, "a measured zero is shown")
        // The distance is rounded up, so it is never zero before the low end is reached.
        XCTAssertEqual(energy(2399.999, open: true).toLowEndKcal, 1)
        XCTAssertEqual(energy(2399.5, open: true).toLowEndKcal, 1)
        XCTAssertEqual(energy(2398.2, open: true).toLowEndKcal, 2)
        // At the low end the open day is in range: `soFar` is strictly under it.
        XCTAssertEqual(energy(2400, open: true).state, .inRange)
        XCTAssertEqual(energy(2399.9996, open: true).state, .inRange, "quantized to 2400.000")
        XCTAssertEqual(energy(2400.001, open: true).state, .inRange)
        assertNotPositive(energy(2400, open: true).toLowEndKcal, "nothing left to the low end at the low end")
        // With no low end there is nothing to be under: an open day with only a high end is in range.
        let highOnly = IntakeTargets(energyHighKcal: 2600)
        XCTAssertEqual(energy(100, open: true, highOnly).state, .inRange)
    }

    func testEnergyAboveRangeIsReportedEvenWhileOpen() {
        let open = energy(2700, open: true)
        XCTAssertEqual(open.state, .aboveRange)
        XCTAssertEqual(open.overHighEndKcal, 100)
        XCTAssertEqual(open.shownKcal, 2700)
        assertNotPositive(open.toLowEndKcal, "an amount over the high end is not under the low end")
        let closed = energy(2601, open: false)
        XCTAssertEqual(closed.state, .aboveRange)
        XCTAssertEqual(closed.overHighEndKcal, 1)
        // The high end is inclusive, open or closed; one quantum over is above, rounded up to 1.
        for isOpen in [true, false] {
            XCTAssertEqual(energy(2600, open: isOpen).state, .inRange)
            XCTAssertEqual(energy(2600.0004, open: isOpen).state, .inRange, "quantized to 2600.000")
            assertNotPositive(energy(2600, open: isOpen).overHighEndKcal, "at the high end nothing is over")
            let over = energy(2600.001, open: isOpen)
            XCTAssertEqual(over.state, .aboveRange)
            XCTAssertEqual(over.overHighEndKcal, 1)
            XCTAssertEqual(energy(2600.5, open: isOpen).overHighEndKcal, 1)
            XCTAssertEqual(energy(2601.2, open: isOpen).overHighEndKcal, 2)
        }
        // A high end alone is enough.
        let highOnly = IntakeTargets(energyHighKcal: 2600)
        XCTAssertEqual(energy(2700, open: true, highOnly).state, .aboveRange)
        XCTAssertEqual(energy(2700, open: true, highOnly).overHighEndKcal, 100)
    }

    func testEnergyBelowHardFloorOnlyOnAClosedDay() {
        XCTAssertEqual(energy(1500, open: false).state, .belowHardFloor)
        XCTAssertEqual(energy(1500, open: true).state, .soFar, "no note about the hard floor while the day is open")
        XCTAssertEqual(energy(0, open: false).state, .belowHardFloor)
        XCTAssertEqual(energy(0, open: true).state, .soFar)
        // The hard floor itself is not below it; one quantum under is.
        XCTAssertEqual(energy(2099.999, open: false).state, .belowHardFloor)
        XCTAssertEqual(energy(2100, open: false).state, .belowRange)
        XCTAssertEqual(energy(2100.001, open: false).state, .belowRange)
        XCTAssertEqual(energy(2099.9996, open: false).state, .belowRange, "quantized to 2100.000")
        XCTAssertEqual(energy(2099.9994, open: false).state, .belowHardFloor, "quantized to 2099.999")
        XCTAssertEqual(energy(1500, open: false).shownKcal, 1500)
        // Without a hard floor a closed low day is simply below the range.
        let noHardFloor = IntakeTargets(energyLowKcal: 2400, energyHighKcal: 2600)
        XCTAssertEqual(energy(1500, open: false, noHardFloor).state, .belowRange)
        XCTAssertEqual(energy(0, open: false, noHardFloor).state, .belowRange)
        // A hard floor with only a high end still applies to a closed day.
        let highAndFloor = IntakeTargets(energyHighKcal: 2600, energyHardFloorKcal: 2100)
        XCTAssertEqual(energy(1500, open: false, highAndFloor).state, .belowHardFloor)
        XCTAssertEqual(energy(2100, open: false, highAndFloor).state, .inRange)
        XCTAssertEqual(energy(1500, open: true, highAndFloor).state, .inRange)
    }

    func testEnergyBelowRangeInRangeAndBoundsAreInclusive() {
        // §13.4, the closed rows.
        XCTAssertEqual(energy(2100, open: false).state, .belowRange)
        XCTAssertEqual(energy(2400, open: false).state, .inRange)
        XCTAssertEqual(energy(2600, open: false).state, .inRange)
        XCTAssertEqual(energy(2601, open: false).state, .aboveRange)
        // One quantum either side of each end.
        XCTAssertEqual(energy(2399.999, open: false).state, .belowRange)
        XCTAssertEqual(energy(2400.001, open: false).state, .inRange)
        XCTAssertEqual(energy(2599.999, open: false).state, .inRange)
        XCTAssertEqual(energy(2600.001, open: false).state, .aboveRange)
        XCTAssertEqual(energy(2500, open: false).state, .inRange)
        XCTAssertEqual(energy(2500, open: true).state, .inRange)
        // Comparison is on quantized values.
        XCTAssertEqual(energy(2399.9996, open: false).state, .inRange)
        XCTAssertEqual(energy(2399.9994, open: false).state, .belowRange)
        let inRange = energy(2400, open: false)
        assertNotPositive(inRange.toLowEndKcal, "in range, nothing is left to the low end")
        assertNotPositive(inRange.overHighEndKcal, "in range, nothing is over")
        XCTAssertEqual(inRange.shownKcal, 2400)
        // A range of one value is a range: only that value is inside.
        let point = IntakeTargets(energyLowKcal: 2500, energyHighKcal: 2500)
        XCTAssertTrue(point.isValid)
        XCTAssertEqual(energy(2499.999, open: false, point).state, .belowRange)
        XCTAssertEqual(energy(2500, open: false, point).state, .inRange)
        XCTAssertEqual(energy(2500.001, open: false, point).state, .aboveRange)
        // Either end alone.
        let lowOnly = IntakeTargets(energyLowKcal: 2400)
        XCTAssertEqual(energy(2399.999, open: false, lowOnly).state, .belowRange)
        XCTAssertEqual(energy(2400, open: false, lowOnly).state, .inRange)
        XCTAssertEqual(energy(9000, open: false, lowOnly).state, .inRange)
        XCTAssertEqual(energy(2399.999, open: true, lowOnly).state, .soFar)
        let highOnly = IntakeTargets(energyHighKcal: 2600)
        XCTAssertEqual(energy(0, open: false, highOnly).state, .inRange)
        XCTAssertEqual(energy(2600, open: false, highOnly).state, .inRange)
        XCTAssertEqual(energy(2600.001, open: false, highOnly).state, .aboveRange)
    }

    func testEnergyShownKcalIsRoundedToTheNearestWhole() {
        XCTAssertEqual(energy(1450.4, open: true).shownKcal, 1450)
        XCTAssertEqual(energy(1450.5, open: true).shownKcal, 1451)
        XCTAssertEqual(energy(1450.6, open: false).shownKcal, 1451)
        XCTAssertEqual(energy(2500.49, open: false).shownKcal, 2500)
        XCTAssertEqual(energy(1450.4, open: true).kcal, 1450.4, "the amount is passed through as given")
    }

    func testEnergyWithNoRangeShowsTheAmountAlone() {
        for t in [IntakeTargets(), IntakeTargets(proteinFloorGrams: 100),
                  IntakeTargets(energyHardFloorKcal: 2100)] {
            for open in [true, false] {
                for kcal in [0.0, 1450, 5000] {
                    let e = energy(kcal, open: open, t)
                    XCTAssertEqual(e.state, .noRange, "\(kcal) kcal")
                    XCTAssertEqual(e.kcal, kcal)
                    XCTAssertEqual(e.shownKcal, Int(kcal))
                    assertNotPositive(e.toLowEndKcal, "no low end exists")
                    assertNotPositive(e.overHighEndKcal, "no high end exists")
                }
            }
        }
        XCTAssertEqual(energy(1450.5, open: true, IntakeTargets()).shownKcal, 1451)
    }

    func testInvalidTargetsBehaveAsNoRange() {
        let invalid = [
            IntakeTargets(energyLowKcal: 2600, energyHighKcal: 2400),                              // low above high
            IntakeTargets(energyLowKcal: 2400, energyHighKcal: 2600, energyHardFloorKcal: 2500),   // floor above low
            IntakeTargets(energyLowKcal: -2400, energyHighKcal: 2600),
            IntakeTargets(energyLowKcal: 2400, energyHighKcal: .nan),
            IntakeTargets(energyLowKcal: 0, energyHighKcal: 2600),
            IntakeTargets(proteinFloorGrams: -1, energyLowKcal: 2400, energyHighKcal: 2600),
        ]
        for (index, t) in invalid.enumerated() {
            XCTAssertFalse(t.isValid, "targets \(index)")
            for open in [true, false] {
                for kcal in [1450.0, 2500, 2700] {
                    let e = energy(kcal, open: open, t)
                    XCTAssertEqual(e.state, .noRange, "targets \(index), \(kcal) kcal")
                    XCTAssertEqual(e.shownKcal, Int(kcal), "targets \(index): the amount is still shown")
                    assertNotPositive(e.toLowEndKcal, "targets \(index)")
                    assertNotPositive(e.overHighEndKcal, "targets \(index)")
                }
                XCTAssertEqual(energy(nil, open: open, t).state, .notMeasured, "targets \(index)")
            }
        }
    }

    func testTargetsValidityRules() {
        XCTAssertTrue(IntakeTargets().isValid, "nothing set is valid")
        XCTAssertTrue(targets.isValid, "the fixture's targets")
        XCTAssertTrue(IntakeTargets(energyLowKcal: 2400).isValid)
        XCTAssertTrue(IntakeTargets(energyHighKcal: 2600).isValid)
        XCTAssertTrue(IntakeTargets(energyHardFloorKcal: 2100).isValid)
        XCTAssertTrue(IntakeTargets(proteinFloorGrams: 100).isValid)

        // Each field alone: not finite, not positive, above the arithmetic limit.
        let setters: [(String, (inout IntakeTargets, Double) -> Void)] = [
            ("proteinFloorGrams", { $0.proteinFloorGrams = $1 }),
            ("energyLowKcal", { $0.energyLowKcal = $1 }),
            ("energyHighKcal", { $0.energyHighKcal = $1 }),
            ("energyHardFloorKcal", { $0.energyHardFloorKcal = $1 }),
        ]
        for (name, set) in setters {
            for bad in [0, -0.0, -1, -0.001, Double.nan, .infinity, -.infinity, (1e100).nextUp, .greatestFiniteMagnitude] {
                var t = IntakeTargets()
                set(&t, bad)
                XCTAssertFalse(t.isValid, "\(name) = \(bad)")
            }
            for good in [0.001, 1, 2400, 1e100, Double.leastNonzeroMagnitude] {
                var t = IntakeTargets()
                set(&t, good)
                XCTAssertTrue(t.isValid, "\(name) = \(good)")
            }
        }

        // Low against high: equal is valid, low above high is not.
        XCTAssertTrue(IntakeTargets(energyLowKcal: 2600, energyHighKcal: 2600).isValid)
        XCTAssertTrue(IntakeTargets(energyLowKcal: 2599.999, energyHighKcal: 2600).isValid)
        XCTAssertFalse(IntakeTargets(energyLowKcal: 2600.001, energyHighKcal: 2600).isValid)
        XCTAssertFalse(IntakeTargets(energyLowKcal: 2601, energyHighKcal: 2600).isValid)

        // Hard floor against the low end: equal is valid, above is not.
        XCTAssertTrue(IntakeTargets(energyLowKcal: 2400, energyHighKcal: 2600, energyHardFloorKcal: 2400).isValid)
        XCTAssertTrue(IntakeTargets(energyLowKcal: 2400, energyHighKcal: 2600, energyHardFloorKcal: 2399.999).isValid)
        XCTAssertFalse(IntakeTargets(energyLowKcal: 2400, energyHighKcal: 2600, energyHardFloorKcal: 2400.001).isValid)
        XCTAssertFalse(IntakeTargets(energyLowKcal: 2400, energyHardFloorKcal: 2401).isValid)

        // One bad field spoils an otherwise valid set.
        var spoiled = targets
        spoiled.energyHardFloorKcal = .nan
        XCTAssertFalse(spoiled.isValid)
        spoiled = targets
        spoiled.proteinFloorGrams = 0
        XCTAssertFalse(spoiled.isValid)

        // Value semantics: equal fields are equal targets.
        XCTAssertEqual(targets, IntakeTargets(proteinFloorGrams: 100, energyLowKcal: 2400,
                                              energyHighKcal: 2600, energyHardFloorKcal: 2100))
        XCTAssertNotEqual(targets, IntakeTargets(proteinFloorGrams: 100, energyLowKcal: 2400, energyHighKcal: 2600))
    }

    func testEnergyProgressIsDeterministic() {
        for kcal in [nil, 0, 1450, 2100, 2400, 2600, 2700] as [Double?] {
            for open in [true, false] {
                XCTAssertEqual(energy(kcal, open: open), energy(kcal, open: open))
            }
        }
    }

    func testFixtureEnergyRows() {
        // §13.4's energy table, every row, in order.
        XCTAssertEqual(energy(nil, open: true).state, .notMeasured)
        XCTAssertEqual(energy(nil, open: false).state, .notMeasured)
        XCTAssertEqual(energy(1450, open: true).state, .soFar)
        XCTAssertEqual(energy(1450, open: true).toLowEndKcal, 950)
        XCTAssertEqual(energy(2700, open: true).state, .aboveRange)
        XCTAssertEqual(energy(2700, open: true).overHighEndKcal, 100)
        XCTAssertEqual(energy(1500, open: false).state, .belowHardFloor)
        XCTAssertEqual(energy(2100, open: false).state, .belowRange)
        XCTAssertEqual(energy(2400, open: false).state, .inRange)
        XCTAssertEqual(energy(2600, open: false).state, .inRange)
        XCTAssertEqual(energy(2601, open: false).state, .aboveRange)
        XCTAssertEqual(energy(2601, open: false).overHighEndKcal, 1)
    }
}
