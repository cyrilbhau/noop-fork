import XCTest
@testable import StrandAnalytics

private typealias F = CutScorecardFixture
private let r1 = CutScorecardRule.liftsHoldingWaistShrinking
private let r2 = CutScorecardRule.liftsDropping
private let r3 = CutScorecardRule.slowLoss

/// `CutScorecard.evaluate`: one named test for each ruling of
/// `docs/personal/superapp/specs/stage-1.md` §18 that the earlier suites left untested because the
/// specification had not yet decided it. Expected values come from §7 read with the rulings.
///
/// R1 (uncapped `consecutiveWeeks`) and R16 (variant V8) are asserted where they already were:
/// `CutScorecardTests.testConsecutiveWeeksKeepsCountingPastTheRequiredWindow`,
/// `CutScorecardTests.testFixtureVariants` and
/// `CutScorecardSeriesTests.testSingleOutlierWeekMovesRateLessThanEndpointDifference`. R17 concerns the
/// parity oracle, which is not part of these suites.
final class CutScorecardRulingTests: XCTestCase {

    /// The arithmetic limit of ruling R3.
    private let limit = 1e100
    private let today = "2031-01-15"
    private let twoWeeks: [Double?] = [100.0, 99.2]
    private let good = [F.weight("2031-01-08", 100.0), F.weight("2031-01-15", 99.2)]
    private let noRejections = CutScorecardRejections(nonFinite: 0, nonPositive: 0, invalidDay: 0, future: 0)

    private func evaluate(_ input: CutScorecardInput) -> CutScorecardResult {
        CutScorecard.evaluate(input)
    }

    private func rejections(_ nonFinite: Int = 0, _ nonPositive: Int = 0, _ invalidDay: Int = 0,
                            _ future: Int = 0) -> CutScorecardRejections {
        CutScorecardRejections(nonFinite: nonFinite, nonPositive: nonPositive, invalidDay: invalidDay, future: future)
    }

    private func lift(_ day: String, _ exercise: String, _ kg: Double) -> CutScorecardLiftObservation {
        CutScorecardLiftObservation(day: day, exercise: exercise, weightKg: kg)
    }

    /// What ruling R2 allows an older item to change.
    private enum Exception { case rateUnavailable, liftReason, consecutiveWeeks }

    /// Asserts `after` equals `before` in every field except `weeks` and the listed exceptions.
    private func assertUnchanged(_ after: CutScorecardResult, _ before: CutScorecardResult,
                                 except exceptions: Set<Exception> = [], _ label: String = "",
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(after.verdict, before.verdict, "\(label) verdict", file: file, line: line)
        XCTAssertEqual(after.rate, before.rate, "\(label) rate", file: file, line: line)
        XCTAssertEqual(after.projection, before.projection, "\(label) projection", file: file, line: line)
        XCTAssertEqual(after.signals.waist, before.signals.waist, "\(label) waist", file: file, line: line)
        XCTAssertEqual(after.signals.protein, before.signals.protein, "\(label) protein", file: file, line: line)
        XCTAssertEqual(after.signals.rateBand, before.signals.rateBand, "\(label) rate band", file: file, line: line)
        let a = after.signals.lifts, b = before.signals.lifts
        XCTAssertEqual(a.state, b.state, "\(label) lift state", file: file, line: line)
        XCTAssertEqual([a.commonExercises, a.dropped, a.climbed, a.held], [b.commonExercises, b.dropped, b.climbed, b.held],
                       "\(label) lift counts", file: file, line: line)
        XCTAssertEqual([a.windowStartDay, a.windowEndDay], [b.windowStartDay, b.windowEndDay],
                       "\(label) lift window", file: file, line: line)
        if !exceptions.contains(.liftReason) {
            XCTAssertEqual(a.reason, b.reason, "\(label) lift reason", file: file, line: line)
        }
        XCTAssertEqual(after.rules.map(\.rule), before.rules.map(\.rule), "\(label) rule order", file: file, line: line)
        XCTAssertEqual(after.rules.map(\.state), before.rules.map(\.state), "\(label) rule states", file: file, line: line)
        XCTAssertEqual(after.rules.map(\.unknownReason), before.rules.map(\.unknownReason), "\(label) rule reasons",
                       file: file, line: line)
        XCTAssertEqual(after.rules.map(\.requiredWeeks), before.rules.map(\.requiredWeeks), "\(label) required weeks",
                       file: file, line: line)
        if !exceptions.contains(.consecutiveWeeks) {
            XCTAssertEqual(after.rules.map(\.consecutiveWeeks), before.rules.map(\.consecutiveWeeks),
                           "\(label) consecutive weeks", file: file, line: line)
        }
        if !exceptions.contains(.rateUnavailable) {
            XCTAssertEqual(after.rateUnavailable, before.rateUnavailable, "\(label) rateUnavailable", file: file, line: line)
        }
        XCTAssertEqual(after.judgedWeekStart, before.judgedWeekStart, "\(label) judgedWeekStart", file: file, line: line)
        XCTAssertEqual(after.currentWeightKg, before.currentWeightKg, "\(label) currentWeightKg", file: file, line: line)
        XCTAssertEqual(after.currentWeightDay, before.currentWeightDay, "\(label) currentWeightDay", file: file, line: line)
        XCTAssertEqual(after.evidenceStartDay, before.evidenceStartDay, "\(label) evidenceStartDay", file: file, line: line)
        XCTAssertEqual(after.rejections, before.rejections, "\(label) rejections", file: file, line: line)
        XCTAssertEqual(after.invalidInput, before.invalidInput, "\(label) invalidInput", file: file, line: line)
    }

    // MARK: - R2: what an item before `evidenceStartDay` may change

    func testOlderWeightCanTurnSingleReadingIntoGapLongerThanWindowAndNothingElse() {
        // One weigh-in in week 12; `evidenceStartDay` is the Monday of week 6.
        let before = evaluate(F.make(weights: [F.weight(F.weighInDay(12), 98.0)], today: F.weighInDay(12)))
        XCTAssertEqual(before.evidenceStartDay, F.monday(6))
        assertCutNoRate(before, .singleReading)
        // The same with a weigh-in in week 1, five weeks before `evidenceStartDay`.
        let after = evaluate(F.make(weights: [F.weight(F.weighInDay(1), 100.0), F.weight(F.weighInDay(12), 98.0)],
                                    today: F.weighInDay(12)))
        assertCutNoRate(after, .gapLongerThanWindow)
        assertUnchanged(after, before, except: [.rateUnavailable])
        XCTAssertEqual(before.weeks.count, 1)
        XCTAssertEqual(after.weeks.count, 12, "`weeks` grows back to the older reading")
        XCTAssertEqual(after.weeks.last, before.weeks.last)
    }

