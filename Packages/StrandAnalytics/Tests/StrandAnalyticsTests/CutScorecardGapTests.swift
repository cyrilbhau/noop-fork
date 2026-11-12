import XCTest
@testable import StrandAnalytics

private typealias F = CutScorecardFixture
private let r1 = CutScorecardRule.liftsHoldingWaistShrinking
private let r2 = CutScorecardRule.liftsDropping
private let r3 = CutScorecardRule.slowLoss

/// `CutScorecard.evaluate`: the gaps found after the first suites were written.
///
/// Three faults that a run of single mutations showed no test caught (`stage-1.md` §18, closing note),
/// second independent tests for two boundaries that only one test guarded, and one named test for each
/// of rulings R18 to R23. Expected values come from §7 read with the rulings.
///
/// Unless a test says otherwise the judged week is fixture week 2, weighed on Wednesday 2031-01-15.
final class CutScorecardGapTests: XCTestCase {

    private let anchor = "2031-01-15"
    private let twoWeeks: [Double?] = [100.0, 99.2]
    private let good = [F.weight("2031-01-08", 100.0), F.weight("2031-01-15", 99.2)]

    private func evaluate(_ input: CutScorecardInput) -> CutScorecardResult {
        CutScorecard.evaluate(input)
    }

    private func lift(_ day: String, _ exercise: String, _ kg: Double) -> CutScorecardLiftObservation {
        CutScorecardLiftObservation(day: day, exercise: exercise, weightKg: kg)
    }

    /// The lift signal of week 2 for observations given as (days before the weigh-in, exercise, kg).
    private func liftSignal(_ sets: [(Int, String, Double)],
                            parameters: CutScorecardParameters = F.parameters) -> CutScorecardLiftSignal {
        evaluate(F.scenario(weights: twoWeeks, lifts: sets.map { lift(F.day(anchor, -$0.0), $0.1, $0.2) },
                            parameters: parameters)).signals.lifts
    }

    private func rejections(_ nonFinite: Int = 0, _ nonPositive: Int = 0, _ invalidDay: Int = 0,
                            _ future: Int = 0) -> CutScorecardRejections {
        CutScorecardRejections(nonFinite: nonFinite, nonPositive: nonPositive, invalidDay: invalidDay, future: future)
    }

    // MARK: - Faults no earlier test caught

    /// Several sets of one exercise on one day: the heaviest counts, whichever comes first in the input.
    /// A lightest-wins or last-wins fault would compare 80 with 100 and call the week dropping.
    func testHeaviestOfSeveralSetsOnTheSameDayCounts() {
        let expected = CutScorecardLiftSignal(state: .met, reason: .holding, commonExercises: 1, dropped: 0, climbed: 0,
                                              held: 1, windowStartDay: "2031-01-08", windowEndDay: "2031-01-14")
        XCTAssertEqual(liftSignal([(9, "Squat", 100), (2, "Squat", 100), (2, "Squat", 80)]), expected, "heavy set first")
        XCTAssertEqual(liftSignal([(9, "Squat", 100), (2, "Squat", 80), (2, "Squat", 100)]), expected, "light set first")
        // The same in the prior window: 100 and 120 on one day make 120 the weight to hold, so 100 drops.
        for sets in [[(9, "Squat", 100.0), (9, "Squat", 120.0), (2, "Squat", 100.0)],
                     [(9, "Squat", 120.0), (9, "Squat", 100.0), (2, "Squat", 100.0)]] {
            let signal = liftSignal(sets)
            XCTAssertEqual(signal.reason, .dropping)
            XCTAssertEqual(signal.dropped, 1)
        }
    }

