import XCTest
@testable import StrandAnalytics

private typealias F = CutScorecardFixture

/// `CutScorecard.evaluate`: the four signals of `docs/personal/superapp/specs/stage-1.md` §7.5: waist,
/// working weights, protein floor and rate band. Every threshold is tried exactly at its value and one
/// quantum (0.001) either side, so `<` for `<=` or a nudged threshold fails here.
///
/// Unless a test says otherwise the judged week is fixture week 2, weighed on Wednesday 2031-01-15, under
/// the fixture parameters: waist window 2 weeks with a 0.5 cm minimum, lift tolerance 5 % and share 0.5,
/// protein floor 100 g on 5 days.
final class CutScorecardSignalTests: XCTestCase {

    /// The weigh-in day of the judged week in the two-week scenarios below.
    private let anchor = "2031-01-15"
    private let twoWeeks: [Double?] = [100.0, 99.2]

    private func evaluate(_ input: CutScorecardInput) -> CutScorecardResult {
        CutScorecard.evaluate(input)
    }

    /// The waist signal of the last week of a scenario with ordinary weigh-ins every week.
    private func waistSignal(_ waists: [Double?], parameters: CutScorecardParameters = F.parameters,
                             phase: CutScorecardPhase = F.phase) -> CutScorecardWaistSignal {
        let weights: [Double?] = (0..<waists.count).map { 100.0 - 0.8 * Double($0) }
        return evaluate(F.scenario(weights: weights, waists: waists, phase: phase, parameters: parameters)).signals.waist
    }

    /// The lift signal of week 2 for lift observations given as (days before the weigh-in, exercise, kg).
    private func liftSignal(_ sets: [(Int, String, Double)],
                            parameters: CutScorecardParameters = F.parameters) -> CutScorecardLiftSignal {
        let lifts = sets.map { CutScorecardLiftObservation(day: F.day(anchor, -$0.0), exercise: $0.1, weightKg: $0.2) }
        return evaluate(F.scenario(weights: twoWeeks, lifts: lifts, parameters: parameters)).signals.lifts
    }

    /// The lift signal of week 2 for one exercise: `previous` kg nine days before the weigh-in, `current`
    /// kg two days before it.
    private func pressSignal(previous: Double, current: Double,
                             parameters: CutScorecardParameters = F.parameters) -> CutScorecardLiftSignal {
        liftSignal([(9, F.pressName, previous), (2, F.pressName, current)], parameters: parameters)
    }

    /// The protein signal of week 2 for the seven days before the weigh-in, oldest first.
    private func proteinSignal(_ grams: [Double?],
                               parameters: CutScorecardParameters = F.parameters) -> CutScorecardProteinSignal {
        evaluate(F.scenario(weights: twoWeeks, proteinDays: F.protein(before: anchor, grams),
                            parameters: parameters)).signals.protein
    }

    // MARK: - Waist

    /// Fault F12: comparing with the previous week only would call the first case flat.
    func testWaistShrinkingComparesWithEarliestReadingInWindow() {
        // Weeks 1 to 3. The window of week 3 is weeks 1 and 2; the earliest is week 1.
        XCTAssertEqual(waistSignal([100.0, 99.0, 99.0]),
                       CutScorecardWaistSignal(state: .met, reason: .shrinking, currentCm: 99.0, referenceCm: 100.0,
                                               referenceWeekStart: "2031-01-06", changeCm: -1.0))
        // Weeks 1 to 4. Week 1 has left the two-week window of week 4; the earliest inside it is week 2.
        XCTAssertEqual(waistSignal([100.0, 99.0, 99.0, 99.0]),
                       CutScorecardWaistSignal(state: .notMet, reason: .notShrinking, currentCm: 99.0, referenceCm: 99.0,
                                               referenceWeekStart: "2031-01-13", changeCm: 0.0))
        // Earliest by week, not the largest value in the window: week 1's 98.0, not week 2's 100.0.
        XCTAssertEqual(waistSignal([98.0, 100.0, 99.4]),
                       CutScorecardWaistSignal(state: .notMet, reason: .notShrinking, currentCm: 99.4, referenceCm: 98.0,
                                               referenceWeekStart: "2031-01-06", changeCm: 1.4))
        // A week without a waist reading inside the window is skipped, not treated as the reference.
        XCTAssertEqual(waistSignal([100.0, nil, 99.0]).referenceWeekStart, "2031-01-06")
        XCTAssertEqual(waistSignal([nil, 100.0, 99.0]).referenceWeekStart, "2031-01-13")
    }

