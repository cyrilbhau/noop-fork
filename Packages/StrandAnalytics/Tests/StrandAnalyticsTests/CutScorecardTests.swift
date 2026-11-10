import XCTest
@testable import StrandAnalytics

private typealias F = CutScorecardFixture
private let r1 = CutScorecardRule.liftsHoldingWaistShrinking
private let r2 = CutScorecardRule.liftsDropping
private let r3 = CutScorecardRule.slowLoss

/// `CutScorecard.evaluate`: empty and small inputs, the three rules and their precedence, and the §13
/// fixture. Written before the implementation from `docs/personal/superapp/specs/stage-1.md` §6, §7,
/// §12.1 and §13; every expected value was derived from the algorithm in §7, not from any implementation.
///
/// The other §12.1 topics live beside this file: `CutScorecardSignalTests`, `CutScorecardSeriesTests`
/// (gaps, edits, phase, projection, week boundaries), `CutScorecardRejectionTests` and
/// `CutScorecardPropertyTests`.
///
/// Scenarios are written as one Wednesday reading per week from 2031-01-06 (a Monday), under the fixture
/// phase and the fixture parameters: slow-loss threshold 0.4 kg over 3 weeks, lift window 3 weeks, waist
/// window 2 weeks with a 0.5 cm minimum, +300 / -250 kcal.
final class CutScorecardTests: XCTestCase {

    // Four weekly weigh-ins each.
    private let slow: [Double?] = [100.0, 99.9, 99.8, 99.7]         // losses 0.1, 0.1, 0.1
    private let steady: [Double?] = [100.0, 99.2, 98.4, 97.6]       // losses 0.8, 0.8, 0.8
    private let flatWaist: [Double?] = [100.0, 100.0, 100.0, 100.0]
    private let shrinkingWaist: [Double?] = [100.0, 99.5, 99.0, 98.5]

    /// Press sessions that fall by 10 kg in each of weeks 2, 3 and 4, after holding through week 1.
    private let droppingThreeWeeks = F.pressSessions([(-1, 100), (0, 100), (1, 100), (2, 90), (3, 80), (4, 70)])

    private func evaluate(_ input: CutScorecardInput) -> CutScorecardResult {
        CutScorecard.evaluate(input)
    }

    // MARK: - Empty and small inputs

    func testEmptyInputReturnsInsufficientDataNoReadings() {
        let result = evaluate(F.make(today: "2031-01-08"))
        assertCutVerdict(result, .insufficientData, .noReadings)
        assertCutRules(result, "UUU", reasons: [.noReadings, .noReadings, .noReadings])
        XCTAssertEqual(result.signals.waist.state, .unknown)
        XCTAssertEqual(result.signals.waist.reason, .noReadings)
        XCTAssertEqual(result.signals.lifts.state, .unknown)
        XCTAssertEqual(result.signals.lifts.reason, .noReadings)
        XCTAssertEqual(result.signals.protein.state, .unknown)
        XCTAssertEqual(result.signals.protein.reason, .noReadings)
        XCTAssertEqual(result.signals.rateBand.state, .unknown)
        XCTAssertEqual(result.signals.rateBand.reason, .noReadings)
        XCTAssertNil(result.invalidInput, "an empty input is valid, not invalid")
    }

    func testEmptyInputHasNoWeeksNoRateAndNoProjection() {
        let result = evaluate(F.make(today: "2031-01-08"))
        XCTAssertEqual(result.weeks, [])
        XCTAssertNil(result.judgedWeekStart)
        XCTAssertNil(result.currentWeightKg)
        XCTAssertNil(result.currentWeightDay)
        assertCutNoRate(result, .noReadings)
        XCTAssertNil(result.evidenceStartDay)
        XCTAssertEqual(result.rejections, CutScorecardRejections(nonFinite: 0, nonPositive: 0, invalidDay: 0, future: 0))
        XCTAssertNil(result.projection.targetDay)
        XCTAssertNil(result.projection.weeksRemaining)
        XCTAssertNil(result.projection.remainingKg, "no current weight, so nothing remains to state")
        // SPEC-AMBIGUITY: §7.8 has no status for "an active phase with a target but no reading in it".
        // §7.2 says everything is unknown(.noReadings), but CutScorecardProjectionStatus has no such
        // case. Walking §7.8 in order: not 1 (the phase is active), not 2 (no judged week, so nothing is
        // overdue), not 3 (there is a target), step 4 cannot be computed, and step 5 applies because the
        // rate is nil. So `.rateUnknown`. The invalid result's `.noActivePhase` (§6.5) is not this case.
        XCTAssertEqual(result.projection.status, .rateUnknown)
        // The same walk with no target stops at step 3.
        let noTarget = evaluate(F.make(phase: F.phase(target: nil), today: "2031-01-08"))
        XCTAssertEqual(noTarget.projection.status, .noTarget)
    }

    /// Line 4a of §7.7, and variant V2.
    func testOneReadingWithoutLiftsIsNoRuleEvaluable() {
        let result = evaluate(F.scenario(weights: [100.0], waists: [100.0]))
        assertCutRules(result, "UUU", reasons: [.liftSignalUnknown, .fewerWeeksThanWindow, .fewerWeeksThanWindow])
        assertCutVerdict(result, .insufficientData, .noRuleEvaluable, unevaluated: [r1, r2, r3])
        XCTAssertEqual(result.signals.lifts.reason, .noLiftData)
        XCTAssertEqual(result.judgedWeekStart, "2031-01-06")
    }

    /// Fixture week 1. Rule 2 is settled by the one holding week; rules 1 and 3 cannot be evaluated; the
    /// answer is to change nothing, and it is not rule 1.
    func testOneReadingWithHoldingLiftsIsHoldSteadyNoChangeRuleFired() {
        let result = evaluate(F.input(week: 1))
        assertCutRules(result, "UNU", reasons: [.waistSignalUnknown, nil, .fewerWeeksThanWindow])
        assertCutVerdict(result, .holdSteady, .noChangeRuleFired, unevaluated: [r1, r3])
        XCTAssertEqual(result.signals.lifts.state, .met)
        XCTAssertEqual(result.signals.waist.reason, .noEarlierWaist)
    }

    func testOneReadingRateIsSingleReading() {
        let result = evaluate(F.scenario(weights: [100.0]))
        assertCutNoRate(result, .singleReading)
        XCTAssertEqual(result.signals.rateBand.state, .unknown)
        XCTAssertEqual(result.signals.rateBand.reason, .rateUnknown)
        XCTAssertEqual(result.currentWeightKg, 100.0)
        XCTAssertEqual(result.currentWeightDay, "2031-01-08")
        XCTAssertEqual(result.weeks, [CutScorecardWeek(weekStart: "2031-01-06", weightKg: 100.0,
                                                       weightDay: "2031-01-08", waistCm: nil, waistDay: nil,
                                                       inPhase: true, weeklyLossKg: nil)])
    }