    func testOlderLiftCanTurnNoLiftDataIntoNoSessionsThisWeekAndNothingElse() {
        let before = evaluate(F.scenario(weights: twoWeeks, waists: [100.0, 99.5]))
        XCTAssertEqual(before.signals.lifts.reason, .noLiftData)
        // One lift observation 400 days before the weigh-in; `evidenceStartDay` is 2030-12-02.
        let old = lift(F.day(today, -400), F.pressName, 100)
        XCTAssertLessThan(old.day, before.evidenceStartDay ?? "")
        let after = evaluate(F.scenario(weights: twoWeeks, waists: [100.0, 99.5], lifts: [old]))
        XCTAssertEqual(after.signals.lifts.reason, .noSessionsThisWeek)
        assertUnchanged(after, before, except: [.liftReason])
        XCTAssertEqual(after.weeks, before.weeks, "a lift observation never touches `weeks`")
    }

    func testOlderWeightCanLengthenTheSlowLossRunAndNothingElse() {
        // Slow weigh-ins in weeks 2 to 8: six weekly losses, so a run of six against a window of three.
        // `evidenceStartDay` is the Monday of week 2, so a weigh-in in week 1 is dated before it.
        let slow: [Double?] = [nil, 99.9, 99.8, 99.7, 99.6, 99.5, 99.4, 99.3]
        let before = evaluate(F.scenario(weights: slow))
        XCTAssertEqual(before.evidenceStartDay, F.monday(2))
        XCTAssertEqual(before.rule(2)?.state, .fired)
        XCTAssertEqual(before.rule(2)?.consecutiveWeeks, 6)

        let after = evaluate(F.make(weights: F.weekly(slow) + [F.weight(F.weighInDay(1), 100.0)], today: F.weighInDay(8)))
        XCTAssertEqual(after.rule(2)?.state, .fired)
        XCTAssertEqual(after.rule(2)?.consecutiveWeeks, 7, "week 2 now has a loss, and it is slow")
        XCTAssertEqual(after.rules.map(\.consecutiveWeeks), [0, 0, 7])
        assertUnchanged(after, before, except: [.consecutiveWeeks])
        // Inside `weeks` the older reading adds its own week and gives the next one a loss.
        XCTAssertEqual(before.weeks.map(\.weeklyLossKg), [nil, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1])
        XCTAssertEqual(after.weeks.map(\.weeklyLossKg), [nil, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1])
        XCTAssertEqual(Array(after.weeks.suffix(6)), Array(before.weeks.suffix(6)))
    }

    func testOlderLiftCanLengthenTheDroppingRunAndNothingElse() {
        // Weigh-ins in weeks 2 to 8 and a press session each Monday of weeks 2 to 8, 10 kg lighter every
        // week. Week 2 has nothing to compare with, so the dropping run is weeks 3 to 8: six.
        let weights: [Double?] = [nil, 100.0, 99.2, 98.4, 97.6, 96.8, 96.0, 95.2]
        let sessions = F.pressSessions([(2, 180), (3, 170), (4, 160), (5, 150), (6, 140), (7, 130), (8, 120)])
        let before = evaluate(F.scenario(weights: weights, lifts: sessions))
        XCTAssertEqual(before.evidenceStartDay, F.monday(2))
        XCTAssertEqual(before.rule(1)?.state, .fired)
        XCTAssertEqual(before.rule(1)?.consecutiveWeeks, 6)

        // A session on the Monday of week 1 is dated before `evidenceStartDay` and is week 2's "previous".
        let after = evaluate(F.scenario(weights: weights, lifts: sessions + F.pressSessions([(1, 190)])))
        XCTAssertEqual(after.rule(1)?.consecutiveWeeks, 7)
        assertUnchanged(after, before, except: [.consecutiveWeeks])
        XCTAssertEqual(after.weeks, before.weeks)
        assertCutVerdict(after, .addCalories, .ruleFired, rule: r2, kcal: 300)
    }

    // MARK: - R3: the arithmetic limit

    func testMagnitudeAboveTheArithmeticLimitIsRejectedAsNonFinite() {
        let above = limit.nextUp
        let clean = evaluate(F.make(weights: good, today: today))

        // A weight, a waist, a lift weight and a protein total just above the limit: each dropped and
        // counted as nonFinite, and the result is what it would be without them.
        let weight = evaluate(F.make(weights: good + [F.weight("2031-01-15", above)], today: today))
        XCTAssertEqual(weight.rejections, rejections(1), "weight")
        XCTAssertEqual(weight.weeks, clean.weeks, "weight")
        XCTAssertEqual(weight.currentWeightKg, 99.2, "weight")
        XCTAssertEqual(weight.rate, clean.rate, "weight")

        let waist = evaluate(F.make(weights: good, waists: [F.waist("2031-01-15", above)], today: today))
        XCTAssertEqual(waist.rejections, rejections(1), "waist")
        XCTAssertEqual(waist.weeks, clean.weeks, "waist")
        XCTAssertEqual(waist.signals, clean.signals, "waist")

        let lifted = evaluate(F.make(weights: good, lifts: [lift("2031-01-13", F.pressName, above)], today: today))
        XCTAssertEqual(lifted.rejections, rejections(1), "lift")
        XCTAssertEqual(lifted.signals, clean.signals, "lift")
        XCTAssertEqual(lifted.signals.lifts.reason, .noLiftData, "lift")

        let protein = evaluate(F.make(weights: good,
                                      proteinDays: [CutScorecardProteinDay(day: "2031-01-14", grams: above)], today: today))
        XCTAssertEqual(protein.rejections, rejections(1), "protein")
        XCTAssertEqual(protein.signals, clean.signals, "protein")
        XCTAssertEqual(protein.signals.protein.daysLogged, 0, "protein")

        // Exactly at the limit each is valid: nothing is rejected and nothing traps.
        let atLimit = evaluate(F.make(
            weights: [F.weight("2031-01-08", limit), F.weight("2031-01-15", limit)],
            waists: [F.waist("2031-01-08", limit), F.waist("2031-01-15", limit)],
            lifts: [lift("2031-01-06", F.pressName, limit), lift("2031-01-13", F.pressName, limit)],
            proteinDays: [CutScorecardProteinDay(day: "2031-01-14", grams: limit)], today: today))
        XCTAssertEqual(atLimit.rejections, rejections(), "at the limit")
        XCTAssertNil(atLimit.invalidInput, "at the limit")
        XCTAssertEqual(atLimit.weeks.count, 2, "at the limit")
        XCTAssertNotNil(atLimit.week(1)?.weightKg, "at the limit")
        XCTAssertNotNil(atLimit.week(1)?.waistCm, "at the limit")
        XCTAssertEqual(atLimit.week(1)?.weeklyLossKg, 0, "at the limit")
        XCTAssertEqual(atLimit.rate?.lossKgPerWeek, 0, "at the limit")
        XCTAssertEqual(atLimit.signals.lifts.reason, .holding, "at the limit")
        XCTAssertEqual(atLimit.signals.lifts.held, 1, "at the limit")
        XCTAssertEqual(atLimit.signals.protein.daysLogged, 1, "at the limit")
        XCTAssertEqual(atLimit.signals.protein.daysAtOrAboveFloor, 1, "at the limit")
        XCTAssertEqual(atLimit.signals.waist.state, .notMet, "at the limit")

        // The limit is on the magnitude: a value below -1e100 is nonFinite, not nonPositive, and one at
        // exactly -1e100 is an ordinary negative.
        let negative = evaluate(F.make(weights: good + [F.weight("2031-01-15", -above), F.weight("2031-01-15", -limit)],
                                       today: today))
        XCTAssertEqual(negative.rejections, rejections(1, 1), "negative")
        XCTAssertEqual(negative.weeks, clean.weeks, "negative")
    }