    func testFlatWaistIsNotMet() {
        XCTAssertEqual(waistSignal([100.0, 100.0]),
                       CutScorecardWaistSignal(state: .notMet, reason: .notShrinking, currentCm: 100.0, referenceCm: 100.0,
                                               referenceWeekStart: "2031-01-06", changeCm: 0.0))
        // Flat stays not met under the generic minimum of 0.1 cm as well.
        XCTAssertEqual(waistSignal([100.0, 100.0], parameters: F.params { $0.waistMinDecreaseCm = 0.1 }).state, .notMet)
        // A growing waist is not met either.
        let growing = waistSignal([100.0, 100.5])
        XCTAssertEqual(growing.state, .notMet)
        XCTAssertEqual(growing.changeCm, 0.5)
    }

    /// The minimum is 0.5 cm and the comparison is `change <= -minimum`.
    func testWaistDecreaseBelowMinimumIsNotMet() {
        let oneQuantumShort = waistSignal([100.0, 99.501])
        XCTAssertEqual(oneQuantumShort.changeCm, -0.499)
        XCTAssertEqual(oneQuantumShort.state, .notMet)
        XCTAssertEqual(oneQuantumShort.reason, .notShrinking)

        let exactly = waistSignal([100.0, 99.5])
        XCTAssertEqual(exactly.changeCm, -0.5)
        XCTAssertEqual(exactly.state, .met)
        XCTAssertEqual(exactly.reason, .shrinking)

        let oneQuantumOver = waistSignal([100.0, 99.499])
        XCTAssertEqual(oneQuantumOver.changeCm, -0.501)
        XCTAssertEqual(oneQuantumOver.state, .met)

        // The minimum is the parameter, not a literal: at 0.499 the short case is met, at 0.501 the exact
        // case is not.
        XCTAssertEqual(waistSignal([100.0, 99.501], parameters: F.params { $0.waistMinDecreaseCm = 0.499 }).state, .met)
        XCTAssertEqual(waistSignal([100.0, 99.5], parameters: F.params { $0.waistMinDecreaseCm = 0.501 }).state, .notMet)
    }

    func testWaistMissingThisWeekIsUnknownNotZero() {
        let result = evaluate(F.scenario(weights: twoWeeks, waists: [100.0, nil]))
        XCTAssertEqual(result.signals.waist.state, .unknown)
        XCTAssertEqual(result.signals.waist.reason, .noWaistThisWeek)
        XCTAssertNil(result.signals.waist.currentCm)
        XCTAssertNil(result.signals.waist.changeCm, "a missing reading is not a change of zero")
        XCTAssertNil(result.weeks.last?.waistCm)
        XCTAssertNil(result.weeks.last?.waistDay)
    }

    func testWaistWithNoEarlierReadingInTheWindowIsUnknown() {
        // Only this week's reading exists.
        let first = waistSignal([nil, 99.5])
        XCTAssertEqual(first.state, .unknown)
        XCTAssertEqual(first.reason, .noEarlierWaist)
        XCTAssertEqual(first.currentCm, 99.5)
        XCTAssertNil(first.referenceCm)
        XCTAssertNil(first.referenceWeekStart)
        XCTAssertNil(first.changeCm)
        // An earlier reading exists but lies before the two-week window of week 4.
        XCTAssertEqual(waistSignal([100.0, nil, nil, 98.5]).reason, .noEarlierWaist)
        // An earlier reading exists inside the window but before the phase: the window is clipped.
        XCTAssertEqual(waistSignal([100.0, 99.0], phase: F.phase(startDay: "2031-01-13")).reason, .noEarlierWaist)
    }

    // MARK: - Working weights