    /// The prior window is `a - 14 … a - 8`. Day `a - 7` belongs to the current window only.
    func testPriorLiftWindowEndsEightDaysBeforeTheWeighIn() {
        // (a) The only lifts are on day `a - 7`: the prior window is empty. Were `a - 7` in both windows
        // the week would be holding.
        let only = liftSignal([(7, "Squat", 100), (7, "Bench", 60)])
        XCTAssertEqual(only, CutScorecardLiftSignal(state: .unknown, reason: .noSessionsPriorWeek, commonExercises: 0,
                                                    dropped: 0, climbed: 0, held: 0, windowStartDay: "2031-01-08",
                                                    windowEndDay: "2031-01-14"))
        // (b) Prior 100, current 120 on day `a - 7`: climbed. Were `a - 7` also prior, the prior weight
        // would be 120 and the exercise would merely have held.
        let climbed = liftSignal([(9, "Squat", 100), (7, "Squat", 120)])
        XCTAssertEqual(climbed, CutScorecardLiftSignal(state: .met, reason: .holding, commonExercises: 1, dropped: 0,
                                                       climbed: 1, held: 0, windowStartDay: "2031-01-08",
                                                       windowEndDay: "2031-01-14"))
        // And the other edge: day `a - 8` is prior, not current.
        XCTAssertEqual(liftSignal([(8, "Squat", 100)]).reason, .noSessionsThisWeek)
    }

    /// A share of 0.0004 is valid (above zero) and quantizes to zero, so `dropped / common >= share` is
    /// true even when nothing dropped. The `dropped >= 1` condition is what keeps the week holding.
    func testNothingDroppedIsHoldingEvenWhenTheShareQuantizesToZero() {
        let tiny = F.params { $0.liftDropShare = 0.0004 }
        XCTAssertEqual(CutScorecard.quantize(0.0004), 0, "the premise")
        let held = liftSignal([(9, "Squat", 100), (2, "Squat", 100)], parameters: tiny)
        XCTAssertEqual(held, CutScorecardLiftSignal(state: .met, reason: .holding, commonExercises: 1, dropped: 0, climbed: 0,
                                                    held: 1, windowStartDay: "2031-01-08", windowEndDay: "2031-01-14"))
        let climbed = liftSignal([(9, "Squat", 100), (2, "Squat", 110)], parameters: tiny)
        XCTAssertEqual(climbed.reason, .holding)
        XCTAssertEqual(climbed.dropped, 0)
        // With that share one drop among many is enough.
        let oneOfFour = liftSignal([(9, "A", 100), (9, "B", 100), (9, "C", 100), (9, "D", 100),
                                    (2, "A", 90), (2, "B", 100), (2, "C", 100), (2, "D", 100)], parameters: tiny)
        XCTAssertEqual(oneOfFour.reason, .dropping)
        XCTAssertEqual(oneOfFour.dropped, 1)
    }

    /// `evidenceStartDay` is `J` moved back `7 x (m + 2)` days. With a window at `Int.max` that product
    /// overflows; the day is clamped to 0001-01-01 (R11) and nothing traps (§6.5, R22).
    func testEvidenceStartDayWithAnIntMaxWindowIsClampedAndDoesNotTrap() {
        let changes: [(String, (inout CutScorecardParameters) -> Void)] = [
            ("rateWindowWeeks", { $0.rateWindowWeeks = .max }),
            ("waistWindowWeeks", { $0.waistWindowWeeks = .max }),
            ("liftDropConsecutiveWeeks", { $0.liftDropConsecutiveWeeks = .max }),
            ("slowLossConsecutiveWeeks", { $0.slowLossConsecutiveWeeks = .max }),
            ("all four", { $0.rateWindowWeeks = .max; $0.waistWindowWeeks = .max
                           $0.liftDropConsecutiveWeeks = .max; $0.slowLossConsecutiveWeeks = .max }),
        ]
        for (label, change) in changes {
            let result = evaluate(F.input(today: F.weighInDay(9), parameters: F.params(change)))
            XCTAssertNil(result.invalidInput, label)
            XCTAssertEqual(result.evidenceStartDay, "0001-01-01", label)
            XCTAssertEqual(result.judgedWeekStart, F.monday(9), label)
            XCTAssertEqual(result.weeks.count, 9, label)
        }
        // Just short of overflow the clamp still applies: a billion weeks is far before year 1.
        let billion = evaluate(F.input(today: F.weighInDay(9), parameters: F.params { $0.rateWindowWeeks = 1_000_000_000 }))
        XCTAssertEqual(billion.evidenceStartDay, "0001-01-01")
        // And an ordinary long window is not clamped: 100 weeks is 714 days before 2031-03-03.
        let hundred = evaluate(F.input(today: F.weighInDay(9), parameters: F.params { $0.rateWindowWeeks = 100 }))
        XCTAssertEqual(hundred.evidenceStartDay, F.day(F.monday(9), -714))
    }