    func testParameterOrPhaseBoundAboveTheArithmeticLimitIsInvalidInput() {
        let above = limit.nextUp
        func invalid(parameters: CutScorecardParameters = F.parameters, phase: CutScorecardPhase? = F.phase)
            -> CutScorecardInvalidInput? {
            evaluate(F.input(today: F.weighInDay(9), phase: phase, parameters: parameters)).invalidInput
        }
        // Every Double parameter whose own range allows a value that large.
        XCTAssertEqual(invalid(parameters: F.params { $0.waistMinDecreaseCm = above }), .parameters)
        XCTAssertEqual(invalid(parameters: F.params { $0.slowLossThresholdKgPerWeek = above }), .parameters)
        XCTAssertEqual(invalid(parameters: F.params { $0.targetToleranceKg = above }), .parameters)
        XCTAssertEqual(invalid(parameters: F.params { $0.proteinFloorGrams = above }), .parameters)
        // Exactly at the limit they are valid, and evaluating with them does not trap.
        XCTAssertNil(invalid(parameters: F.params { $0.waistMinDecreaseCm = self.limit }))
        XCTAssertNil(invalid(parameters: F.params { $0.slowLossThresholdKgPerWeek = self.limit }))
        XCTAssertNil(invalid(parameters: F.params { $0.targetToleranceKg = self.limit }))
        XCTAssertNil(invalid(parameters: F.params { $0.proteinFloorGrams = self.limit }))

        // The phase target and both band bounds.
        XCTAssertEqual(invalid(phase: F.phase(target: above)), .phase)
        XCTAssertEqual(invalid(phase: F.phase(low: 0.4, high: above)), .phase)
        XCTAssertEqual(invalid(phase: F.phase(low: above, high: above)), .phase)
        XCTAssertNil(invalid(phase: F.phase(target: limit)))
        XCTAssertNil(invalid(phase: F.phase(low: 0.4, high: limit)))
        XCTAssertNil(invalid(phase: F.phase(low: limit, high: limit)))

        // The invalid result is the whole §6.5 result, not a partial evaluation.
        let result = evaluate(F.input(today: F.weighInDay(9), phase: F.phase(target: above)))
        XCTAssertEqual(result.weeks, [])
        assertCutVerdict(result, .insufficientData, .invalidInput)
    }

    // MARK: - R4: positive zero

    func testQuantizeReturnsPositiveZeroAndPassesThroughWhatItCannotScale() {
        for x in [-0.0, 0.0, -0.0004, -0.00049, 0.0004, -5e-324] {
            let quantized = CutScorecard.quantize(x)
            XCTAssertEqual(quantized, 0, "\(x)")
            XCTAssertEqual(quantized.sign, .plus, "\(x): never negative zero")
        }
        // A negative value that does not round to zero keeps its sign.
        XCTAssertEqual(CutScorecard.quantize(-0.0005), -0.001)

        // The guard: when |x| x 1000 is not finite the argument comes back unchanged.
        XCTAssertEqual(CutScorecard.quantize(.infinity), .infinity)
        XCTAssertEqual(CutScorecard.quantize(-.infinity), -.infinity)
        XCTAssertTrue(CutScorecard.quantize(.nan).isNaN)
        XCTAssertEqual(CutScorecard.quantize(1e306), 1e306)
        XCTAssertEqual(CutScorecard.quantize(-1e306), -1e306)

        // Through `evaluate`: a week 0.0004 kg heavier is a loss of zero, a rate of zero and a percentage
        // of zero, each positive.
        let result = evaluate(F.scenario(weights: [100.0, 100.0004], waists: [100.0, 99.9996]))
        XCTAssertEqual(result.week(1)?.weeklyLossKg, 0)
        XCTAssertEqual(result.week(1)?.weeklyLossKg?.sign, .plus)
        XCTAssertEqual(result.rate?.lossKgPerWeek, 0)
        XCTAssertEqual(result.rate?.lossKgPerWeek.sign, .plus)
        XCTAssertEqual(result.rate?.percentPerWeek.sign, .plus)
        XCTAssertEqual(result.signals.waist.changeCm, 0)
        XCTAssertEqual(result.signals.waist.changeCm?.sign, .plus)
        // And a weight 0.0004 kg under the target has zero remaining, positive.
        let reached = evaluate(F.scenario(weights: [93.9996]))
        XCTAssertEqual(reached.projection.status, .targetReached)
        XCTAssertEqual(reached.projection.remainingKg, 0)
        XCTAssertEqual(reached.projection.remainingKg?.sign, .plus)
    }

    // MARK: - R5: canonical day keys

    func testNonCanonicalDayKeysAreInvalidEverywhere() {
        // Each of these names, or nearly names, a real day, and none is the ten-character yyyy-MM-dd form
        // with a year from 0001 to 9999.
        let keys = ["2031-1-8", "2031-01-8", "2031-1-08", "+2031-01-08", "2031-+1-08", "2031-01-+8", "-031-01-08",
                    "0000-01-01", "10000-01-01", "02031-01-08", "2031/01/08", "20310108", " 2031-01-08",
                    "2031-01-08 ", "2031-01-08T00:00", "2031- 1-08", "31-01-08"]

        for key in keys {
            XCTAssertNil(CutScorecard.weekStart(containing: key), "weekStart \"\(key)\"")
            XCTAssertEqual(evaluate(F.input(today: key)).invalidInput, .today, "today \"\(key)\"")
            XCTAssertEqual(evaluate(F.input(today: F.weighInDay(9), phase: F.phase(startDay: key))).invalidInput, .phase,
                           "phase start \"\(key)\"")
        }

        // As the day of a reading, a lift observation or a protein day, each is dropped and counted.
        let clean = evaluate(F.make(weights: good, today: today))
        let result = evaluate(F.make(
            weights: good + keys.map { CutScorecardReading(day: $0, takenAt: 0, value: 90.0) },
            waists: keys.map { CutScorecardReading(day: $0, takenAt: 0, value: 90.0) },
            lifts: keys.map { lift($0, F.pressName, 60) },
            proteinDays: keys.map { CutScorecardProteinDay(day: $0, grams: 120) }, today: today))
        XCTAssertEqual(result.rejections, rejections(0, 0, 4 * keys.count))
        XCTAssertEqual(result.weeks, clean.weeks)
        XCTAssertEqual(result.signals, clean.signals)
        XCTAssertEqual(result.verdict, clean.verdict)
        XCTAssertNil(result.invalidInput)

        // The first and the last valid years are valid.
        XCTAssertEqual(CutScorecard.weekStart(containing: "0001-01-01"), "0001-01-01", "a Monday")
        XCTAssertEqual(CutScorecard.weekStart(containing: "0001-01-07"), "0001-01-01", "the Sunday after")
        XCTAssertEqual(CutScorecard.weekStart(containing: "9999-12-31"), "9999-12-27", "a Friday")
        let first = evaluate(F.make(weights: [F.weight("0001-01-03", 100.0)], phase: F.phase(startDay: "0001-01-01"),
                                    today: "0001-01-03"))
        XCTAssertNil(first.invalidInput)
        XCTAssertEqual(first.rejections, rejections())
        XCTAssertEqual(first.weeks.map(\.weekStart), ["0001-01-01"])
    }