    /// Tolerance 5 %: against 100.0 the line is 95.0, and "dropped" is strictly below it. Fault F9.
    func testLiftDropWithinToleranceIsHeld() {
        let atTheLine = pressSignal(previous: 100, current: 95)
        XCTAssertEqual(atTheLine, CutScorecardLiftSignal(state: .met, reason: .holding, commonExercises: 1, dropped: 0,
                                                         climbed: 0, held: 1, windowStartDay: "2031-01-08",
                                                         windowEndDay: "2031-01-14"))
        let oneQuantumBelow = pressSignal(previous: 100, current: 94.999)
        XCTAssertEqual(oneQuantumBelow, CutScorecardLiftSignal(state: .notMet, reason: .dropping, commonExercises: 1,
                                                               dropped: 1, climbed: 0, held: 0,
                                                               windowStartDay: "2031-01-08", windowEndDay: "2031-01-14"))
        XCTAssertEqual(pressSignal(previous: 100, current: 95.001).held, 1)
        XCTAssertEqual(pressSignal(previous: 100, current: 99.999).held, 1, "inside the tolerance is held")

        // A line that is not a round number: 62.5 x 0.95 = 59.375.
        XCTAssertEqual(pressSignal(previous: 62.5, current: 59.375).dropped, 0)
        XCTAssertEqual(pressSignal(previous: 62.5, current: 59.374).dropped, 1)

        // The tolerance is the parameter. At the generic 2.5 % the line is 97.5; at 0 % any decrease drops.
        let generic = F.params { $0.liftDropTolerancePercent = 2.5 }
        XCTAssertEqual(pressSignal(previous: 100, current: 97.5, parameters: generic).dropped, 0)
        XCTAssertEqual(pressSignal(previous: 100, current: 97.499, parameters: generic).dropped, 1)
        let none = F.params { $0.liftDropTolerancePercent = 0 }
        XCTAssertEqual(pressSignal(previous: 100, current: 100, parameters: none).dropped, 0)
        XCTAssertEqual(pressSignal(previous: 100, current: 99.999, parameters: none).dropped, 1)
    }

    /// "Climbed" is strictly above the previous weight; equal is held.
    func testLiftClimbedIsStrictlyAboveThePreviousWeight() {
        let equal = pressSignal(previous: 100, current: 100)
        XCTAssertEqual(equal.climbed, 0)
        XCTAssertEqual(equal.held, 1)
        let oneQuantumAbove = pressSignal(previous: 100, current: 100.001)
        XCTAssertEqual(oneQuantumAbove.climbed, 1)
        XCTAssertEqual(oneQuantumAbove.held, 0)
        XCTAssertEqual(oneQuantumAbove.state, .met)
        XCTAssertEqual(oneQuantumAbove.reason, .holding, "the met reason is `holding` whether weights held or climbed")
    }

    /// Share 0.5 and the comparison is `dropped / common >= share`. Fault F10.
    func testLiftDropShareBelowThresholdIsHolding() {
        // One of three dropped: a third is below a half.
        let oneOfThree = liftSignal([(9, "A", 100), (9, "B", 100), (9, "C", 100),
                                     (2, "A", 90), (2, "B", 100), (2, "C", 100)])
        XCTAssertEqual(oneOfThree, CutScorecardLiftSignal(state: .met, reason: .holding, commonExercises: 3, dropped: 1,
                                                          climbed: 0, held: 2, windowStartDay: "2031-01-08",
                                                          windowEndDay: "2031-01-14"))
        // One of two dropped: exactly a half, which is dropping.
        let sets: [(Int, String, Double)] = [(9, "A", 100), (9, "B", 100), (2, "A", 90), (2, "B", 105)]
        let oneOfTwo = liftSignal(sets)
        XCTAssertEqual(oneOfTwo, CutScorecardLiftSignal(state: .notMet, reason: .dropping, commonExercises: 2, dropped: 1,
                                                        climbed: 1, held: 0, windowStartDay: "2031-01-08",
                                                        windowEndDay: "2031-01-14"))
        // One quantum either side of the share.
        XCTAssertEqual(liftSignal(sets, parameters: F.params { $0.liftDropShare = 0.501 }).reason, .holding)
        XCTAssertEqual(liftSignal(sets, parameters: F.params { $0.liftDropShare = 0.499 }).reason, .dropping)
        // Share 1 needs every common exercise to drop.
        XCTAssertEqual(liftSignal(sets, parameters: F.params { $0.liftDropShare = 1 }).reason, .holding)
        XCTAssertEqual(liftSignal([(9, "A", 100), (9, "B", 100), (2, "A", 90), (2, "B", 90)],
                                  parameters: F.params { $0.liftDropShare = 1 }).reason, .dropping)
    }