    // MARK: - Second, independent tests

    /// The lift tolerance boundary, seen through the rules. Press sessions that fall by exactly 5 % a week
    /// (200, 190, 180.5) sit on the line and are held, so with a two-week window rule 2 is settled as not
    /// fired. One quantum under the line each week (189.999, then 180.498 against a line of 180.499) and
    /// it fires.
    func testLiftExactlyOnTheToleranceLineIsHeldAndKeepsRuleTwoFromFiring() {
        let parameters = F.params { $0.liftDropConsecutiveWeeks = 2 }
        func run(_ week2: Double, _ week3: Double) -> CutScorecardResult {
            evaluate(F.scenario(weights: [100.0, 99.2, 98.4], waists: [100.0, 100.0, 100.0],
                                lifts: F.pressSessions([(0, 200), (1, 200), (2, week2), (3, week3)]), parameters: parameters))
        }
        let onTheLine = run(190, 180.5)
        XCTAssertEqual(onTheLine.signals.lifts.reason, .holding)
        XCTAssertEqual(onTheLine.signals.lifts.held, 1)
        XCTAssertEqual(onTheLine.signals.lifts.dropped, 0)
        assertCutRules(onTheLine, "NNN")
        XCTAssertEqual(onTheLine.rule(1)?.consecutiveWeeks, 0)
        assertCutVerdict(onTheLine, .holdSteady, .noChangeRuleFired)

        let under = run(189.999, 180.498)
        XCTAssertEqual(under.signals.lifts.reason, .dropping)
        XCTAssertEqual(under.signals.lifts.dropped, 1)
        assertCutRules(under, "NFN")
        XCTAssertEqual(under.rule(1)?.consecutiveWeeks, 2)
        assertCutVerdict(under, .addCalories, .ruleFired, rule: r2, kcal: 300)

        // Only the judged week under the line: one dropping week behind a held one.
        let last = run(190, 180.499)
        XCTAssertEqual(last.signals.lifts.reason, .dropping)
        assertCutRules(last, "NNN")
        XCTAssertEqual(last.rule(1)?.consecutiveWeeks, 1)
    }

    /// The category order of R12 (nonFinite, nonPositive, invalidDay, future), through waist readings,
    /// lift observations and protein days in one evaluation.
    func testRejectionCategoryOrderAcrossWaistsLiftsAndProtein() {
        let clean = evaluate(F.make(weights: good, today: anchor))
        let result = evaluate(F.make(
            weights: good,
            waists: [CutScorecardReading(day: "2031-13-40", takenAt: 0, value: -.infinity),      // nonFinite
                     CutScorecardReading(day: "2031-13-40", takenAt: 0, value: -80),             // nonPositive
                     CutScorecardReading(day: "2031-09-09", takenAt: 0, value: 0)],              // nonPositive
            lifts: [lift("2031-09-09", "", .nan),                                                // nonFinite
                    lift("2031-09-09", "", -60),                                                 // nonPositive
                    lift("2031-09-09", "", 60),                                                  // invalidDay
                    lift("2031-09-09", "Squat", 60)],                                            // future
            proteinDays: [CutScorecardProteinDay(day: "2031-09-09", grams: 2e100),               // nonFinite
                          CutScorecardProteinDay(day: "2031-09-09", grams: -1),                  // nonPositive
                          CutScorecardProteinDay(day: "2031-09-31", grams: 0),                   // invalidDay
                          CutScorecardProteinDay(day: "2031-09-09", grams: 0)],                  // future
            today: anchor))
        XCTAssertEqual(result.rejections, rejections(3, 4, 2, 2))
        XCTAssertEqual(result.weeks, clean.weeks)
        XCTAssertEqual(result.signals, clean.signals)
        XCTAssertEqual(result.verdict, clean.verdict)
    }

    // MARK: - R18: readings are echoed as given