    // MARK: - R6 and R7: no active phase

    func testOverdueAppliesWithoutAnActivePhase() {
        let phases: [(CutScorecardPhase?, CutScorecardVerdictReason)] = [
            (nil, .noActivePhase), (F.phase(startDay: "2031-06-02"), .phaseNotStarted),
        ]
        for (phase, reason) in phases {
            func run(today: String) -> CutScorecardResult {
                evaluate(F.scenario(weights: twoWeeks, waists: [100.0, 99.5], lifts: F.holdingSessions(weeks: -1...2),
                                    proteinDays: [CutScorecardProteinDay(day: "2031-01-14", grams: 120)],
                                    phase: phase, today: today))
            }
            // One week after the last weigh-in: not overdue, so the rate and three signals are computed.
            let current = run(today: F.weighInDay(3))
            assertCutRate(current, loss: 0.8, percent: 0.803, "\(reason)")
            XCTAssertEqual(current.signals.waist.state, .met, "\(reason)")
            XCTAssertEqual(current.signals.lifts.state, .met, "\(reason)")
            XCTAssertEqual(current.signals.protein.reason, .incompleteLogging, "\(reason)")

            // Two weeks after: overdue.
            let overdue = run(today: F.weighInDay(4))
            assertCutNoRate(overdue, .weighInOverdue, "\(reason)")
            XCTAssertEqual(overdue.signals.waist, CutScorecardWaistSignal(state: .unknown, reason: .weighInOverdue,
                                                                          currentCm: nil, referenceCm: nil,
                                                                          referenceWeekStart: nil, changeCm: nil), "\(reason)")
            XCTAssertEqual(overdue.signals.lifts, CutScorecardLiftSignal(state: .unknown, reason: .weighInOverdue,
                                                                         commonExercises: 0, dropped: 0, climbed: 0, held: 0,
                                                                         windowStartDay: nil, windowEndDay: nil), "\(reason)")
            XCTAssertEqual(overdue.signals.protein, CutScorecardProteinSignal(state: .unknown, reason: .weighInOverdue,
                                                                              daysLogged: 0, daysAtOrAboveFloor: 0,
                                                                              requiredDays: 5, floorGrams: 100), "\(reason)")
            // The rate band, the rules, the projection and the verdict keep reporting the missing phase.
            XCTAssertEqual(overdue.signals.rateBand, CutScorecardRateBandSignal(state: .unknown, reason: .noActivePhase,
                                                                                percentPerWeek: nil, lowPercentPerWeek: nil,
                                                                                highPercentPerWeek: nil), "\(reason)")
            assertCutRules(overdue, "UUU", reasons: [.noActivePhase, .noActivePhase, .noActivePhase], "\(reason)")
            assertCutProjection(overdue, .noActivePhase, "\(reason)")
            assertCutVerdict(overdue, .insufficientData, reason, "\(reason)")
            // The series and the judged week are still reported.
            XCTAssertEqual(overdue.judgedWeekStart, F.monday(2), "\(reason)")
            XCTAssertEqual(overdue.evidenceStartDay, "2030-12-02", "\(reason)")
            XCTAssertEqual(overdue.weeks.map(\.weeklyLossKg), [nil, 0.8, nil, nil], "\(reason)")
            XCTAssertEqual(overdue.currentWeightKg, 99.2, "\(reason)")
        }
    }

    func testPhaseNotStartedIsTreatedExactlyAsNoPhase() {
        for week in [1, 4, 9, 11, 19] {
            let today = F.weighInDay(week)
            let none = evaluate(F.input(today: today, phase: nil))
            let notStarted = evaluate(F.input(today: today, phase: F.phase(startDay: F.day(today, 1))))
            let label = "week \(week)"
            // Everything but the verdict's reason is identical.
            XCTAssertEqual(notStarted.weeks, none.weeks, label)
            XCTAssertEqual(notStarted.judgedWeekStart, none.judgedWeekStart, label)
            XCTAssertEqual(notStarted.currentWeightKg, none.currentWeightKg, label)
            XCTAssertEqual(notStarted.currentWeightDay, none.currentWeightDay, label)
            XCTAssertEqual(notStarted.rate, none.rate, label)
            XCTAssertEqual(notStarted.rateUnavailable, none.rateUnavailable, label)
            XCTAssertEqual(notStarted.projection, none.projection, label)
            XCTAssertEqual(notStarted.signals, none.signals, label)
            XCTAssertEqual(notStarted.rules, none.rules, label)
            XCTAssertEqual(notStarted.evidenceStartDay, none.evidenceStartDay, label)
            XCTAssertEqual(notStarted.rejections, none.rejections, label)
            assertCutVerdict(none, .insufficientData, .noActivePhase, label)
            assertCutVerdict(notStarted, .insufficientData, .phaseNotStarted, label)

            // The domain is every week: nothing is in phase, every consecutive pair has a loss, and the
            // judged week is the latest week with a weight.
            XCTAssertTrue(notStarted.weeks.allSatisfy { !$0.inPhase }, label)
            XCTAssertEqual(notStarted.weeks.map(\.weeklyLossKg), evaluate(F.input(today: today)).weeks.map(\.weeklyLossKg), label)
            XCTAssertEqual(notStarted.judgedWeekStart, F.monday(week), label)
            // The band bounds are nil, although the phase that has not started has a band.
            XCTAssertEqual(notStarted.signals.rateBand, CutScorecardRateBandSignal(state: .unknown, reason: .noActivePhase,
                                                                                   percentPerWeek: nil, lowPercentPerWeek: nil,
                                                                                   highPercentPerWeek: nil), label)
        }
    }

    // MARK: - R8 and R9: the projection without and with an in-phase weight