    /// The window is the seven days before the weigh-in, `a - 7 … a - 1`, and the one before it is
    /// `a - 14 … a - 8`. Neither is the Monday week, and the weigh-in day itself is in neither.
    func testLiftSignalUsesSevenDaysBeforeTheWeighIn() {
        let press = F.pressName
        // Both edges of both windows are inside.
        let edges = liftSignal([(14, press, 100), (8, press, 100), (7, press, 100), (1, press, 100)])
        XCTAssertEqual(edges.reason, .holding)
        XCTAssertEqual(edges.windowStartDay, "2031-01-08")
        XCTAssertEqual(edges.windowEndDay, "2031-01-14")
        // `a - 7` is current and `a - 8` is previous: a drop across that boundary is seen.
        XCTAssertEqual(liftSignal([(8, press, 100), (7, press, 90)]).reason, .dropping)
        // A session on the weigh-in day is not in the current window.
        XCTAssertEqual(liftSignal([(9, press, 100), (0, press, 100)]).reason, .noSessionsThisWeek)
        // A session fifteen days back is not in the previous window.
        XCTAssertEqual(liftSignal([(15, press, 100), (2, press, 100)]).reason, .noSessionsPriorWeek)
        // The heavy set fifteen days back does not count as "previous" either: 100 -> 100 holds.
        XCTAssertEqual(liftSignal([(15, press, 200), (14, press, 100), (1, press, 100)]).reason, .holding)
        // A weigh-in set on the day itself does not rescue a drop.
        XCTAssertEqual(liftSignal([(9, press, 100), (2, press, 90), (0, press, 100)]).reason, .dropping)

        // The window follows the weigh-in day, not the calendar week. Weigh-in on Monday 2031-01-13: the
        // current window is the whole of the previous Monday week.
        let monday = evaluate(F.make(weights: [F.weight("2031-01-08", 100.0), F.weight("2031-01-13", 99.2)],
                                     lifts: [CutScorecardLiftObservation(day: "2031-01-06", exercise: press, weightKg: 90),
                                             CutScorecardLiftObservation(day: "2031-01-05", exercise: press, weightKg: 100)],
                                     today: "2031-01-13")).signals.lifts
        XCTAssertEqual(monday.reason, .dropping)
        XCTAssertEqual(monday.windowStartDay, "2031-01-06")
        XCTAssertEqual(monday.windowEndDay, "2031-01-12")
    }

    /// The comparison is the greatest weight per exercise in each window, wherever it falls in the week.
    func testLiftSignalUsesTheHeaviestSetPerExercise() {
        let press = F.pressName
        // Previous: 70 then 100. Current: 100 then 80. Heaviest against heaviest holds.
        let signal = liftSignal([(13, press, 70), (9, press, 100), (6, press, 100), (2, press, 80)])
        XCTAssertEqual(signal.reason, .holding)
        XCTAssertEqual(signal.held, 1)
        XCTAssertEqual(signal.commonExercises, 1, "several sets of one exercise are one exercise")
    }

    /// Names are compared byte for byte: no trimming, no case folding (§6.3, §12.7 item 3).
    func testLiftExerciseNamesCompareExactly() {
        XCTAssertEqual(pressSignal(previous: 100, current: 100).commonExercises, 1)
        for other in ["fixture press", "Fixture Press ", " Fixture Press", "FIXTURE PRESS"] {
            let signal = liftSignal([(9, F.pressName, 100), (2, other, 100)])
            XCTAssertEqual(signal.state, .unknown, "\"\(other)\"")
            XCTAssertEqual(signal.reason, .noCommonExercises, "\"\(other)\"")
        }
        // Two spellings are two exercises: they are neither merged nor compared with each other.
        let both = liftSignal([(9, "Fixture Press", 100), (9, "fixture press", 50),
                               (2, "Fixture Press", 100), (2, "fixture press", 40)])
        XCTAssertEqual(both.commonExercises, 2)
        XCTAssertEqual(both.dropped, 1)
        XCTAssertEqual(both.held, 1)
    }

    func testNoCommonExerciseIsUnknown() {
        let signal = liftSignal([(9, F.pressName, 100), (2, F.rowName, 50)])
        XCTAssertEqual(signal.state, .unknown)
        XCTAssertEqual(signal.reason, .noCommonExercises)
        XCTAssertEqual(signal.commonExercises, 0)
        XCTAssertEqual(signal.dropped, 0)
        // Exercises that appear in only one window are ignored when another is common.
        let partly = liftSignal([(9, F.pressName, 100), (9, "Only Before", 100),
                                 (2, F.pressName, 100), (2, "Only Now", 10)])
        XCTAssertEqual(partly.commonExercises, 1)
        XCTAssertEqual(partly.reason, .holding)
    }