    /// The representative is the latest reading: not the first, the lowest, the highest or the mean.
    func testTwoReadingsInSameWeekUseTheLatest() {
        // Later reading is the lower one (the fixture's week 3): first = max = 98.9, mean = 98.65.
        let laterLower = [F.weight("2031-01-20", 98.9), F.weight("2031-01-22", 98.4)]
        // Later reading is the higher one: first = min = 98.0, mean = 98.2.
        let laterHigher = [F.weight("2031-01-20", 98.0), F.weight("2031-01-22", 98.4)]
        for (label, readings) in [("later lower", laterLower), ("later higher", laterHigher),
                                  ("later lower, reversed input", Array(laterLower.reversed())),
                                  ("later higher, reversed input", Array(laterHigher.reversed()))] {
            let result = evaluate(F.make(weights: [F.weight("2031-01-15", 99.2)] + readings,
                                         waists: readings.map { F.waist($0.day, $0.value) },
                                         today: "2031-01-22"))
            let week = result.weeks.last
            XCTAssertEqual(week?.weekStart, "2031-01-20", label)
            XCTAssertEqual(week?.weightKg, 98.4, label)
            XCTAssertEqual(week?.weightDay, "2031-01-22", label)
            XCTAssertEqual(week?.waistCm, 98.4, "\(label): waist follows the same rule independently")
            XCTAssertEqual(week?.waistDay, "2031-01-22", label)
            XCTAssertEqual(week?.weeklyLossKg, 0.8, "\(label): the loss uses the representative")
            XCTAssertEqual(result.currentWeightKg, 98.4, label)
            XCTAssertEqual(result.currentWeightDay, "2031-01-22", label)
            XCTAssertEqual(result.weeks.count, 2, label)
        }
    }

    func testTwoReadingsOnSameDayUseTheGreatestTakenAt() {
        let morning = F.weight("2031-01-08", 100.4, hour: 7)
        let evening = F.weight("2031-01-08", 99.6, hour: 21)
        for readings in [[morning, evening], [evening, morning]] {
            let result = evaluate(F.make(weights: readings, today: "2031-01-08"))
            XCTAssertEqual(result.weeks.last?.weightKg, 99.6)
            XCTAssertEqual(result.currentWeightKg, 99.6)
        }
        // The later instant wins even when an earlier day-mate is entered with a later-sorting value.
        let lowMorning = F.weight("2031-01-08", 99.0, hour: 7)
        let highEvening = F.weight("2031-01-08", 101.0, hour: 21)
        let result = evaluate(F.make(weights: [highEvening, lowMorning], today: "2031-01-08"))
        XCTAssertEqual(result.currentWeightKg, 101.0)
    }

    /// The last key of §7.1's `(day, takenAt, value)` order: the parity plan (§12.7) names this tie.
    func testReadingsSharingDayAndInstantUseTheGreatestValue() {
        let a = CutScorecardReading(day: "2031-01-08", takenAt: 500, value: 99.1)
        let b = CutScorecardReading(day: "2031-01-08", takenAt: 500, value: 99.3)
        for readings in [[a, b], [b, a]] {
            let result = evaluate(F.make(weights: readings, waists: readings, today: "2031-01-08"))
            XCTAssertEqual(result.weeks.last?.weightKg, 99.3)
            XCTAssertEqual(result.weeks.last?.waistCm, 99.3)
            XCTAssertEqual(result.currentWeightKg, 99.3)
        }
    }