    func testActivePhaseWithNoInPhaseWeighInProjectsNoTargetOrRateUnknown() {
        // No reading at all, and readings only before the phase.
        let inputs: [(String, [Double?], String)] = [("empty", [], "2031-01-08"), ("before the phase", [100.0, 99.2], "2031-02-03")]
        for (label, weights, today) in inputs {
            func run(target: Double?) -> CutScorecardResult {
                evaluate(F.scenario(weights: weights, phase: F.phase(startDay: today, target: target), today: today))
            }
            let withTarget = run(target: 94.0)
            XCTAssertEqual(withTarget.projection, CutScorecardProjection(status: .rateUnknown, targetDay: nil,
                                                                         weeksRemaining: nil, remainingKg: nil), label)
            assertCutVerdict(withTarget, .insufficientData, .noReadings, label)
            let withoutTarget = run(target: nil)
            XCTAssertEqual(withoutTarget.projection, CutScorecardProjection(status: .noTarget, targetDay: nil,
                                                                            weeksRemaining: nil, remainingKg: nil), label)
        }
        // A weight before the phase is the current weight, and is still not "in phase" for `remainingKg`.
        let before = evaluate(F.scenario(weights: [100.0, 99.2], phase: F.phase(startDay: "2031-02-03"), today: "2031-02-03"))
        XCTAssertEqual(before.currentWeightKg, 99.2)
        XCTAssertNil(before.projection.remainingKg)
    }

    func testRemainingKgIsSetWheneverATargetAndAnInPhaseWeightExist() {
        func remaining(_ weights: [Double?], target: Double? = 94.0, start: String = F.weekOneMonday,
                       horizon: Int = 104, today: String? = nil) -> (CutScorecardProjectionStatus, Double?) {
            let result = evaluate(F.scenario(weights: weights, phase: F.phase(startDay: start, target: target),
                                             parameters: F.params { $0.maxProjectionWeeks = horizon }, today: today))
            return (result.projection.status, result.projection.remainingKg)
        }
        func check(_ got: (CutScorecardProjectionStatus, Double?), _ status: CutScorecardProjectionStatus, _ kg: Double?,
                   line: UInt = #line) {
            XCTAssertEqual(got.0, status, line: line)
            XCTAssertEqual(got.1, kg, "\(status)", line: line)
        }
        // Set under every status that has a target and an in-phase weight, overdue included.
        check(remaining([100.0, 99.2], today: F.weighInDay(4)), .weighInOverdue, 5.2)
        check(remaining([100.0, 99.2], target: 99.5, today: F.weighInDay(4)), .weighInOverdue, -0.3)
        check(remaining([100.0, 93.5]), .targetReached, -0.5)
        check(remaining([100.0]), .rateUnknown, 6.0)
        check(remaining([100.0, 100.5]), .notLosing, 6.5)
        check(remaining([100.0, 99.2], horizon: 6), .beyondHorizon, 5.2)
        check(remaining([100.0, 99.2], target: 99.0, today: "2031-01-18"), .needsNewWeighIn, 0.2)
        check(remaining([100.0, 99.2]), .projected, 5.2)
        // Nil without a target, without a started phase, and without an in-phase weight.
        check(remaining([100.0, 99.2], target: nil), .noTarget, nil)
        check(remaining([100.0, 99.2], start: "2031-06-02"), .noActivePhase, nil)
        check(remaining([100.0, 99.2], start: "2031-01-20", today: "2031-01-20"), .rateUnknown, nil)
        XCTAssertNil(evaluate(F.scenario(weights: [100.0, 99.2], phase: nil)).projection.remainingKg)
    }

    // MARK: - R10: quantized operands on both sides

    func testEveryThresholdComparisonUsesQuantizedOperands() {
        // Lift share. Two of three exercises dropped: 2/3 = 0.6666…, which is below 0.667 as a Double and
        // equal to it once quantized. So the week is dropping at a share of 0.667 and holding at 0.668.
        XCTAssertLessThan(2.0 / 3.0, 0.667, "the premise")
        func lifts(share: Double) -> CutScorecardLiftSignal {
            let sets = ["A", "B", "C"].map { lift(F.day(today, -9), $0, 100) }
                + [lift(F.day(today, -2), "A", 90), lift(F.day(today, -2), "B", 90), lift(F.day(today, -2), "C", 100)]
            return evaluate(F.scenario(weights: twoWeeks, lifts: sets, parameters: F.params { $0.liftDropShare = share })).signals.lifts
        }
        XCTAssertEqual(lifts(share: 0.667), CutScorecardLiftSignal(state: .notMet, reason: .dropping, commonExercises: 3,
                                                                   dropped: 2, climbed: 0, held: 1,
                                                                   windowStartDay: "2031-01-08", windowEndDay: "2031-01-14"))
        XCTAssertEqual(lifts(share: 0.668).reason, .holding)
        XCTAssertEqual(lifts(share: 0.666).reason, .dropping)
        // The share parameter is quantized too: 0.6674 is 0.667.
        XCTAssertEqual(lifts(share: 0.6674).reason, .dropping)
        XCTAssertEqual(lifts(share: 0.6676).reason, .holding)

        // Band bounds. The rate is 0.803 percent per week. A low bound of 0.8034 is above it as a Double
        // and equal once quantized; a high bound of 0.8026 is below it as a Double and equal once quantized.
        func band(_ low: Double, _ high: Double) -> CutScorecardRateBandSignal {
            evaluate(F.scenario(weights: twoWeeks, phase: F.phase(low: low, high: high))).signals.rateBand
        }
        XCTAssertEqual(band(0.8034, 1.2).reason, .withinBand)
        XCTAssertEqual(band(0.8036, 1.2).reason, .belowBand, "0.8036 quantizes to 0.804")
        XCTAssertEqual(band(0.4, 0.8026).reason, .withinBand)
        XCTAssertEqual(band(0.4, 0.8024).reason, .aboveBand, "0.8024 quantizes to 0.802")

        // Horizon. 20.001 kg at 5 kg per week is 4.0002 weeks: above 4 as a Double, equal once quantized.
        func project(_ first: Double, _ second: Double, target: Double, horizon: Int) -> CutScorecardProjection {
            evaluate(F.scenario(weights: [first, second], phase: F.phase(target: target),
                                parameters: F.params { $0.maxProjectionWeeks = horizon })).projection
        }
        let fine = project(100.0, 95.0, target: 74.999, horizon: 4)
        XCTAssertEqual(fine.status, .projected)
        XCTAssertEqual(fine.remainingKg, 20.001)
        XCTAssertEqual(fine.targetDay, "2031-02-13", "28.0014 days quantizes to 28.001 and rounds up to 29")
        // The reported `weeksRemaining` is the unquantized quotient.
        XCTAssertEqual(fine.weeksRemaining ?? 0, 4.0002, accuracy: 1e-9)
        XCTAssertNotEqual(fine.weeksRemaining, 4.0)
        XCTAssertEqual(project(100.0, 95.0, target: 74.999, horizon: 3).status, .beyondHorizon)
        // The floating-point case: 2.1 / 0.3 is 7.000000000000001, which is not beyond a horizon of 7.
        XCTAssertGreaterThan(2.1 / 0.3, 7, "the premise")
        let hair = project(100.0, 99.7, target: 97.6, horizon: 7)
        XCTAssertEqual(hair.status, .projected)
        XCTAssertEqual(hair.targetDay, "2031-03-05")
        XCTAssertEqual(hair.weeksRemaining, 2.1 / 0.3, "unquantized")
    }