    func testReadingsAreEchoedAsGivenAndDerivedFiguresAreQuantized() throws {
        let result = evaluate(F.make(
            weights: [F.weight("2031-01-08", 100.0004), F.weight("2031-01-15", 99.2006)],
            waists: [F.waist("2031-01-08", 100.0004), F.waist("2031-01-15", 99.4996)], today: anchor))
        // Echoed: exactly the values passed in.
        XCTAssertEqual(result.weeks.map(\.weightKg), [100.0004, 99.2006])
        XCTAssertEqual(result.weeks.map(\.waistCm), [100.0004, 99.4996])
        XCTAssertEqual(result.currentWeightKg, 99.2006)
        XCTAssertEqual(result.signals.waist.currentCm, 99.4996)
        XCTAssertEqual(result.signals.waist.referenceCm, 100.0004)
        // Derived: quantized. 100.0004 - 99.2006 = 0.7998; 99.4996 - 100.0004 = -0.5008.
        XCTAssertEqual(result.week(1)?.weeklyLossKg, 0.8)
        XCTAssertEqual(result.signals.waist.changeCm, -0.501)
        XCTAssertEqual(result.signals.waist.state, .met)
        let rate = try XCTUnwrap(result.rate)
        XCTAssertEqual(rate.lossKgPerWeek, 0.8)
        XCTAssertEqual(rate.percentPerWeek, 0.803)
        XCTAssertEqual(rate.referenceWeightKg, 99.6005, accuracy: 1e-9, "the mean of the readings, not quantized")
        // A value that is not its own quantization survives untouched, at any size.
        let odd = evaluate(F.make(weights: [F.weight(anchor, 87.65432109876)], waists: [F.waist(anchor, 1e100)], today: anchor))
        XCTAssertEqual(odd.week(0)?.weightKg, 87.65432109876)
        XCTAssertEqual(odd.currentWeightKg, 87.65432109876)
        XCTAssertEqual(odd.week(0)?.waistCm, 1e100)
        XCTAssertEqual(odd.signals.waist.currentCm, 1e100)
    }

    // MARK: - R19: band bounds as given

    func testRateBandSignalReportsItsBoundsAsGiven() {
        func band(_ low: Double, _ high: Double, weights: [Double?]) -> CutScorecardRateBandSignal {
            evaluate(F.scenario(weights: weights, phase: F.phase(low: low, high: high))).signals.rateBand
        }
        // Met, not met and unknown all carry the bounds exactly as the phase states them.
        XCTAssertEqual(band(0.25049, 0.80349, weights: twoWeeks),
                       CutScorecardRateBandSignal(state: .met, reason: .withinBand, percentPerWeek: 0.803,
                                                  lowPercentPerWeek: 0.25049, highPercentPerWeek: 0.80349))
        XCTAssertEqual(band(0.25049, 0.80249, weights: twoWeeks),
                       CutScorecardRateBandSignal(state: .notMet, reason: .aboveBand, percentPerWeek: 0.803,
                                                  lowPercentPerWeek: 0.25049, highPercentPerWeek: 0.80249))
        XCTAssertEqual(band(0.25049, 0.80349, weights: [100.0]),
                       CutScorecardRateBandSignal(state: .unknown, reason: .rateUnknown, percentPerWeek: nil,
                                                  lowPercentPerWeek: 0.25049, highPercentPerWeek: 0.80349))
    }

    // MARK: - R20: the invalid result

    func testInvalidResultHasNoBandBoundsAndNoCurrentWeightDay() {
        let base = F.input(week: 9)
        func invalid(parameters: CutScorecardParameters = F.parameters, phase: CutScorecardPhase? = F.phase,
                     today: String = F.weighInDay(9)) -> CutScorecardResult {
            evaluate(F.make(weights: base.weights, waists: base.waists, lifts: base.lifts, proteinDays: base.proteinDays,
                            phase: phase, parameters: parameters, today: today))
        }
        // The control: the same input, valid, has a current weight day and a started phase's bounds.
        let valid = invalid()
        XCTAssertEqual(valid.currentWeightDay, F.weighInDay(9))
        XCTAssertEqual(valid.signals.rateBand.lowPercentPerWeek, 0.40)

        let cases: [(CutScorecardInvalidInput, CutScorecardResult)] = [
            (.parameters, invalid(parameters: F.params { $0.rateWindowWeeks = 0 })),    // phase valid and started
            (.phase, invalid(phase: F.phase(low: 1.2, high: 0.4))),
            (.today, invalid(today: "never")),
        ]
        for (kind, result) in cases {
            XCTAssertEqual(result.invalidInput, kind)
            XCTAssertEqual(result.signals.rateBand, CutScorecardRateBandSignal(state: .unknown, reason: .noReadings,
                                                                               percentPerWeek: nil, lowPercentPerWeek: nil,
                                                                               highPercentPerWeek: nil), "\(kind)")
            XCTAssertNil(result.currentWeightDay, "\(kind)")
            XCTAssertNil(result.currentWeightKg, "\(kind)")
        }
    }