    /// The unknown reasons of the lift signal in the order §7.5 tests them.
    func testLiftUnknownReasonPrecedence() {
        let press = F.pressName
        XCTAssertEqual(liftSignal([]).reason, .noLiftData)
        XCTAssertEqual(liftSignal([]).state, .unknown)
        // The only observation is invalid, so the input holds no valid observation at all.
        XCTAssertEqual(liftSignal([(2, press, -1)]).reason, .noLiftData)
        XCTAssertEqual(liftSignal([(2, "", 100)]).reason, .noLiftData)
        // §7.5 makes `noLiftData` depend on the whole input ("no valid lift observation at all"), so one
        // valid observation anywhere, however old, turns it into `noSessionsThisWeek`. Ruling R2 lists
        // this as one of the things an observation dated before `evidenceStartDay` may change.
        XCTAssertEqual(liftSignal([(400, press, 100)]).reason, .noSessionsThisWeek)
        // Both windows empty: the current window is named first.
        XCTAssertEqual(liftSignal([(20, press, 100)]).reason, .noSessionsThisWeek)
        XCTAssertEqual(liftSignal([(9, press, 100)]).reason, .noSessionsThisWeek)
        XCTAssertEqual(liftSignal([(2, press, 100)]).reason, .noSessionsPriorWeek)
        XCTAssertEqual(liftSignal([(9, press, 100), (2, F.rowName, 100)]).reason, .noCommonExercises)
    }

    // MARK: - Protein

    func testProteinMetAtRequiredDays() {
        XCTAssertEqual(proteinSignal([100, 100, 100, 100, 100, nil, nil]),
                       CutScorecardProteinSignal(state: .met, reason: .floorMet, daysLogged: 5, daysAtOrAboveFloor: 5,
                                                 requiredDays: 5, floorGrams: 100))
        // The floor itself counts; one quantum under does not; one quantum over does.
        XCTAssertEqual(proteinSignal([100, 100, 100, 100, 100, 0, 0]).reason, .floorMet)
        let short = proteinSignal([100, 100, 100, 100, 99.999, 0, 0])
        XCTAssertEqual(short, CutScorecardProteinSignal(state: .notMet, reason: .floorMissed, daysLogged: 7,
                                                        daysAtOrAboveFloor: 4, requiredDays: 5, floorGrams: 100))
        XCTAssertEqual(proteinSignal([100, 100, 100, 100, 100.001, 0, 0]).reason, .floorMet)
        // The comparison is on quantized grams (§7.5): 99.9996 quantizes to 100.000.
        XCTAssertEqual(proteinSignal([100, 100, 100, 100, 99.9996, 0, 0]).reason, .floorMet)
        // The required day count is the parameter: six days fail at 7, pass at 6.
        let six: [Double?] = [100, 100, 100, 100, 100, 100, 0]
        XCTAssertEqual(proteinSignal(six, parameters: F.params { $0.proteinMinDaysPerWeek = 6 }).reason, .floorMet)
        XCTAssertEqual(proteinSignal(six, parameters: F.params { $0.proteinMinDaysPerWeek = 7 }).reason, .floorMissed)
    }

    func testProteinNotMetOnlyWhenUnloggedDaysCannotRescueIt() {
        // 2 at the floor + 2 unlogged = 4, below 5: even perfect unlogged days could not reach it.
        XCTAssertEqual(proteinSignal([120, 120, 80, 80, 80, nil, nil]),
                       CutScorecardProteinSignal(state: .notMet, reason: .floorMissed, daysLogged: 5, daysAtOrAboveFloor: 2,
                                                 requiredDays: 5, floorGrams: 100))
        // 2 at the floor + 3 unlogged = 5: it could still be reached, so it is not "not met".
        XCTAssertEqual(proteinSignal([120, 120, 80, 80, nil, nil, nil]),
                       CutScorecardProteinSignal(state: .unknown, reason: .incompleteLogging, daysLogged: 4,
                                                 daysAtOrAboveFloor: 2, requiredDays: 5, floorGrams: 100))
    }