    // MARK: - R11: the ends of the calendar

    func testProjectedDayAfterYear9999IsBeyondHorizon() {
        // Weigh-ins on Wednesday 9999-12-15 and 9999-12-22, losing 0.8 kg per week.
        func project(target: Double) -> CutScorecardProjection {
            evaluate(F.make(weights: [F.weight("9999-12-15", 100.0), F.weight("9999-12-22", 99.2)],
                            phase: F.phase(startDay: "9999-11-01", target: target), today: "9999-12-22")).projection
        }
        // 0.8 kg: seven days, 9999-12-29.
        XCTAssertEqual(project(target: 98.4).targetDay, "9999-12-29")
        // 1.028 kg: 8.995 days, so nine, the last day there is.
        let last = project(target: 98.172)
        XCTAssertEqual(last.status, .projected)
        XCTAssertEqual(last.targetDay, "9999-12-31")
        // 1.029 kg: 9.004 days, so ten, which would be 10000-01-01. Well inside 104 weeks, and still
        // beyond the horizon.
        let past = project(target: 98.171)
        XCTAssertEqual(past, CutScorecardProjection(status: .beyondHorizon, targetDay: nil, weeksRemaining: nil,
                                                    remainingKg: 1.029))
        XCTAssertEqual(project(target: 97.6).status, .beyondHorizon)
    }

    func testEvidenceStartDayIsClampedToTheFirstDay() {
        func start(weighIn: String) -> CutScorecardResult {
            evaluate(F.make(weights: [F.weight(weighIn, 100.0)], phase: F.phase(startDay: "0001-01-01"), today: weighIn))
        }
        // The fixture windows give 42 days. From Monday 0001-02-19 that is 0001-01-08; from Monday
        // 0001-02-12 it is exactly 0001-01-01; from anything earlier it would be before the calendar.
        XCTAssertEqual(start(weighIn: "0001-02-21").evidenceStartDay, "0001-01-08")
        XCTAssertEqual(start(weighIn: "0001-02-14").evidenceStartDay, "0001-01-01")
        let clamped = start(weighIn: "0001-01-10")
        XCTAssertEqual(clamped.evidenceStartDay, "0001-01-01")
        XCTAssertEqual(clamped.judgedWeekStart, "0001-01-08")
        XCTAssertNil(clamped.invalidInput)
        XCTAssertEqual(clamped.weeks.count, 1)
        assertCutNoRate(clamped, .singleReading)
    }

    // MARK: - R12: order of checks

    func testInvalidInputIsReportedInTheOrderParametersPhaseToday() {
        let badParameters = F.params { $0.rateWindowWeeks = 0 }
        let badPhase = F.phase(low: 2, high: 1)
        func invalid(parameters: CutScorecardParameters = F.parameters, phase: CutScorecardPhase? = F.phase,
                     today: String = F.weighInDay(9)) -> CutScorecardInvalidInput? {
            let base = F.input(week: 9)
            return evaluate(F.make(weights: base.weights, waists: base.waists, lifts: base.lifts,
                                   proteinDays: base.proteinDays, phase: phase, parameters: parameters, today: today)).invalidInput
        }
        XCTAssertEqual(invalid(parameters: badParameters, phase: badPhase, today: "never"), .parameters)
        XCTAssertEqual(invalid(parameters: badParameters, phase: badPhase), .parameters)
        XCTAssertEqual(invalid(parameters: badParameters, today: "never"), .parameters)
        XCTAssertEqual(invalid(phase: badPhase, today: "never"), .phase)
        XCTAssertEqual(invalid(parameters: badParameters), .parameters)
        XCTAssertEqual(invalid(phase: badPhase), .phase)
        XCTAssertEqual(invalid(today: "never"), .today)
        XCTAssertNil(invalid())
    }

    func testAnItemWithSeveralFaultsIsCountedOnceInCategoryOrder() {
        func count(weights: [CutScorecardReading] = [], lifts: [CutScorecardLiftObservation] = [],
                   proteinDays: [CutScorecardProteinDay] = []) -> CutScorecardRejections {
            evaluate(F.make(weights: good + weights, lifts: lifts, proteinDays: proteinDays, today: today)).rejections
        }
        func reading(_ day: String, _ value: Double) -> CutScorecardReading {
            CutScorecardReading(day: day, takenAt: 0, value: value)
        }
        // nonFinite before everything.
        XCTAssertEqual(count(weights: [reading("2031-02-30", .nan)]), rejections(1), "NaN on an impossible day")
        XCTAssertEqual(count(weights: [reading("2031-06-01", .infinity)]), rejections(1), "infinite in the future")
        XCTAssertEqual(count(weights: [reading("2031-01-15", -.infinity)]), rejections(1), "negative infinity is nonFinite")
        XCTAssertEqual(count(weights: [reading("nonsense", -1e200)]), rejections(1), "beyond the limit, negative, bad day")
        // nonPositive before invalidDay and future.
        XCTAssertEqual(count(weights: [reading("2031-02-30", -5)]), rejections(0, 1), "negative on an impossible day")
        XCTAssertEqual(count(weights: [reading("2031-06-01", 0)]), rejections(0, 1), "zero in the future")
        XCTAssertEqual(count(lifts: [lift("2031-01-13", "", 0)]), rejections(0, 1), "zero weight, no exercise name")
        XCTAssertEqual(count(proteinDays: [CutScorecardProteinDay(day: "", grams: -1)]), rejections(0, 1), "negative protein, no day")
        // invalidDay before future: an unnamed exercise counts as invalidDay even on a future day.
        XCTAssertEqual(count(lifts: [lift("2031-06-01", "", 60)]), rejections(0, 0, 1), "no exercise name, in the future")
        // A zero protein total is not a fault, so the day decides.
        XCTAssertEqual(count(proteinDays: [CutScorecardProteinDay(day: "2031-06-01", grams: 0)]), rejections(0, 0, 0, 1))
        // Each item is counted once: four items with nine faults between them are four rejections.
        XCTAssertEqual(count(weights: [reading("2031-02-30", .nan), reading("nonsense", -1e200),
                                       reading("2031-02-30", -5), reading("2031-06-01", 0)]), rejections(2, 2))
    }

    // MARK: - R13: secondary fields