    // MARK: - R21: no day before 0001-01-01

    func testReportedDaysBeforeTheFirstDayAreReportedAsTheFirstDay() {
        func run(weighIn: String, lifts: [CutScorecardLiftObservation] = []) -> CutScorecardResult {
            evaluate(F.make(weights: [F.weight(weighIn, 100.0)], lifts: lifts, phase: F.phase(startDay: "0001-01-01"),
                            today: weighIn))
        }
        // Weigh-in on Wednesday 0001-01-03: the window starts seven days earlier, before the calendar,
        // and ends on 0001-01-02.
        let third = run(weighIn: "0001-01-03")
        XCTAssertNil(third.invalidInput)
        XCTAssertEqual(third.signals.lifts, CutScorecardLiftSignal(state: .unknown, reason: .noLiftData, commonExercises: 0,
                                                                   dropped: 0, climbed: 0, held: 0,
                                                                   windowStartDay: "0001-01-01", windowEndDay: "0001-01-02"))
        XCTAssertEqual(third.evidenceStartDay, "0001-01-01")
        XCTAssertEqual(third.judgedWeekStart, "0001-01-01")
        XCTAssertEqual(third.weeks.map(\.weekStart), ["0001-01-01"])

        // Weigh-in on the first day there is: both ends of the window are before the calendar.
        let first = run(weighIn: "0001-01-01")
        XCTAssertNil(first.invalidInput)
        XCTAssertEqual(first.signals.lifts.windowStartDay, "0001-01-01")
        XCTAssertEqual(first.signals.lifts.windowEndDay, "0001-01-01")
        XCTAssertEqual(first.evidenceStartDay, "0001-01-01")

        // Lifts on the two days that do exist in the window are still found; the prior window is empty.
        let lifted = run(weighIn: "0001-01-03", lifts: [lift("0001-01-01", "Squat", 100), lift("0001-01-02", "Squat", 100)])
        XCTAssertEqual(lifted.signals.lifts, CutScorecardLiftSignal(state: .unknown, reason: .noSessionsPriorWeek,
                                                                    commonExercises: 0, dropped: 0, climbed: 0, held: 0,
                                                                    windowStartDay: "0001-01-01", windowEndDay: "0001-01-02"))
        // Eight days in, nothing needs clamping.
        let ninth = run(weighIn: "0001-01-09")
        XCTAssertEqual(ninth.signals.lifts.windowStartDay, "0001-01-02")
        XCTAssertEqual(ninth.signals.lifts.windowEndDay, "0001-01-08")
    }

    // MARK: - R22: integer parameters up to Int.max