    func testTwoReadingsExactlyAWeekApartGiveEndpointRate() throws {
        let result = evaluate(F.scenario(weights: [100.0, 99.2]))
        let rate = try XCTUnwrap(result.rate)
        XCTAssertEqual(rate.lossKgPerWeek, 0.8)
        XCTAssertEqual(rate.percentPerWeek, 0.803, "100 x 0.8 / 99.6 = 0.8032")
        XCTAssertEqual(rate.referenceWeightKg, 99.6, accuracy: 1e-9)
        XCTAssertEqual(rate.pointsUsed, 2)
        XCTAssertEqual(rate.spanWeeks, 1)
        XCTAssertEqual(rate.firstWeekStart, "2031-01-06")
        XCTAssertEqual(rate.lastWeekStart, "2031-01-13")
        XCTAssertNil(result.rateUnavailable)
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, 0.8])
    }

    /// Three weigh-ins give two weekly losses. Rule 3 needs three, so it is unknown; rules 1 and 2 still
    /// evaluate and rule 1 decides.
    func testFewerWeeksThanSlowLossWindowLeavesRuleThreeUnknownAndOthersEvaluate() {
        let result = evaluate(F.scenario(weights: [100.0, 99.9, 99.8], waists: [100.0, 99.5, 99.0],
                                         lifts: F.holdingSessions(weeks: -1...3)))
        assertCutRules(result, "FNU", reasons: [nil, nil, .fewerWeeksThanWindow])
        XCTAssertEqual(result.rule(2)?.consecutiveWeeks, 2)
        XCTAssertEqual(result.rule(2)?.requiredWeeks, 3)
        assertCutVerdict(result, .holdSteady, .ruleFired, rule: r1)
    }

    /// Two weigh-ins, lifts dropping in both weeks. Rule 2 needs three weeks inside the phase, so it is
    /// unknown; rule 1 is settled by the dropping week and rule 3 by a 0.8 kg loss. Line 4b names rule 2.
    func testFewerWeeksThanLiftWindowLeavesRuleTwoUnknownAndOthersEvaluate() {
        let result = evaluate(F.scenario(weights: [100.0, 99.2], waists: [100.0, 99.5],
                                         lifts: F.pressSessions([(-1, 100), (0, 90), (1, 80), (2, 70)])))
        assertCutRules(result, "NUN", reasons: [nil, .fewerWeeksThanWindow, nil])
        XCTAssertEqual(result.rule(1)?.consecutiveWeeks, 2)
        XCTAssertEqual(result.rule(1)?.requiredWeeks, 3)
        assertCutVerdict(result, .holdSteady, .noChangeRuleFired, unevaluated: [r2])
    }

    // MARK: - Rules and precedence

    /// Fixture week 4: line 1 of §7.7 with nothing overridden.
    func testSteadyLossInsideBandIsHoldSteadyByRuleOne() {
        let result = evaluate(F.input(week: 4))
        assertCutRules(result, "FNN")
        assertCutVerdict(result, .holdSteady, .ruleFired, rule: r1)
        assertCutRate(result, loss: 0.8, percent: 0.81)
        XCTAssertEqual(result.signals.rateBand.state, .met)
        XCTAssertEqual(result.signals.rateBand.reason, .withinBand)
        XCTAssertEqual(result.rule(0), CutScorecardRuleEvaluation(rule: r1, state: .fired, unknownReason: nil,
                                                                   consecutiveWeeks: 1, requiredWeeks: 1))
    }

    /// Line 3b. Four weigh-ins in consecutive weeks give exactly the three slow weeks the rule needs.
    func testSlowLossForExactlyTheWindowIsReduceCarbs() {
        let result = evaluate(F.scenario(weights: slow, waists: flatWaist,
                                         lifts: F.holdingSessions(weeks: -1...4)))
        assertCutRules(result, "NNF")
        XCTAssertEqual(result.rule(2), CutScorecardRuleEvaluation(rule: r3, state: .fired, unknownReason: nil,
                                                                   consecutiveWeeks: 3, requiredWeeks: 3))
        assertCutVerdict(result, .reduceCarbs, .ruleFired, rule: r3, kcal: -250)
    }

    /// Two slow weeks behind one ordinary week: the run is one short, and the ordinary week settles it.
    func testSlowLossOneWeekShortOfTheWindowIsNotReduceCarbs() {
        let result = evaluate(F.scenario(weights: [100.0, 99.5, 99.4, 99.3], waists: flatWaist,
                                         lifts: F.holdingSessions(weeks: -1...4)))
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, 0.5, 0.1, 0.1])
        assertCutRules(result, "NNN")
        XCTAssertEqual(result.rule(2)?.consecutiveWeeks, 2)
        assertCutVerdict(result, .holdSteady, .noChangeRuleFired)
        XCTAssertNotEqual(result.verdict.kind, .reduceCarbs)
    }

    /// The comparison is `loss >= threshold` settles the rule as not fired. The judged week is the only
    /// week at the boundary; the two before it are plainly slow.
    func testSlowLossAtExactlyTheThresholdDoesNotCount() {
        func run(_ lastKg: Double) -> CutScorecardResult {
            evaluate(F.scenario(weights: [100.0, 99.9, 99.8, lastKg], waists: flatWaist,
                                lifts: F.holdingSessions(weeks: -1...4)))
        }
        let atThreshold = run(99.4)             // loss 0.400
        XCTAssertEqual(atThreshold.weeks.last?.weeklyLossKg, 0.4)
        assertCutRules(atThreshold, "NNN", "loss 0.400")
        XCTAssertEqual(atThreshold.rule(2)?.consecutiveWeeks, 0)
        assertCutVerdict(atThreshold, .holdSteady, .noChangeRuleFired, "loss 0.400")

        let oneQuantumUnder = run(99.401)       // loss 0.399
        XCTAssertEqual(oneQuantumUnder.weeks.last?.weeklyLossKg, 0.399)
        assertCutRules(oneQuantumUnder, "NNF", "loss 0.399")
        assertCutVerdict(oneQuantumUnder, .reduceCarbs, .ruleFired, rule: r3, kcal: -250, "loss 0.399")

        let oneQuantumOver = run(99.399)        // loss 0.401
        XCTAssertEqual(oneQuantumOver.weeks.last?.weeklyLossKg, 0.401)
        assertCutRules(oneQuantumOver, "NNN", "loss 0.401")
        assertCutVerdict(oneQuantumOver, .holdSteady, .noChangeRuleFired, "loss 0.401")
    }

    /// The comparison is on quantized values (§7.1 step 2): a loss a hair under the threshold in Double
    /// arithmetic that quantizes onto it does not count as slow.
    func testSlowLossComparisonUsesQuantizedLoss() {
        // 99.8 - 99.4002 = 0.3998, which quantizes to 0.400.
        let result = evaluate(F.scenario(weights: [100.0, 99.9, 99.8, 99.4002], waists: flatWaist,
                                         lifts: F.holdingSessions(weeks: -1...4)))
        XCTAssertEqual(result.weeks.last?.weeklyLossKg, 0.4)
        assertCutRules(result, "NNN")
    }

    /// Line 1 beats line 3b: the recomposition week.
    func testSlowLossWithShrinkingWaistAndHoldingLiftsIsHoldSteadyNeverReduceCarbs() {
        let result = evaluate(F.scenario(weights: slow, waists: shrinkingWaist,
                                         lifts: F.holdingSessions(weeks: -1...4)))
        assertCutRules(result, "FNF")
        XCTAssertEqual(result.verdict.kind, .holdSteady)
        XCTAssertEqual(result.verdict.reason, .ruleFired)
        XCTAssertEqual(result.verdict.rule, r1)
        XCTAssertNil(result.verdict.calorieChangeKcal)
        XCTAssertNotEqual(result.verdict.kind, .reduceCarbs)
    }

    func testRecompositionWeekRecordsSlowLossAsOverridden() {
        let result = evaluate(F.scenario(weights: slow, waists: shrinkingWaist,
                                         lifts: F.holdingSessions(weeks: -1...4)))
        assertCutVerdict(result, .holdSteady, .ruleFired, rule: r1, overridden: [r3])
        XCTAssertEqual(result.rule(2)?.state, .fired, "rule 3 is still reported as fired in `rules`")
    }

    func testSlowLossWithShrinkingWaistAndClimbingLiftsIsHoldSteady() {
        let climbing = F.pressSessions([(-1, 60), (0, 62.5), (1, 65), (2, 67.5), (3, 70), (4, 72.5)])
        let result = evaluate(F.scenario(weights: slow, waists: shrinkingWaist, lifts: climbing))
        XCTAssertEqual(result.signals.lifts.state, .met)
        XCTAssertEqual(result.signals.lifts.reason, .holding)
        XCTAssertEqual(result.signals.lifts.climbed, 1)
        assertCutRules(result, "FNF")
        assertCutVerdict(result, .holdSteady, .ruleFired, rule: r1, overridden: [r3])
    }

    /// Line 2 with nothing overridden: weeks 2, 3 and 4 drop, the loss is ordinary.
    func testLiftsDroppingForTheWindowIsAddCalories() {
        let result = evaluate(F.scenario(weights: steady, waists: shrinkingWaist, lifts: droppingThreeWeeks))
        assertCutRules(result, "NFN")
        XCTAssertEqual(result.rule(1), CutScorecardRuleEvaluation(rule: r2, state: .fired, unknownReason: nil,
                                                                   consecutiveWeeks: 3, requiredWeeks: 3))
        assertCutVerdict(result, .addCalories, .ruleFired, rule: r2, kcal: 300)
    }

    /// Weeks 3 and 4 drop; week 2 held, which settles rule 2 as not fired.
    func testLiftsDroppingOneWeekShortOfTheWindowIsNotAddCalories() {
        let twoWeeks = F.pressSessions([(-1, 100), (0, 100), (1, 100), (2, 100), (3, 90), (4, 80)])
        let result = evaluate(F.scenario(weights: steady, waists: shrinkingWaist, lifts: twoWeeks))
        assertCutRules(result, "NNN")
        XCTAssertEqual(result.rule(1)?.consecutiveWeeks, 2)
        assertCutVerdict(result, .holdSteady, .noChangeRuleFired)
        XCTAssertNotEqual(result.verdict.kind, .addCalories)
    }

    /// Line 2 beats line 3: opposite advice, and adding wins.
    func testLiftsDroppingAndSlowLossTogetherIsAddCaloriesWithSlowLossOverridden() {
        let result = evaluate(F.scenario(weights: slow, waists: shrinkingWaist, lifts: droppingThreeWeeks))
        assertCutRules(result, "NFF")
        assertCutVerdict(result, .addCalories, .ruleFired, rule: r2, kcal: 300, overridden: [r3])
    }

    func testOneHoldingWeekInsideTheLiftWindowSettlesRuleTwoAsNotFired() {
        // Week 2 drops, week 3 holds, week 4 drops.
        let holdInTheMiddle = F.pressSessions([(0, 100), (1, 100), (2, 90), (3, 90), (4, 80)])
        let result = evaluate(F.scenario(weights: steady, waists: shrinkingWaist, lifts: holdInTheMiddle))
        XCTAssertEqual(result.rule(1)?.state, .notFired)
        XCTAssertNil(result.rule(1)?.unknownReason)
        XCTAssertEqual(result.rule(1)?.consecutiveWeeks, 1)

        // A holding week settles it even when another week of the window has no weigh-in at all: week 2
        // holds, week 3 was missed, week 4 drops. "Unknown" would be wrong; the run is already broken.
        let lifts = F.pressSessions([(0, 100), (1, 100), (2, 100), (3, 90), (4, 80)])
        let missed = evaluate(F.scenario(weights: [100.0, 99.2, nil, 97.6], waists: shrinkingWaist, lifts: lifts))
        XCTAssertEqual(missed.rule(1)?.state, .notFired)
        XCTAssertNil(missed.rule(1)?.unknownReason)
    }

    /// Line 3a. Fault F4: were an unknown lift status read as dropping, this would be `addCalories`.
    func testLiftSignalUnknownWithSlowLossAndShrinkingWaistWithholdsVerdictAndNamesRuleOne() {
        let result = evaluate(F.scenario(weights: slow, waists: shrinkingWaist))
        assertCutRules(result, "UUF", reasons: [.liftSignalUnknown, .liftSignalUnknown, nil])
        assertCutVerdict(result, .insufficientData, .recompositionCheckIncomplete, unevaluated: [r1, r2])
        XCTAssertEqual(result.verdict.unevaluatedRules.first, r1)
    }

    /// Line 3b with rule 2 unknown: the flat waist settles rule 1, so the verdict stands and names rule 2.
    func testLiftSignalUnknownWithSlowLossAndFlatWaistIsReduceCarbsNamingRuleTwo() {
        let result = evaluate(F.scenario(weights: slow, waists: flatWaist))
        assertCutRules(result, "NUF", reasons: [nil, .liftSignalUnknown, nil])
        assertCutVerdict(result, .reduceCarbs, .ruleFired, rule: r3, kcal: -250, unevaluated: [r2])
    }

    /// Line 4b with two unknown rules.
    func testLiftSignalUnknownWithNoRuleFiredIsHoldSteadyNamingUnevaluatedRules() {
        let result = evaluate(F.scenario(weights: steady, waists: shrinkingWaist))
        assertCutRules(result, "UUN", reasons: [.liftSignalUnknown, .liftSignalUnknown, nil])
        assertCutVerdict(result, .holdSteady, .noChangeRuleFired, unevaluated: [r1, r2])
    }

    /// Fault F3: were an unknown lift status read as holding, every case here would fire rule 1. Each
    /// kind of unknown is tried against a slow scale and a shrinking waist, where rule 1 is most tempting.
    func testLiftSignalUnknownNeverYieldsRuleOne() {
        let cases: [(String, [CutScorecardLiftObservation], CutScorecardLiftReason)] = [
            ("no lift data", [], .noLiftData),
            ("no sessions this week", F.session(week: 3, [(F.pressName, 60)]), .noSessionsThisWeek),
            ("no sessions the week before", F.session(week: 4, [(F.pressName, 60)]), .noSessionsPriorWeek),
            ("no common exercise", F.session(week: 3, [(F.pressName, 60)]) + F.session(week: 4, [(F.rowName, 50)]),
             .noCommonExercises),
        ]
        for (label, lifts, reason) in cases {
            let result = evaluate(F.scenario(weights: slow, waists: shrinkingWaist, lifts: lifts))
            XCTAssertEqual(result.signals.lifts.state, .unknown, label)
            XCTAssertEqual(result.signals.lifts.reason, reason, label)
            XCTAssertEqual(result.signals.waist.state, .met, label)
            XCTAssertEqual(result.rule(0)?.state, .unknown, label)
            XCTAssertEqual(result.rule(0)?.unknownReason, .liftSignalUnknown, label)
            XCTAssertEqual(result.rule(0)?.consecutiveWeeks, 0, label)
            XCTAssertNotEqual(result.verdict.rule, r1, label)
            assertCutVerdict(result, .insufficientData, .recompositionCheckIncomplete, unevaluated: [r1, r2], label)
        }
    }

    /// Line 3a with rule 2 settled: only rule 1 is named.
    func testWaistUnknownWithSlowLossAndHoldingLiftsWithholdsVerdict() {
        let result = evaluate(F.scenario(weights: slow, waists: [100.0, 99.5, 99.0, nil],
                                         lifts: F.holdingSessions(weeks: -1...4)))
        XCTAssertEqual(result.signals.waist.reason, .noWaistThisWeek)
        assertCutRules(result, "UNF", reasons: [.waistSignalUnknown, nil, nil])
        assertCutVerdict(result, .insufficientData, .recompositionCheckIncomplete, unevaluated: [r1])
    }

    /// When both halves of rule 1 are unknown the reason names the lift status (§7.6).
    func testRuleOneUnknownReasonNamesLiftsBeforeWaist() {
        let result = evaluate(F.scenario(weights: slow, waists: [100.0, 99.5, 99.0, nil]))
        XCTAssertEqual(result.rule(0)?.state, .unknown)
        XCTAssertEqual(result.rule(0)?.unknownReason, .liftSignalUnknown)
    }

    /// One known half is enough to settle rule 1 as not fired, whatever the other half is.
    func testRuleOneIsNotFiredWhenEitherHalfIsKnownAgainstIt() {
        // Lifts dropping, waist unknown.
        let dropping = evaluate(F.scenario(weights: steady, waists: [100.0, 99.5, 99.0, nil],
                                           lifts: droppingThreeWeeks))
        XCTAssertEqual(dropping.signals.waist.state, .unknown)
        XCTAssertEqual(dropping.rule(0)?.state, .notFired)
        // Waist flat, lifts unknown.
        let flat = evaluate(F.scenario(weights: steady, waists: flatWaist))
        XCTAssertEqual(flat.signals.lifts.state, .unknown)
        XCTAssertEqual(flat.rule(0)?.state, .notFired)
    }

    /// Line 4b with nothing unknown. `rule` is nil: this is not rule 1, and the screen must not say so.
    func testNoRuleFiredIsHoldSteadyWithNilRule() {
        let result = evaluate(F.scenario(weights: steady, waists: flatWaist,
                                         lifts: F.holdingSessions(weeks: -1...4)))
        assertCutRules(result, "NNN", reasons: [nil, nil, nil])
        assertCutVerdict(result, .holdSteady, .noChangeRuleFired)
        XCTAssertNil(result.verdict.rule)
        XCTAssertNil(result.verdict.calorieChangeKcal)
    }

    func testCalorieAmountsComeFromParameters() {
        let custom = F.params { $0.addCaloriesKcal = 425; $0.reduceCarbsKcal = 175 }
        let add = evaluate(F.scenario(weights: steady, waists: shrinkingWaist, lifts: droppingThreeWeeks,
                                      parameters: custom))
        assertCutVerdict(add, .addCalories, .ruleFired, rule: r2, kcal: 425)
        let reduce = evaluate(F.scenario(weights: slow, waists: flatWaist,
                                         lifts: F.holdingSessions(weeks: -1...4), parameters: custom))
        assertCutVerdict(reduce, .reduceCarbs, .ruleFired, rule: r3, kcal: -175)

        // The generic defaults are 100 and 100; the fixture's are 300 and 250.
        let generic = F.params { $0.addCaloriesKcal = 100; $0.reduceCarbsKcal = 100 }
        XCTAssertEqual(evaluate(F.scenario(weights: steady, waists: shrinkingWaist, lifts: droppingThreeWeeks,
                                           parameters: generic)).verdict.calorieChangeKcal, 100)
        XCTAssertEqual(evaluate(F.scenario(weights: slow, waists: flatWaist,
                                           lifts: F.holdingSessions(weeks: -1...4),
                                           parameters: generic)).verdict.calorieChangeKcal, -100)
        // Zero is a valid amount (§6.5 rejects only negatives) and is reported, not dropped to nil.
        let zero = F.params { $0.addCaloriesKcal = 0; $0.reduceCarbsKcal = 0 }
        XCTAssertEqual(evaluate(F.scenario(weights: steady, waists: shrinkingWaist, lifts: droppingThreeWeeks,
                                           parameters: zero)).verdict.calorieChangeKcal, 0)
    }

    /// One sub-case per parameter: the same input evaluated with the fixture value and with one field
    /// changed, asserting the outcome that field governs on both sides. Fault F8: a threshold replaced
    /// by a literal passes one side and fails the other.
    func testChangingEveryParameterChangesTheOutcomeItGoverns() {
        func run(_ input: CutScorecardInput, _ change: (inout CutScorecardParameters) -> Void) -> CutScorecardResult {
            evaluate(CutScorecardInput(weights: input.weights, waists: input.waists, lifts: input.lifts,
                                       proteinDays: input.proteinDays, phase: input.phase,
                                       parameters: F.params(change), today: input.today))
        }

        // rateWindowWeeks: fixture week 6. Window 4 fits weeks 2-6 (0.45); window 2 fits weeks 4-6 (0.1).
        assertCutRate(run(F.input(week: 6)) { _ in }, loss: 0.45, percent: 0.459, "rateWindowWeeks 4")
        let narrow = run(F.input(week: 6)) { $0.rateWindowWeeks = 2 }
        assertCutRate(narrow, loss: 0.1, percent: 0.103, "rateWindowWeeks 2")
        XCTAssertEqual(narrow.rate?.pointsUsed, 3)

        // waistWindowWeeks: fixture week 8. Window 2 reaches week 6 (97.5); window 4 reaches week 4 (98.5).
        XCTAssertEqual(run(F.input(week: 8)) { _ in }.signals.waist.changeCm, -0.5)
        let wide = run(F.input(week: 8)) { $0.waistWindowWeeks = 4 }
        XCTAssertEqual(wide.signals.waist.changeCm, -1.5)
        XCTAssertEqual(wide.signals.waist.referenceWeekStart, F.monday(4))

        // waistMinDecreaseCm: fixture week 8 shrank 0.5.
        XCTAssertEqual(run(F.input(week: 8)) { _ in }.signals.waist.state, .met)
        XCTAssertEqual(run(F.input(week: 8)) { $0.waistMinDecreaseCm = 0.6 }.signals.waist.state, .notMet)

        // liftDropTolerancePercent: fixture week 17, 62.5 -> 57.5 and 52.5 -> 47.5 (8 % and 9.5 %).
        XCTAssertEqual(run(F.input(week: 17)) { _ in }.signals.lifts.dropped, 2)
        let tolerant = run(F.input(week: 17)) { $0.liftDropTolerancePercent = 10 }
        XCTAssertEqual(tolerant.signals.lifts.dropped, 0)
        XCTAssertEqual(tolerant.signals.lifts.state, .met)

        // liftDropShare: one of two exercises dropped.
        let oneOfTwo = F.scenario(weights: [100.0, 99.2], lifts:
            F.session(week: 1, [(F.pressName, 100), (F.rowName, 50)]) +
            F.session(week: 2, [(F.pressName, 90), (F.rowName, 50)]))
        XCTAssertEqual(run(oneOfTwo) { _ in }.signals.lifts.reason, .dropping)
        XCTAssertEqual(run(oneOfTwo) { $0.liftDropShare = 0.75 }.signals.lifts.reason, .holding)

        // liftDropConsecutiveWeeks: fixture week 18 has two dropping weeks behind it.
        XCTAssertEqual(run(F.input(week: 18)) { _ in }.rule(1)?.state, .unknown)
        let twoWeeks = run(F.input(week: 18)) { $0.liftDropConsecutiveWeeks = 2 }
        XCTAssertEqual(twoWeeks.rule(1)?.state, .fired)
        XCTAssertEqual(twoWeeks.rule(1)?.requiredWeeks, 2)
        assertCutVerdict(twoWeeks, .addCalories, .ruleFired, rule: r2, kcal: 300, overridden: [r3])

        // addCaloriesKcal: fixture week 19.
        XCTAssertEqual(run(F.input(week: 19)) { _ in }.verdict.calorieChangeKcal, 300)
        XCTAssertEqual(run(F.input(week: 19)) { $0.addCaloriesKcal = 301 }.verdict.calorieChangeKcal, 301)

        // slowLossThresholdKgPerWeek: fixture week 4 lost 0.8 in each of three weeks.
        XCTAssertEqual(run(F.input(week: 4)) { _ in }.rule(2)?.state, .notFired)
        let highThreshold = run(F.input(week: 4)) { $0.slowLossThresholdKgPerWeek = 0.9 }
        XCTAssertEqual(highThreshold.rule(2)?.state, .fired)
        assertCutVerdict(highThreshold, .holdSteady, .ruleFired, rule: r1, overridden: [r3])

        // slowLossConsecutiveWeeks: fixture week 6 has two slow weeks behind an ordinary one.
        XCTAssertEqual(run(F.input(week: 6)) { _ in }.rule(2)?.state, .notFired)
        let shortRun = run(F.input(week: 6)) { $0.slowLossConsecutiveWeeks = 2 }
        XCTAssertEqual(shortRun.rule(2)?.state, .fired)
        XCTAssertEqual(shortRun.rule(2)?.requiredWeeks, 2)

        // reduceCarbsKcal: fixture week 9.
        XCTAssertEqual(run(F.input(week: 9)) { _ in }.verdict.calorieChangeKcal, -250)
        XCTAssertEqual(run(F.input(week: 9)) { $0.reduceCarbsKcal = 251 }.verdict.calorieChangeKcal, -251)

        // proteinFloorGrams: fixture week 5 logged 120, 80, 80, 120, 80, 80, 120.
        XCTAssertEqual(run(F.input(week: 5)) { _ in }.signals.protein.reason, .floorMissed)
        let lowFloor = run(F.input(week: 5)) { $0.proteinFloorGrams = 80 }
        XCTAssertEqual(lowFloor.signals.protein.reason, .floorMet)
        XCTAssertEqual(lowFloor.signals.protein.floorGrams, 80)
        XCTAssertEqual(run(F.input(week: 5)) { $0.proteinFloorGrams = nil }.signals.protein.reason, .noFloorConfigured)

        // proteinMinDaysPerWeek: fixture week 2 reached the floor on 6 of 7 logged days.
        XCTAssertEqual(run(F.input(week: 2)) { _ in }.signals.protein.reason, .floorMet)
        let everyDay = run(F.input(week: 2)) { $0.proteinMinDaysPerWeek = 7 }
        XCTAssertEqual(everyDay.signals.protein.reason, .floorMissed)
        XCTAssertEqual(everyDay.signals.protein.requiredDays, 7)

        // maxWeighInAgeWeeks: fixture week 10 judges a weigh-in one week old.
        assertCutVerdict(run(F.input(week: 10)) { _ in }, .reduceCarbs, .ruleFired, rule: r3, kcal: -250)
        assertCutVerdict(run(F.input(week: 10)) { $0.maxWeighInAgeWeeks = 0 }, .insufficientData, .weighInOverdue)
        // ...and two weeks old in week 11 once that week's reading is taken away.
        let twoWeeksOld = F.input(today: F.weighInDay(11), weights: F.allWeights.filter { $0.day != F.weighInDay(11) })
        assertCutVerdict(run(twoWeeksOld) { _ in }, .insufficientData, .weighInOverdue)
        assertCutVerdict(run(twoWeeksOld) { $0.maxWeighInAgeWeeks = 2 }, .reduceCarbs, .ruleFired, rule: r3, kcal: -250)

        // maxProjectionWeeks: fixture week 8 is 32 weeks from the target.
        assertCutProjection(run(F.input(week: 8)) { _ in }, .projected, targetDay: "2031-10-08")
        assertCutProjection(run(F.input(week: 8)) { $0.maxProjectionWeeks = 31 }, .beyondHorizon)

        // targetToleranceKg: fixture week 19 is 0.5 kg from the target.
        assertCutProjection(run(F.input(week: 19)) { _ in }, .projected, targetDay: "2031-06-18")
        assertCutProjection(run(F.input(week: 19)) { $0.targetToleranceKg = 0.5 }, .targetReached)
    }

    // MARK: - consecutiveWeeks and unknown reasons

    func testConsecutiveWeeksStopsAtTheFirstWeekThatBreaksTheRun() {
        // Losses 0.1, 0.8, 0.1, 0.1: the run counted back from the judged week is 2, not 3.
        let result = evaluate(F.scenario(weights: [100.0, 99.9, 99.1, 99.0, 98.9]))
        XCTAssertEqual(result.rule(2)?.state, .notFired)
        XCTAssertEqual(result.rule(2)?.consecutiveWeeks, 2)
        // Rule 1 reports 1 when it fired and 0 otherwise; its required count is always 1.
        XCTAssertEqual(evaluate(F.input(week: 4)).rule(0)?.consecutiveWeeks, 1)
        XCTAssertEqual(evaluate(F.input(week: 9)).rule(0)?.consecutiveWeeks, 0)
        XCTAssertEqual(evaluate(F.input(week: 9)).rule(0)?.requiredWeeks, 1)
    }

    func testConsecutiveWeeksKeepsCountingPastTheRequiredWindow() {
        // SPEC-AMBIGUITY: §7.6 says the count "stops at the first week where it is false or unknown" and
        // names no upper bound, so a run longer than the window is reported in full: fixture week 9 has
        // five slow weeks (5 to 9) against a window of 3, and week 19 has seven. §7.9 implies the
        // opposite, since an uncapped count can be changed by a reading dated before `evidenceStartDay`.
        // The literal §7.6 reading is asserted here; the property test keeps its inputs where the two
        // readings agree.
        let week9 = evaluate(F.input(week: 9))
        XCTAssertEqual(week9.rule(2)?.state, .fired)
        XCTAssertEqual(week9.rule(2)?.consecutiveWeeks, 5)
        XCTAssertEqual(week9.rule(2)?.requiredWeeks, 3)
        XCTAssertEqual(evaluate(F.input(week: 19)).rule(2)?.consecutiveWeeks, 7)
        XCTAssertEqual(evaluate(F.input(week: 19)).rule(1)?.consecutiveWeeks, 3)
    }

    /// Rule 2's unknown reasons in the order §7.6 tests them.
    func testRuleTwoUnknownReasonPrecedence() {
        let dropping = F.pressSessions([(-1, 100), (0, 90), (1, 80), (2, 70), (3, 60), (4, 50)])
        // The window (weeks 0 to 2) starts before the phase AND week 1 has no weigh-in:
        // fewerWeeksThanWindow wins over missedWeighIn.
        let short = evaluate(F.scenario(weights: [nil, 99.2], lifts: dropping.filter { $0.day <= F.weighInDay(2) }))
        XCTAssertEqual(short.rule(1)?.state, .unknown)
        XCTAssertEqual(short.rule(1)?.unknownReason, .fewerWeeksThanWindow)
        // All three weeks are in the phase, week 3 has no weigh-in, weeks 2 and 4 drop: missedWeighIn.
        let missed = evaluate(F.scenario(weights: [100.0, 99.2, nil, 97.6], lifts: dropping))
        XCTAssertEqual(missed.rule(1)?.state, .unknown)
        XCTAssertEqual(missed.rule(1)?.unknownReason, .missedWeighIn)
        XCTAssertEqual(missed.rule(1)?.consecutiveWeeks, 1)
        // All three weeks weighed and none holding: week 2 drops, and with no session on the Monday of
        // week 3 the lift status of weeks 3 and 4 is unknown: liftSignalUnknown.
        let gap = F.pressSessions([(0, 100), (1, 90), (2, 80), (4, 50)])
        let unknown = evaluate(F.scenario(weights: steady, lifts: gap))
        XCTAssertEqual(unknown.rule(1)?.state, .unknown)
        XCTAssertEqual(unknown.rule(1)?.unknownReason, .liftSignalUnknown)
    }

    /// Rule 3's unknown reasons in the order §7.6 tests them.
    func testRuleThreeUnknownReasonPrecedence() {
        // Three weigh-ins: `J - 3` is before the phase.
        let short = evaluate(F.scenario(weights: [100.0, 99.9, 99.8]))
        XCTAssertEqual(short.rule(2)?.unknownReason, .fewerWeeksThanWindow)
        // Same, with a missed week inside the window as well: still fewerWeeksThanWindow.
        let shortAndMissed = evaluate(F.scenario(weights: [100.0, nil, 99.8]))
        XCTAssertEqual(shortAndMissed.rule(2)?.unknownReason, .fewerWeeksThanWindow)
        // Five weeks in the phase, week 3 missed: missedWeighIn.
        let missed = evaluate(F.scenario(weights: [100.0, 99.9, nil, 99.7, 99.6]))
        XCTAssertEqual(missed.rule(2)?.state, .unknown)
        XCTAssertEqual(missed.rule(2)?.unknownReason, .missedWeighIn)
        // Exactly N + 1 weigh-ins: `J - 3` is week 1, the first week of the phase, and the rule evaluates.
        let exact = evaluate(F.scenario(weights: [100.0, 99.9, 99.8, 99.7]))
        XCTAssertEqual(exact.rule(2)?.state, .fired)
    }

    // MARK: - Fixture (§13)

    /// All 22 weeks of §13.3, every column, with `today` set to each weigh-in day and only the data up
    /// to that day. Fault F14 (rate window off by one) fails on the rate columns from week 6 on.
    func testFixtureVerdictSequence() throws {
        XCTAssertEqual(F.expectedWeeks.count, 22)
        var kinds: [CutScorecardVerdictKind] = []
        for expected in F.expectedWeeks {
            let label = "week \(expected.week)"
            let result = evaluate(F.input(today: expected.day))
            kinds.append(result.verdict.kind)

            XCTAssertNil(result.invalidInput, label)
            XCTAssertEqual(result.rejections, CutScorecardRejections(nonFinite: 0, nonPositive: 0, invalidDay: 0, future: 0), label)
            XCTAssertEqual(result.weeks.count, expected.week, label)
            XCTAssertEqual(result.weeks.first?.weekStart, F.weekOneMonday, label)
            let week = try XCTUnwrap(result.weeks.last, label)
            XCTAssertEqual(week.weekStart, F.monday(expected.week), label)
            XCTAssertEqual(week.weightKg, expected.weightKg, "\(label) weight")
            XCTAssertEqual(week.weightDay, expected.weightKg == nil ? nil : expected.day, "\(label) weightDay")
            XCTAssertEqual(week.waistCm, expected.waistCm, "\(label) waist")
            XCTAssertEqual(week.weeklyLossKg, expected.weeklyLossKg, "\(label) weekly loss")
            XCTAssertTrue(week.inPhase, label)

            if let rate = expected.rate {
                assertCutRate(result, loss: rate.loss, percent: rate.percent, label)
            } else {
                assertCutNoRate(result, try XCTUnwrap(expected.rateUnavailable), label)
            }
            XCTAssertEqual(result.signals.waist.state, expected.waistState, "\(label) waist signal")
            XCTAssertEqual(result.signals.waist.changeCm, expected.waistChangeCm, "\(label) waist change")
            XCTAssertEqual(result.signals.lifts.state, expected.liftState, "\(label) lift signal")
            XCTAssertEqual(result.signals.lifts.reason, expected.liftReason, "\(label) lift reason")
            XCTAssertEqual(result.signals.protein.reason, expected.proteinReason, "\(label) protein")
            XCTAssertEqual(result.signals.rateBand.reason, expected.rateBandReason, "\(label) rate band")
            assertCutRules(result, String(expected.ruleStates.map { $0 == .fired ? "F" : ($0 == .notFired ? "N" : "U") }), label)
            XCTAssertEqual(result.verdict, expected.verdict, "\(label) verdict")
            assertCutProjection(result, expected.projection, targetDay: expected.targetDay, label)

            // The judged week and the current weight follow the last week that has a reading.
            let judged = expected.week == 10 ? 9 : expected.week
            XCTAssertEqual(result.judgedWeekStart, F.monday(judged), "\(label) judged week")
            XCTAssertEqual(result.currentWeightKg, F.weeklyWeightKg[judged - 1], "\(label) current weight")
            XCTAssertEqual(result.currentWeightDay, F.weighInDay(judged), "\(label) current weight day")
            XCTAssertEqual(result.evidenceStartDay, F.day(F.monday(judged), -7 * 6), "\(label) evidence start")
        }

        // The sequence §13.3 states in one line.
        let hold = CutScorecardVerdictKind.holdSteady, reduce = CutScorecardVerdictKind.reduceCarbs
        XCTAssertEqual(kinds,
                       Array(repeating: hold, count: 8) + [reduce, reduce]
                       + Array(repeating: hold, count: 4) + [.insufficientData, .insufficientData]
                       + [reduce, reduce, .addCalories, reduce, hold, hold])
    }

    /// The parts of the fixture that §13.3 states in prose rather than in a column.
    func testFixtureSeriesAndSignalDetail() {
        let last = evaluate(F.input(week: 22))
        XCTAssertEqual(last.weeks.map(\.weightKg), F.weeklyWeightKg)
        XCTAssertEqual(last.weeks.map(\.waistCm), F.weeklyWaistCm)
        XCTAssertEqual(last.weeks.map(\.weeklyLossKg),
                       [nil, 0.8, 0.8, 0.8, 0.1, 0.1, 0.1, 0.1, 0.1, nil, nil,
                        0.8, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, -1.0, 1.5, 0.5])
        XCTAssertEqual(last.week(2)?.weightDay, "2031-01-22", "week 3: Wednesday's 98.4 beats Monday's 98.9")
        XCTAssertEqual(last.week(9), CutScorecardWeek(weekStart: "2031-03-10", weightKg: nil, weightDay: nil,
                                                       waistCm: nil, waistDay: nil, inPhase: true, weeklyLossKg: nil))

        // Protein: 6 of 7 at the floor, then 3 of 7 logged at the floor, then 3 logged in all.
        let floor: Double? = 100
        XCTAssertEqual(evaluate(F.input(week: 2)).signals.protein,
                       CutScorecardProteinSignal(state: .met, reason: .floorMet, daysLogged: 7,
                                                 daysAtOrAboveFloor: 6, requiredDays: 5, floorGrams: floor))
        XCTAssertEqual(evaluate(F.input(week: 5)).signals.protein,
                       CutScorecardProteinSignal(state: .notMet, reason: .floorMissed, daysLogged: 7,
                                                 daysAtOrAboveFloor: 3, requiredDays: 5, floorGrams: floor))
        XCTAssertEqual(evaluate(F.input(week: 6)).signals.protein,
                       CutScorecardProteinSignal(state: .unknown, reason: .incompleteLogging, daysLogged: 3,
                                                 daysAtOrAboveFloor: 3, requiredDays: 5, floorGrams: floor))
        XCTAssertEqual(evaluate(F.input(week: 7)).signals.protein,
                       CutScorecardProteinSignal(state: .unknown, reason: .noProteinData, daysLogged: 0,
                                                 daysAtOrAboveFloor: 0, requiredDays: 5, floorGrams: floor))

        // Lifts: week 5 Press climbs 60 -> 62.5 while Row holds; week 17 both drop.
        XCTAssertEqual(evaluate(F.input(week: 5)).signals.lifts,
                       CutScorecardLiftSignal(state: .met, reason: .holding, commonExercises: 2, dropped: 0,
                                              climbed: 1, held: 1, windowStartDay: "2031-01-29",
                                              windowEndDay: "2031-02-04"))
        XCTAssertEqual(evaluate(F.input(week: 17)).signals.lifts,
                       CutScorecardLiftSignal(state: .notMet, reason: .dropping, commonExercises: 2, dropped: 2,
                                              climbed: 0, held: 0, windowStartDay: "2031-04-23",
                                              windowEndDay: "2031-04-29"))

        // Waist: week 8 compares with week 6, the earliest reading in a two-week window.
        XCTAssertEqual(evaluate(F.input(week: 8)).signals.waist,
                       CutScorecardWaistSignal(state: .met, reason: .shrinking, currentCm: 97.0,
                                               referenceCm: 97.5, referenceWeekStart: "2031-02-10", changeCm: -0.5))

        // Rate band: the fixture band is 0.40 to 1.20 percent per week.
        XCTAssertEqual(evaluate(F.input(week: 4)).signals.rateBand,
                       CutScorecardRateBandSignal(state: .met, reason: .withinBand, percentPerWeek: 0.81,
                                                  lowPercentPerWeek: 0.40, highPercentPerWeek: 1.20))
        XCTAssertEqual(evaluate(F.input(week: 8)).signals.rateBand,
                       CutScorecardRateBandSignal(state: .notMet, reason: .belowBand, percentPerWeek: 0.103,
                                                  lowPercentPerWeek: 0.40, highPercentPerWeek: 1.20))

        // Rate detail in week 11: the window is weeks 7 to 11 and week 10 contributes no point.
        let rate = evaluate(F.input(week: 11)).rate
        XCTAssertEqual(rate?.pointsUsed, 4)
        XCTAssertEqual(rate?.spanWeeks, 4)
        XCTAssertEqual(rate?.firstWeekStart, F.monday(7))
        XCTAssertEqual(rate?.lastWeekStart, F.monday(11))
        XCTAssertEqual(rate?.referenceWeightKg ?? 0, 96.9, accuracy: 1e-9)

        // Projection detail in week 2: 5.2 kg at 0.8 kg per week is 6.5 weeks.
        let projection = evaluate(F.input(week: 2)).projection
        XCTAssertEqual(projection.remainingKg, 5.2)
        XCTAssertEqual(projection.weeksRemaining ?? 0, 6.5, accuracy: 1e-9)
    }

    /// §13.4, V1 to V12. Each is the fixture with one change.
    func testFixtureVariants() throws {
        // V1: no readings at all.
        let v1 = evaluate(F.input(today: F.weighInDay(4), weights: [], waists: []))
        assertCutVerdict(v1, .insufficientData, .noReadings, "V1")
        XCTAssertEqual(v1.weeks, [], "V1")

        // V2: week 1 only, no lift observations.
        let v2 = evaluate(F.input(today: F.weighInDay(1), lifts: []))
        assertCutVerdict(v2, .insufficientData, .noRuleEvaluable, unevaluated: [r1, r2, r3], "V2")

        // V3: week 11's reading removed, today 2031-03-19. The last weigh-in is two weeks old.
        let v3 = evaluate(F.input(today: "2031-03-19", weights: F.allWeights.filter { $0.day != "2031-03-19" }))
        assertCutVerdict(v3, .insufficientData, .weighInOverdue, "V3")
        assertCutNoRate(v3, .weighInOverdue, "V3")
        assertCutProjection(v3, .weighInOverdue, "V3")

        // V4: no phase, today 2031-01-29. The series and the rate remain.
        let v4 = evaluate(F.input(today: "2031-01-29", phase: nil))
        assertCutVerdict(v4, .insufficientData, .noActivePhase, "V4")
        assertCutRate(v4, loss: 0.8, percent: 0.81, "V4")

        // V5: phase start moved to the Monday of week 5, today 2031-02-19.
        let v5 = evaluate(F.input(today: "2031-02-19", phase: F.phase(startDay: "2031-02-03")))
        XCTAssertEqual(v5.weeks.map(\.inPhase), [false, false, false, false, true, true, true], "V5")
        XCTAssertEqual(v5.weeks.map(\.weeklyLossKg), [nil, nil, nil, nil, nil, 0.1, 0.1], "V5")
        XCTAssertEqual(v5.rule(2)?.state, .unknown, "V5")
        XCTAssertEqual(v5.rule(2)?.unknownReason, .fewerWeeksThanWindow, "V5")
        assertCutRate(v5, loss: 0.1, percent: 0.103, "V5")
        XCTAssertEqual(v5.rate?.pointsUsed, 3, "V5: the rate is clipped to the phase")
        assertCutVerdict(v5, .holdSteady, .ruleFired, rule: r1, "V5")

        // V6: target removed, today 2031-01-29. No projection, same verdict.
        let v6 = evaluate(F.input(today: "2031-01-29", phase: F.phase(target: nil)))
        assertCutProjection(v6, .noTarget, "V6")
        XCTAssertNil(v6.projection.remainingKg, "V6")
        XCTAssertEqual(v6.verdict, evaluate(F.input(week: 4)).verdict, "V6")

        // V7: 98.0 kg backdated to Thursday 2031-01-16, today 2031-03-05.
        let base9 = evaluate(F.input(week: 9))
        let v7 = evaluate(F.input(today: "2031-03-05", weights: F.allWeights + [F.weight("2031-01-16", 98.0)]))
        XCTAssertEqual(v7.weeks.map(\.weightKg), [100.0, 98.0, 98.4, 97.6, 97.5, 97.4, 97.3, 97.2, 97.1], "V7")
        XCTAssertEqual(v7.week(1)?.weightDay, "2031-01-16", "V7")
        XCTAssertEqual(v7.weeks.map(\.weeklyLossKg), [nil, 2.0, -0.4, 0.8, 0.1, 0.1, 0.1, 0.1, 0.1], "V7")
        XCTAssertEqual(v7.verdict, base9.verdict, "V7")
        XCTAssertEqual(v7.rules, base9.rules, "V7")

        // V8: week 6's weight replaced by 99.9, today 2031-02-26.
        // SPEC-AMBIGUITY (discrepancy in §13.4): the table says "the fitted rate moves by less than the
        // end-point difference would". On this day the window is weeks 4 to 8 and week 6 is its centre
        // point, which has no leverage on a least-squares slope and is not an end point either: the
        // fitted loss stays exactly 0.100 and so does the end-point difference (97.6 - 97.2) / 4. Neither
        // moves, so "less than" is not satisfied. What §7 gives is asserted here; the comparison the
        // variant intends is made in `testSingleOutlierWeekMovesRateLessThanEndpointDifference`, with the
        // outlier at the end of the window.
        let outlier = F.allWeights.map { $0.day == F.weighInDay(6) ? F.weight($0.day, 99.9) : $0 }
        let v8 = evaluate(F.input(today: "2031-02-26", weights: outlier))
        XCTAssertEqual(v8.weeks.map(\.weeklyLossKg), [nil, 0.8, 0.8, 0.8, 0.1, -2.4, 2.6, 0.1], "V8")
        assertCutRate(v8, loss: 0.1, percent: 0.102, "V8")
        XCTAssertEqual(v8.rate?.referenceWeightKg ?? 0, 97.9, accuracy: 1e-9, "V8")
        assertCutRules(v8, "FNN", "V8: week 7's 2.6 kg loss breaks the slow run")
        assertCutVerdict(v8, .holdSteady, .ruleFired, rule: r1, "V8")

        // V9: a NaN weight and a -5.0 weight added in week 4.
        let base4 = evaluate(F.input(week: 4))
        let v9 = evaluate(F.input(today: F.weighInDay(4), weights: F.allWeights
                                  + [F.weight("2031-01-28", .nan), F.weight("2031-01-28", -5.0)]))
        XCTAssertEqual(v9.rejections, CutScorecardRejections(nonFinite: 1, nonPositive: 1, invalidDay: 0, future: 0), "V9")
        XCTAssertEqual(v9.weeks, base4.weeks, "V9")
        XCTAssertEqual(v9.rate, base4.rate, "V9")
        XCTAssertEqual(v9.signals, base4.signals, "V9")
        XCTAssertEqual(v9.rules, base4.rules, "V9")
        XCTAssertEqual(v9.verdict, base4.verdict, "V9")
        XCTAssertEqual(v9.projection, base4.projection, "V9")
        XCTAssertEqual(v9.currentWeightKg, base4.currentWeightKg, "V9")

        // V10: a reading dated 2029-06-06 added. Only `weeks` grows.
        let base22 = evaluate(F.input(week: 22))
        let v10 = evaluate(F.input(today: F.weighInDay(22), weights: F.allWeights + [F.weight("2029-06-06", 101.0)]))
        XCTAssertEqual(v10.weeks.count, 105, "V10: 2029-06-04 to 2031-06-02 is 105 Monday weeks")
        XCTAssertEqual(v10.weeks.first, CutScorecardWeek(weekStart: "2029-06-04", weightKg: 101.0,
                                                         weightDay: "2029-06-06", waistCm: nil, waistDay: nil,
                                                         inPhase: false, weeklyLossKg: nil), "V10")
        XCTAssertNil(v10.week(1)?.weightKg, "V10: the gap is not filled")
        XCTAssertEqual(v10.week(1)?.inPhase, false, "V10")
        XCTAssertEqual(Array(v10.weeks.suffix(22)), base22.weeks, "V10")
        XCTAssertEqual(v10.rate, base22.rate, "V10")
        XCTAssertEqual(v10.signals, base22.signals, "V10")
        XCTAssertEqual(v10.rules, base22.rules, "V10")
        XCTAssertEqual(v10.verdict, base22.verdict, "V10")
        XCTAssertEqual(v10.projection, base22.projection, "V10")
        XCTAssertEqual(v10.evidenceStartDay, base22.evidenceStartDay, "V10")
        XCTAssertEqual(v10.judgedWeekStart, base22.judgedWeekStart, "V10")
        XCTAssertEqual(v10.currentWeightKg, base22.currentWeightKg, "V10")
        XCTAssertEqual(v10.rejections, base22.rejections, "V10")

        // V11: "Fixture Press" renamed "fixture press" from week 17 on. In week 17 the press appears under
        // one name in each window, so only the row is common. A week later both windows use the new name.
        let renamed = F.allLifts(pressName: "fixture press", renameFromWeek: 17)
        let v11 = evaluate(F.input(today: F.weighInDay(17), lifts: renamed))
        XCTAssertEqual(v11.signals.lifts, CutScorecardLiftSignal(state: .notMet, reason: .dropping, commonExercises: 1,
                                                                 dropped: 1, climbed: 0, held: 0,
                                                                 windowStartDay: "2031-04-23",
                                                                 windowEndDay: "2031-04-29"), "V11")
        XCTAssertEqual(evaluate(F.input(week: 17)).signals.lifts.commonExercises, 2, "V11 baseline")
        XCTAssertEqual(evaluate(F.input(today: F.weighInDay(18), lifts: renamed)).signals.lifts.commonExercises, 2, "V11 week 18")

        // V12: target 80.0, today 2031-02-26. 17.2 kg at 0.1 kg per week is 172 weeks.
        let v12 = evaluate(F.input(today: "2031-02-26", phase: F.phase(target: 80.0)))
        assertCutProjection(v12, .beyondHorizon, "V12")
        XCTAssertEqual(v12.projection.remainingKg, 17.2, "V12")
    }
}