    func testSecondaryFieldsOfUnknownSignals() {
        let noFloor = F.params { $0.proteinFloorGrams = nil; $0.proteinMinDaysPerWeek = 6 }
        let day = CutScorecardProteinDay(day: "2031-01-14", grams: 120)

        // A judged week is evaluated: waist missing, no lift data, no protein floor.
        let judged = evaluate(F.scenario(weights: twoWeeks, waists: [100.0, nil], proteinDays: [day], parameters: noFloor))
        XCTAssertEqual(judged.signals.waist, CutScorecardWaistSignal(state: .unknown, reason: .noWaistThisWeek, currentCm: nil,
                                                                     referenceCm: nil, referenceWeekStart: nil, changeCm: nil))
        XCTAssertEqual(judged.signals.lifts, CutScorecardLiftSignal(state: .unknown, reason: .noLiftData, commonExercises: 0,
                                                                    dropped: 0, climbed: 0, held: 0,
                                                                    windowStartDay: "2031-01-08", windowEndDay: "2031-01-14"))
        XCTAssertEqual(judged.signals.protein, CutScorecardProteinSignal(state: .unknown, reason: .noFloorConfigured,
                                                                         daysLogged: 1, daysAtOrAboveFloor: 0,
                                                                         requiredDays: 6, floorGrams: nil),
                       "`daysLogged` is counted even with no floor")

        // `noEarlierWaist` carries the current reading and nothing else.
        XCTAssertEqual(evaluate(F.scenario(weights: twoWeeks, waists: [nil, 99.5])).signals.waist,
                       CutScorecardWaistSignal(state: .unknown, reason: .noEarlierWaist, currentCm: 99.5, referenceCm: nil,
                                               referenceWeekStart: nil, changeCm: nil))

        // The other unknown lift reasons: counts zero, window days set.
        let lifts: [(CutScorecardLiftReason, [CutScorecardLiftObservation])] = [
            (.noSessionsThisWeek, [lift("2031-01-06", F.pressName, 100)]),
            (.noSessionsPriorWeek, [lift("2031-01-13", F.pressName, 100)]),
            (.noCommonExercises, [lift("2031-01-06", F.pressName, 100), lift("2031-01-13", F.rowName, 50)]),
        ]
        for (reason, sets) in lifts {
            XCTAssertEqual(evaluate(F.scenario(weights: twoWeeks, lifts: sets)).signals.lifts,
                           CutScorecardLiftSignal(state: .unknown, reason: reason, commonExercises: 0, dropped: 0, climbed: 0,
                                                  held: 0, windowStartDay: "2031-01-08", windowEndDay: "2031-01-14"), "\(reason)")
        }

        // Protein with a floor and nothing logged, and the rate band with a started phase and no rate.
        let single = evaluate(F.scenario(weights: [100.0]))
        XCTAssertEqual(single.signals.protein, CutScorecardProteinSignal(state: .unknown, reason: .noProteinData, daysLogged: 0,
                                                                         daysAtOrAboveFloor: 0, requiredDays: 5, floorGrams: 100))
        XCTAssertEqual(single.signals.rateBand, CutScorecardRateBandSignal(state: .unknown, reason: .rateUnknown,
                                                                           percentPerWeek: nil, lowPercentPerWeek: 0.40,
                                                                           highPercentPerWeek: 1.20))

        // No in-phase reading, and an overdue one: everything zero and nil, except what the protein signal
        // and the rate band always carry.
        let cases: [(String, CutScorecardResult, CutScorecardWaistReason, CutScorecardLiftReason,
                     CutScorecardProteinReason, CutScorecardRateBandReason)] = [
            ("no readings", evaluate(F.make(lifts: F.holdingSessions(weeks: -1...2), proteinDays: [day], today: today)),
             .noReadings, .noReadings, .noReadings, .noReadings),
            ("overdue", evaluate(F.scenario(weights: twoWeeks, waists: [100.0, 99.5], lifts: F.holdingSessions(weeks: -1...2),
                                            proteinDays: [day], today: F.weighInDay(4))),
             .weighInOverdue, .weighInOverdue, .weighInOverdue, .weighInOverdue),
        ]
        for (label, result, waist, liftReason, protein, band) in cases {
            XCTAssertEqual(result.signals.waist, CutScorecardWaistSignal(state: .unknown, reason: waist, currentCm: nil,
                                                                         referenceCm: nil, referenceWeekStart: nil,
                                                                         changeCm: nil), label)
            XCTAssertEqual(result.signals.lifts, CutScorecardLiftSignal(state: .unknown, reason: liftReason, commonExercises: 0,
                                                                        dropped: 0, climbed: 0, held: 0, windowStartDay: nil,
                                                                        windowEndDay: nil), label)
            XCTAssertEqual(result.signals.protein, CutScorecardProteinSignal(state: .unknown, reason: protein, daysLogged: 0,
                                                                             daysAtOrAboveFloor: 0, requiredDays: 5,
                                                                             floorGrams: 100), label)
            XCTAssertEqual(result.signals.rateBand, CutScorecardRateBandSignal(state: .unknown, reason: band, percentPerWeek: nil,
                                                                               lowPercentPerWeek: 0.40, highPercentPerWeek: 1.20),
                           "\(label): a started phase exists, so the bounds are carried")
        }
    }

    func testRulesInAPreconditionFailedStateCarryNoRunAndTheirRequiredWeeks() {
        let parameters = F.params { $0.liftDropConsecutiveWeeks = 2; $0.slowLossConsecutiveWeeks = 4 }
        func expected(_ reason: CutScorecardRuleUnknownReason) -> [CutScorecardRuleEvaluation] {
            [CutScorecardRuleEvaluation(rule: r1, state: .unknown, unknownReason: reason, consecutiveWeeks: 0, requiredWeeks: 1),
             CutScorecardRuleEvaluation(rule: r2, state: .unknown, unknownReason: reason, consecutiveWeeks: 0, requiredWeeks: 2),
             CutScorecardRuleEvaluation(rule: r3, state: .unknown, unknownReason: reason, consecutiveWeeks: 0, requiredWeeks: 4)]
        }
        // Slow weigh-ins and dropping lifts, so there are runs to report if the precondition were ignored.
        let weights: [Double?] = [100.0, 99.9, 99.8, 99.7, 99.6]
        let lifts = F.pressSessions([(0, 100), (1, 90), (2, 80), (3, 70), (4, 60), (5, 50)])
        func run(phase: CutScorecardPhase? = F.phase, today: String? = nil) -> [CutScorecardRuleEvaluation] {
            evaluate(F.scenario(weights: weights, lifts: lifts, phase: phase, parameters: parameters, today: today)).rules
        }
        XCTAssertEqual(evaluate(F.make(parameters: parameters, today: today)).rules, expected(.noReadings))
        XCTAssertEqual(run(today: F.weighInDay(7)), expected(.weighInOverdue))
        XCTAssertEqual(run(phase: nil), expected(.noActivePhase))
        XCTAssertEqual(run(phase: F.phase(startDay: "2031-06-02")), expected(.noActivePhase))
        // The control: with the phase active and the weigh-in current the runs are there.
        XCTAssertEqual(run().map(\.consecutiveWeeks), [0, 5, 4])

        // Overdue keeps the judged week and its evidence day (m = 4, so 42 days back).
        let overdue = evaluate(F.scenario(weights: weights, lifts: lifts, parameters: parameters, today: F.weighInDay(7)))
        XCTAssertEqual(overdue.judgedWeekStart, F.monday(5))
        XCTAssertEqual(overdue.evidenceStartDay, F.day(F.monday(5), -42))
    }