    /// Fault F21: an unlogged day is not a day below the floor.
    func testProteinIncompleteLoggingIsUnknown() {
        // The fixture's week 6: three days logged, all at the floor, four not logged.
        let signal = proteinSignal([120, nil, 120, nil, nil, 120, nil])
        XCTAssertEqual(signal, CutScorecardProteinSignal(state: .unknown, reason: .incompleteLogging, daysLogged: 3,
                                                         daysAtOrAboveFloor: 3, requiredDays: 5, floorGrams: 100))
        XCTAssertEqual(proteinSignal([nil, nil, nil, nil, nil, nil, 120]).reason, .incompleteLogging)
        XCTAssertEqual(proteinSignal([nil, nil, nil, nil, nil, nil, 80]).reason, .incompleteLogging,
                       "one day below the floor and six unlogged could still reach five")
    }

    func testProteinWithoutFloorIsUnknown() {
        let signal = proteinSignal([120, 120, 120, 120, 120, 120, 120],
                                   parameters: F.params { $0.proteinFloorGrams = nil })
        XCTAssertEqual(signal.state, .unknown)
        XCTAssertEqual(signal.reason, .noFloorConfigured)
        XCTAssertNil(signal.floorGrams)
        // No floor is named before no data.
        XCTAssertEqual(proteinSignal([nil, nil, nil, nil, nil, nil, nil],
                                     parameters: F.params { $0.proteinFloorGrams = nil }).reason, .noFloorConfigured)
    }

    func testProteinWithNothingLoggedInTheWindowIsNoProteinData() {
        let signal = proteinSignal([nil, nil, nil, nil, nil, nil, nil])
        XCTAssertEqual(signal, CutScorecardProteinSignal(state: .unknown, reason: .noProteinData, daysLogged: 0,
                                                         daysAtOrAboveFloor: 0, requiredDays: 5, floorGrams: 100))
    }

    /// The protein window is the lift window: `a - 7 … a - 1`, without the weigh-in day.
    func testProteinWindowIsTheSevenDaysBeforeTheWeighIn() {
        func signal(_ offsets: [Int]) -> CutScorecardProteinSignal {
            let days = offsets.map { CutScorecardProteinDay(day: F.day(anchor, -$0), grams: 120) }
            return evaluate(F.scenario(weights: twoWeeks, proteinDays: days)).signals.protein
        }
        XCTAssertEqual(signal([0, 8]).reason, .noProteinData, "the weigh-in day and eight days back are outside")
        XCTAssertEqual(signal([7, 6, 5, 4, 1]).reason, .floorMet, "both edges are inside")
        let straddling = signal([8, 7, 6, 5, 1, 0])
        XCTAssertEqual(straddling.daysLogged, 4, "of six entries, four are inside the window")
        XCTAssertEqual(straddling.reason, .incompleteLogging)
    }

    /// A zero-gram day is a logged day below the floor (§6.5), not an unlogged one.
    func testZeroGramProteinDayIsLoggedAndBelowTheFloor() {
        let signal = proteinSignal([0, 0, 0, 120, 120, 120, 120])
        XCTAssertEqual(signal.daysLogged, 7)
        XCTAssertEqual(signal.daysAtOrAboveFloor, 4)
        XCTAssertEqual(signal.reason, .floorMissed)
    }

    /// §7.1 step 7: the one place input order matters.
    func testDuplicateProteinDayUsesTheLaterEntry() {
        let base = F.protein(before: anchor, [120, 120, 120, 120, 0, 0, nil])
        let day = F.day(anchor, -1)
        let low = CutScorecardProteinDay(day: day, grams: 80)
        let high = CutScorecardProteinDay(day: day, grams: 120)

        let highLast = evaluate(F.scenario(weights: twoWeeks, proteinDays: [low] + base + [high])).signals.protein
        XCTAssertEqual(highLast.daysLogged, 7, "two entries for one day are one logged day")
        XCTAssertEqual(highLast.daysAtOrAboveFloor, 5)
        XCTAssertEqual(highLast.reason, .floorMet)

        let lowLast = evaluate(F.scenario(weights: twoWeeks, proteinDays: [high] + base + [low])).signals.protein
        XCTAssertEqual(lowLast.daysLogged, 7)
        XCTAssertEqual(lowLast.daysAtOrAboveFloor, 4)
        XCTAssertEqual(lowLast.reason, .floorMissed)
    }

    // MARK: - Rate band