    func testIntegerParametersAreValidUpToIntMax() {
        let slow: [Double?] = [100.0, 99.9, 99.8, 99.7]
        let flat: [Double?] = [100.0, 100.0, 100.0, 100.0]
        let dropping = F.pressSessions([(-1, 100), (0, 100), (1, 100), (2, 90), (3, 80), (4, 70)])

        // Calorie amounts: reported exactly, and the negation of Int.max does not overflow.
        let amounts = F.params { $0.addCaloriesKcal = .max; $0.reduceCarbsKcal = .max }
        let add = evaluate(F.scenario(weights: [100.0, 99.2, 98.4, 97.6], lifts: dropping, parameters: amounts))
        assertCutVerdict(add, .addCalories, .ruleFired, rule: r2, kcal: .max)
        let reduce = evaluate(F.scenario(weights: slow, waists: flat, lifts: F.holdingSessions(weeks: -1...4),
                                         parameters: amounts))
        assertCutVerdict(reduce, .reduceCarbs, .ruleFired, rule: r3, kcal: -Int.max)

        // Age and horizon: nothing is ever overdue or beyond the horizon.
        let patient = F.params { $0.maxWeighInAgeWeeks = .max; $0.maxProjectionWeeks = .max }
        let old = evaluate(F.scenario(weights: [100.0, 99.999], phase: F.phase(target: 50.0), parameters: patient,
                                      today: "2031-01-15"))
        XCTAssertNil(old.invalidInput)
        // 49.999 kg at 0.001 kg per week is 49,999 weeks: 349,993 days after 2031-01-15, inside year 9999.
        XCTAssertEqual(old.projection.status, .projected)
        XCTAssertEqual(old.projection.targetDay, F.day("2031-01-15", 349_993))
        XCTAssertEqual(old.projection.weeksRemaining ?? 0, 49_999, accuracy: 1e-6)
        let years = evaluate(F.scenario(weights: [100.0, 99.2], parameters: patient, today: "2099-12-31"))
        XCTAssertNotEqual(years.verdict.reason, .weighInOverdue)
        assertCutRate(years, loss: 0.8, percent: 0.803)

        // Windows and counts: valid, echoed in `requiredWeeks`, and the rules behave as with any window
        // longer than the phase.
        let wide = F.params {
            $0.rateWindowWeeks = .max; $0.waistWindowWeeks = .max
            $0.liftDropConsecutiveWeeks = .max; $0.slowLossConsecutiveWeeks = .max
        }
        let result = evaluate(F.scenario(weights: slow, waists: flat, parameters: wide))
        XCTAssertNil(result.invalidInput)
        XCTAssertEqual(result.rules.map(\.requiredWeeks), [1, .max, .max])
        assertCutRules(result, "NUU", reasons: [nil, .fewerWeeksThanWindow, .fewerWeeksThanWindow])
        XCTAssertEqual(result.rule(2)?.consecutiveWeeks, 3)
        XCTAssertEqual(result.rate?.pointsUsed, 4)
        XCTAssertEqual(result.signals.waist.referenceWeekStart, F.weekOneMonday)
        assertCutVerdict(result, .holdSteady, .noChangeRuleFired, unevaluated: [r2, r3])
    }

    // MARK: - R23: runs stop at the phase

    func testConsecutiveWeeksNeverCountsAWeekBeforeThePhase() {
        let weights: [Double?] = [100.0, 99.9, 99.8, 99.7, 99.6, 99.5]
        // Each Monday 20 kg lighter than the last: at least a 10 % drop every week, well past the 5 % line.
        let lifts = F.pressSessions([(0, 200), (1, 180), (2, 160), (3, 140), (4, 120), (5, 100), (6, 80)])
        // The phase covers all six weeks: lifts drop in every week and the loss is slow in five.
        let whole = evaluate(F.scenario(weights: weights, lifts: lifts))
        XCTAssertEqual(whole.rules.map(\.consecutiveWeeks), [0, 6, 5])
        // The phase starts in week 3. Weeks 1 and 2 dropped and were slow as well, and are not counted:
        // rule 2 runs over weeks 3 to 6, and rule 3 over weeks 4 to 6 because week 3 is the baseline.
        let clipped = evaluate(F.scenario(weights: weights, lifts: lifts, phase: F.phase(startDay: F.monday(3))))
        XCTAssertEqual(clipped.rules.map(\.consecutiveWeeks), [0, 4, 3])
        assertCutRules(clipped, "NFF")
        assertCutVerdict(clipped, .addCalories, .ruleFired, rule: r2, kcal: 300, overridden: [r3])
        // A phase that starts in the judged week: a run of one for rule 2 and none for rule 3.
        let last = evaluate(F.scenario(weights: weights, lifts: lifts, phase: F.phase(startDay: F.monday(6))))
        XCTAssertEqual(last.rules.map(\.consecutiveWeeks), [0, 1, 0])
        assertCutRules(last, "NUU", reasons: [nil, .fewerWeeksThanWindow, .fewerWeeksThanWindow])
    }
}