    func testInvalidResultEchoesParametersAndCarriesNothingElse() {
        func invalid(_ change: (inout CutScorecardParameters) -> Void, phase: CutScorecardPhase? = F.phase,
                     today: String = F.weighInDay(9)) -> CutScorecardResult {
            let base = F.input(week: 9)
            return evaluate(F.make(weights: base.weights, waists: base.waists, lifts: base.lifts,
                                   proteinDays: base.proteinDays, phase: phase, parameters: F.params(change), today: today))
        }
        // The parameters as given, including the invalid ones.
        let given = invalid { $0.liftDropConsecutiveWeeks = 0; $0.slowLossConsecutiveWeeks = -2; $0.proteinMinDaysPerWeek = 9 }
        XCTAssertEqual(given.invalidInput, .parameters)
        XCTAssertEqual(given.rules.map(\.requiredWeeks), [1, 0, -2])
        XCTAssertEqual(given.rules.map(\.consecutiveWeeks), [0, 0, 0])
        XCTAssertEqual(given.signals.protein, CutScorecardProteinSignal(state: .unknown, reason: .noReadings, daysLogged: 0,
                                                                        daysAtOrAboveFloor: 0, requiredDays: 9, floorGrams: 100))
        // `floorGrams` only when finite and positive.
        for bad in [0, -5, Double.nan, .infinity] {
            let result = invalid { $0.proteinFloorGrams = bad }
            XCTAssertEqual(result.invalidInput, .parameters, "\(bad)")
            XCTAssertNil(result.signals.protein.floorGrams, "\(bad)")
            XCTAssertEqual(result.signals.protein.requiredDays, 5, "\(bad)")
        }
        XCTAssertNil(invalid { $0.proteinFloorGrams = nil; $0.rateWindowWeeks = 0 }.signals.protein.floorGrams)

        // An invalid phase or today leaves valid parameters to echo.
        for result in [invalid({ $0.liftDropConsecutiveWeeks = 2 }, phase: F.phase(low: 2, high: 1)),
                       invalid({ $0.liftDropConsecutiveWeeks = 2 }, today: "never")] {
            XCTAssertNotNil(result.invalidInput)
            XCTAssertEqual(result.rules.map(\.requiredWeeks), [1, 2, 3])
            XCTAssertEqual(result.signals.protein.requiredDays, 5)
            XCTAssertEqual(result.signals.protein.floorGrams, 100)
            // Nothing is computed from the readings.
            XCTAssertNil(result.currentWeightKg)
            XCTAssertNil(result.judgedWeekStart)
            XCTAssertNil(result.evidenceStartDay)
            XCTAssertEqual(result.signals.waist, CutScorecardWaistSignal(state: .unknown, reason: .noReadings, currentCm: nil,
                                                                         referenceCm: nil, referenceWeekStart: nil, changeCm: nil))
            XCTAssertEqual(result.signals.lifts, CutScorecardLiftSignal(state: .unknown, reason: .noReadings, commonExercises: 0,
                                                                        dropped: 0, climbed: 0, held: 0, windowStartDay: nil,
                                                                        windowEndDay: nil))
            XCTAssertNil(result.signals.rateBand.percentPerWeek)
        }
        XCTAssertNil(given.currentWeightKg)
        XCTAssertNil(given.judgedWeekStart)
        XCTAssertNil(given.evidenceStartDay)
    }

    // MARK: - R14 and R15

    func testZeroWaistMinimumMakesAnUnchangedWaistMet() {
        let zero = F.params { $0.waistMinDecreaseCm = 0 }
        func waist(_ second: Double) -> CutScorecardWaistSignal {
            evaluate(F.scenario(weights: twoWeeks, waists: [100.0, second], parameters: zero)).signals.waist
        }
        XCTAssertEqual(waist(100.0), CutScorecardWaistSignal(state: .met, reason: .shrinking, currentCm: 100.0, referenceCm: 100.0,
                                                             referenceWeekStart: "2031-01-06", changeCm: 0.0))
        XCTAssertEqual(waist(99.999).state, .met)
        // One quantum larger is still not met.
        let grown = waist(100.001)
        XCTAssertEqual(grown.state, .notMet)
        XCTAssertEqual(grown.changeCm, 0.001)
        // With lifts holding, the unchanged waist now fires rule 1.
        let result = evaluate(F.scenario(weights: twoWeeks, waists: [100.0, 100.0], lifts: F.holdingSessions(weeks: 0...2),
                                         parameters: zero))
        assertCutVerdict(result, .holdSteady, .ruleFired, rule: r1)
        // Any positive minimum, down to one quantum, keeps an unchanged waist not met.
        XCTAssertEqual(evaluate(F.scenario(weights: twoWeeks, waists: [100.0, 100.0],
                                           parameters: F.params { $0.waistMinDecreaseCm = 0.001 })).signals.waist.state, .notMet)
    }

    func testSpanWeeksCountsFromTheFirstToTheLastPointUsed() {
        func rate(_ weights: [Double?]) -> CutScorecardRate? { evaluate(F.scenario(weights: weights)).rate }
        // Consecutive weeks: one less than the points.
        XCTAssertEqual(rate([100.0, 99.2])?.spanWeeks, 1)
        XCTAssertEqual(rate([100.0, 99.2, 98.4, 97.6, 96.8])?.spanWeeks, 4)
        // Missed weeks inside the fit count towards the span and not towards the points.
        let gapped = rate([100.0, nil, 98.4, nil, 96.8])
        XCTAssertEqual(gapped?.spanWeeks, 4)
        XCTAssertEqual(gapped?.pointsUsed, 3)
        // A missed week at the start of the window does not: the window of week 6 is weeks 2 to 6, week 2
        // has no weigh-in, so the first point used is week 3 and the span is 3, not 4.
        let late = rate([100.0, nil, 98.4, 97.6, 96.8, 96.0])
        XCTAssertEqual(late?.spanWeeks, 3)
        XCTAssertEqual(late?.pointsUsed, 4)
        XCTAssertEqual(late?.firstWeekStart, F.monday(3))
        XCTAssertEqual(late?.lastWeekStart, F.monday(6))
        // The span is the distance between the two reported week starts.
        XCTAssertEqual((F.dayNumber(F.monday(6)) - F.dayNumber(F.monday(3))) / 7, 3)
    }
}