    /// 100.0 then 99.2 is 0.803 percent per week. Fault F13.
    func testRateBandBoundsAreInclusive() {
        func band(_ low: Double, _ high: Double) -> CutScorecardRateBandSignal {
            evaluate(F.scenario(weights: twoWeeks, phase: F.phase(low: low, high: high))).signals.rateBand
        }
        XCTAssertEqual(band(0.803, 1.2), CutScorecardRateBandSignal(state: .met, reason: .withinBand, percentPerWeek: 0.803,
                                                                    lowPercentPerWeek: 0.803, highPercentPerWeek: 1.2))
        XCTAssertEqual(band(0.804, 1.2), CutScorecardRateBandSignal(state: .notMet, reason: .belowBand, percentPerWeek: 0.803,
                                                                    lowPercentPerWeek: 0.804, highPercentPerWeek: 1.2))
        XCTAssertEqual(band(0.802, 1.2).reason, .withinBand)
        XCTAssertEqual(band(0.4, 0.803), CutScorecardRateBandSignal(state: .met, reason: .withinBand, percentPerWeek: 0.803,
                                                                    lowPercentPerWeek: 0.4, highPercentPerWeek: 0.803))
        XCTAssertEqual(band(0.4, 0.802), CutScorecardRateBandSignal(state: .notMet, reason: .aboveBand, percentPerWeek: 0.803,
                                                                    lowPercentPerWeek: 0.4, highPercentPerWeek: 0.802))
        XCTAssertEqual(band(0.4, 0.804).reason, .withinBand)
        XCTAssertEqual(band(0.803, 0.803).reason, .withinBand, "a band of one value is valid and inclusive at both ends")
    }

    func testRisingWeightIsBelowBand() {
        let result = evaluate(F.scenario(weights: [100.0, 100.5]))
        assertCutRate(result, loss: -0.5, percent: -0.499)
        XCTAssertEqual(result.signals.rateBand.state, .notMet)
        XCTAssertEqual(result.signals.rateBand.reason, .belowBand)
        XCTAssertEqual(result.signals.rateBand.percentPerWeek, -0.499)
        // Rising is below the band even when the band starts at zero; flat is then inside it.
        XCTAssertEqual(evaluate(F.scenario(weights: [100.0, 100.5], phase: F.phase(low: 0, high: 1.2)))
            .signals.rateBand.reason, .belowBand)
        XCTAssertEqual(evaluate(F.scenario(weights: [100.0, 100.0], phase: F.phase(low: 0, high: 1.2)))
            .signals.rateBand.reason, .withinBand)
    }

    func testRateBandUnknownReasons() {
        // One reading: no rate.
        let single = evaluate(F.scenario(weights: [100.0])).signals.rateBand
        XCTAssertEqual(single.state, .unknown)
        XCTAssertEqual(single.reason, .rateUnknown)
        XCTAssertNil(single.percentPerWeek)
        // No phase, and a phase that has not started: there is a rate but no band to hold it against.
        let noPhase = evaluate(F.scenario(weights: twoWeeks, phase: nil))
        XCTAssertNotNil(noPhase.rate)
        XCTAssertEqual(noPhase.signals.rateBand.state, .unknown)
        XCTAssertEqual(noPhase.signals.rateBand.reason, .noActivePhase)
        let notStarted = evaluate(F.scenario(weights: twoWeeks, phase: F.phase(startDay: "2031-06-02")))
        XCTAssertEqual(notStarted.signals.rateBand.reason, .noActivePhase)
        // Overdue and empty are covered with the other signals in CutScorecardSeriesTests and
        // CutScorecardTests.
    }

    /// With no active phase the waist, lift and protein signals are still computed (§7.2).
    func testWaistLiftAndProteinSignalsAreComputedWithoutAPhase() {
        for phase in [nil, F.phase(startDay: "2031-06-02")] {
            let result = evaluate(F.input(today: F.weighInDay(4), phase: phase))
            XCTAssertEqual(result.signals.waist.state, .met)
            XCTAssertEqual(result.signals.waist.changeCm, -1.0)
            XCTAssertEqual(result.signals.lifts.state, .met)
            XCTAssertEqual(result.signals.lifts.reason, .holding)
            XCTAssertEqual(result.signals.protein.reason, .floorMet)
            XCTAssertEqual(result.judgedWeekStart, F.monday(4))
        }
    }
}
