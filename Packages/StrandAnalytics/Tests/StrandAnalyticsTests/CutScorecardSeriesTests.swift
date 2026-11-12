import XCTest
@testable import StrandAnalytics

private typealias F = CutScorecardFixture
private let r1 = CutScorecardRule.liftsHoldingWaistShrinking
private let r2 = CutScorecardRule.liftsDropping
private let r3 = CutScorecardRule.slowLoss

/// `CutScorecard.evaluate`: the weekly series (gaps, edits, overdue weigh-ins), the phase boundary, the
/// projection of `docs/personal/superapp/specs/stage-1.md` §7.8 in its precedence order, and week
/// boundaries in day-key space.
final class CutScorecardSeriesTests: XCTestCase {

    private let steady: [Double?] = [100.0, 99.2, 98.4, 97.6]
    private let shrinkingWaist: [Double?] = [100.0, 99.5, 99.0, 98.5]
    private let noRejections = CutScorecardRejections(nonFinite: 0, nonPositive: 0, invalidDay: 0, future: 0)

    private func evaluate(_ input: CutScorecardInput) -> CutScorecardResult {
        CutScorecard.evaluate(input)
    }

    /// Two weigh-ins a week apart under a chosen target: the smallest input that has a projection.
    private func projecting(_ first: Double, _ second: Double, target: Double?,
                            parameters: CutScorecardParameters = F.parameters,
                            today: String? = nil) -> CutScorecardResult {
        evaluate(F.scenario(weights: [first, second], phase: F.phase(target: target),
                            parameters: parameters, today: today))
    }

    // MARK: - Gaps and edits

    /// Fault F16: bridging the gap would give week 4 a loss of 0.2 and fire rule 3.
    func testMissedWeekInTheMiddleLeavesANilWeekAndBreaksTheSlowLossRun() {
        let lifts = F.holdingSessions(weeks: -1...7)
        func run(_ weights: [Double?]) -> CutScorecardResult {
            let waists: [Double?] = weights.map { $0 == nil ? nil : 100.0 }
            return evaluate(F.scenario(weights: weights, waists: waists,
                                       lifts: lifts.filter { $0.day <= F.weighInDay(weights.count) }))
        }
        let result = run([100.0, 99.9, nil, 99.7, 99.6])
        XCTAssertEqual(result.weeks.count, 5)
        XCTAssertEqual(result.week(2), CutScorecardWeek(weekStart: "2031-01-20", weightKg: nil, weightDay: nil,
                                                         waistCm: nil, waistDay: nil, inPhase: true, weeklyLossKg: nil))
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, 0.1, nil, nil, 0.1],
                       "the loss across the gap belongs to neither week")
        assertCutRules(result, "NNU", reasons: [nil, nil, .missedWeighIn])
        XCTAssertEqual(result.rule(2)?.consecutiveWeeks, 1)
        assertCutVerdict(result, .holdSteady, .noChangeRuleFired, unevaluated: [r3])
        XCTAssertEqual(result.rejections, noRejections)

        // One more slow week: the window is weeks 4 to 6 and week 4 still has no loss.
        let sixWeeks = run([100.0, 99.9, nil, 99.7, 99.6, 99.5])
        assertCutRules(sixWeeks, "NNU", reasons: [nil, nil, .missedWeighIn])
        XCTAssertEqual(sixWeeks.rule(2)?.consecutiveWeeks, 2)
        // And one more: three slow weeks in a row after the gap, and the rule fires again.
        let sevenWeeks = run([100.0, 99.9, nil, 99.7, 99.6, 99.5, 99.4])
        assertCutRules(sevenWeeks, "NNF")
        assertCutVerdict(sevenWeeks, .reduceCarbs, .ruleFired, rule: r3, kcal: -250)
    }

    /// 100, 99, none, 97 lies exactly on a line of -1 kg per week over the true spacing 0, 1, 3. Closing
    /// the gap (0, 1, 2) would fit -1.5.
    func testMissedWeekStillFitsRateAcrossTrueSpacing() throws {
        let result = evaluate(F.scenario(weights: [100.0, 99.0, nil, 97.0]))
        let rate = try XCTUnwrap(result.rate)
        XCTAssertEqual(rate.lossKgPerWeek, 1.0)
        XCTAssertEqual(rate.percentPerWeek, 1.014, "100 x 1.0 / 98.667 = 1.0135")
        XCTAssertEqual(rate.referenceWeightKg, 296.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(rate.pointsUsed, 3)
        XCTAssertEqual(rate.spanWeeks, 3)
        XCTAssertEqual(rate.firstWeekStart, "2031-01-06")
        XCTAssertEqual(rate.lastWeekStart, "2031-01-27")
    }

    /// The window is `J - rateWindowWeeks … J`: with a window of 4, five consecutive weekly points.
    func testRateWindowHoldsAtMostWindowPlusOnePoints() throws {
        // Six weeks. Weeks 2 to 6 lie on -0.5 per week; week 1 is 3 kg above that line and outside.
        let result = evaluate(F.scenario(weights: [105.0, 101.5, 101.0, 100.5, 100.0, 99.5]))
        let rate = try XCTUnwrap(result.rate)
        XCTAssertEqual(rate.pointsUsed, 5)
        XCTAssertEqual(rate.spanWeeks, 4)
        XCTAssertEqual(rate.firstWeekStart, "2031-01-13")
        XCTAssertEqual(rate.lossKgPerWeek, 0.5)
        XCTAssertEqual(rate.referenceWeightKg, 100.5, accuracy: 1e-9)
        XCTAssertEqual(rate.percentPerWeek, 0.498, "100 x 0.5 / 100.5 = 0.4975")
    }

    /// Variant V3. Fault F17.
    func testTwoMissedWeeksAtTheEndIsWeighInOverdue() {
        let weights = F.allWeights.filter { $0.day != F.weighInDay(11) }
        let result = evaluate(F.input(today: "2031-03-19", weights: weights))
        assertCutVerdict(result, .insufficientData, .weighInOverdue)
        assertCutRules(result, "UUU", reasons: [.weighInOverdue, .weighInOverdue, .weighInOverdue])
        XCTAssertEqual(result.rules.map(\.consecutiveWeeks), [0, 0, 0])
        assertCutNoRate(result, .weighInOverdue)
        XCTAssertEqual(result.signals.waist.state, .unknown)
        XCTAssertEqual(result.signals.waist.reason, .weighInOverdue)
        XCTAssertEqual(result.signals.lifts.state, .unknown)
        XCTAssertEqual(result.signals.lifts.reason, .weighInOverdue)
        XCTAssertEqual(result.signals.protein.state, .unknown)
        XCTAssertEqual(result.signals.protein.reason, .weighInOverdue)
        XCTAssertEqual(result.signals.rateBand.state, .unknown)
        XCTAssertEqual(result.signals.rateBand.reason, .weighInOverdue)
        assertCutProjection(result, .weighInOverdue)
        // Ruling R9: `remainingKg` is set whenever a phase target and an in-phase current weight exist,
        // including while overdue. The last weight, 97.1, is 3.1 kg above the 94.0 target.
        XCTAssertEqual(result.projection.remainingKg, 3.1)

        // The series and the last weight are still reported; only current claims are withheld.
        XCTAssertEqual(result.weeks.count, 11)
        XCTAssertNil(result.week(9)?.weightKg)
        XCTAssertNil(result.week(10)?.weightKg)
        XCTAssertEqual(result.week(8)?.weeklyLossKg, 0.1)
        XCTAssertEqual(result.currentWeightKg, 97.1)
        XCTAssertEqual(result.currentWeightDay, F.weighInDay(9))
        XCTAssertEqual(result.judgedWeekStart, F.monday(9))
        XCTAssertEqual(result.evidenceStartDay, "2031-01-20", "a judged week exists, so the field is set")

        // The boundary is the Monday: Sunday of the following week is still one week old.
        let sunday = evaluate(F.input(today: "2031-03-16", weights: weights))
        assertCutVerdict(sunday, .reduceCarbs, .ruleFired, rule: r3, kcal: -250, "Sunday 2031-03-16")
        let monday = evaluate(F.input(today: "2031-03-17", weights: weights))
        assertCutVerdict(monday, .insufficientData, .weighInOverdue, "Monday 2031-03-17")
    }

    /// Fixture week 10: nothing was measured, and week 9's verdict stands for one more week.
    func testOneMissedWeekAtTheEndKeepsLastWeeksVerdict() {
        let week9 = evaluate(F.input(week: 9))
        for today in [F.monday(10), F.weighInDay(10), "2031-03-16"] {
            let result = evaluate(F.input(today: today))
            XCTAssertEqual(result.verdict, week9.verdict, today)
            assertCutVerdict(result, .reduceCarbs, .ruleFired, rule: r3, kcal: -250, today)
            XCTAssertEqual(result.rules, week9.rules, today)
            XCTAssertEqual(result.signals, week9.signals, today)
            XCTAssertEqual(result.rate, week9.rate, today)
            XCTAssertEqual(result.projection, week9.projection, today)
            XCTAssertEqual(result.judgedWeekStart, F.monday(9), today)
            XCTAssertEqual(result.weeks.count, 10, today)
            XCTAssertEqual(Array(result.weeks.prefix(9)), week9.weeks, today)
            XCTAssertEqual(result.weeks.last, CutScorecardWeek(weekStart: "2031-03-10", weightKg: nil, weightDay: nil,
                                                               waistCm: nil, waistDay: nil, inPhase: true,
                                                               weeklyLossKg: nil), today)
        }
    }

    func testGapLongerThanWindowHasNoRate() {
        // Weeks 1 and 7 with a window of 4: the window is weeks 3 to 7 and holds one point.
        let result = evaluate(F.scenario(weights: [100.0, nil, nil, nil, nil, nil, 98.0]))
        assertCutNoRate(result, .gapLongerThanWindow)
        XCTAssertEqual(result.signals.rateBand.reason, .rateUnknown)
        assertCutProjection(result, .rateUnknown)
        XCTAssertEqual(result.projection.remainingKg, 4.0)
        XCTAssertEqual(result.weeks.count, 7)
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, nil, nil, nil, nil, nil, nil])

        // One week either side of the window edge: weeks 1 and 5 are exactly four weeks apart.
        let inside = evaluate(F.scenario(weights: [100.0, nil, nil, nil, 98.0]))
        assertCutRate(inside, loss: 0.5, percent: 0.505)
        XCTAssertEqual(inside.rate?.pointsUsed, 2)
        XCTAssertEqual(inside.rate?.spanWeeks, 4)
        let outside = evaluate(F.scenario(weights: [100.0, nil, nil, nil, nil, 98.0]))
        assertCutNoRate(outside, .gapLongerThanWindow)

        // §7.4 separates `singleReading` from `gapLongerThanWindow` by whether "older points exist"
        // anywhere in the phase, however old. Ruling R2 lists this as one of the things a reading dated
        // before `evidenceStartDay` may change: with a window of 4 the reading in week 1 below is dated
        // before it (six weeks before the judged week) and still decides the reason.
        let farWeights: [Double?] = [100.0] + Array(repeating: nil, count: 10) + [98.0]
        let far = evaluate(F.scenario(weights: farWeights))
        XCTAssertLessThan(F.weighInDay(1), far.evidenceStartDay ?? "")
        assertCutNoRate(far, .gapLongerThanWindow)

        // A point before the phase is not an "older point": the phase holds one weigh-in.
        let clipped = evaluate(F.scenario(weights: [100.0, nil, nil, nil, nil, nil, 98.0],
                                          phase: F.phase(startDay: F.monday(7))))
        assertCutNoRate(clipped, .singleReading)
    }

    func testBackdatedReadingChangesOnlyItsOwnWeek() {
        let weights = F.weekly([100.0, 99.2, nil, 97.6, 96.8])
        let today = F.weighInDay(5)
        let base = evaluate(F.make(weights: weights, today: today))
        XCTAssertEqual(base.weeks.map(\.weeklyLossKg), [nil, 0.8, nil, nil, 0.8])

        // A reading entered later for the Tuesday of the missed week 3.
        let filled = evaluate(F.make(weights: weights + [F.weight("2031-01-21", 98.5)], today: today))
        XCTAssertEqual(filled.weeks.map(\.weightKg), [100.0, 99.2, 98.5, 97.6, 96.8])
        XCTAssertEqual(filled.week(2)?.weightDay, "2031-01-21")
        XCTAssertEqual(filled.weeks.map(\.weeklyLossKg), [nil, 0.8, 0.7, 0.9, 0.8],
                       "only the losses that touch week 3 change")
        for index in [0, 1, 3, 4] {
            XCTAssertEqual(filled.week(index)?.weightKg, base.week(index)?.weightKg)
            XCTAssertEqual(filled.week(index)?.weightDay, base.week(index)?.weightDay)
        }
        XCTAssertEqual(filled.currentWeightKg, 96.8, "a backdated reading is not the current weight")
        XCTAssertEqual(filled.currentWeightDay, today)
        XCTAssertEqual(filled.judgedWeekStart, base.judgedWeekStart)

        // Backdated into a week that already has a later reading: it represents nothing and the result
        // is identical.
        let shadowed = evaluate(F.make(weights: weights + [F.weight("2031-01-13", 105.0)], today: today))
        XCTAssertEqual(shadowed, base)
    }

    func testDeletedReadingLeavesAMissedWeek() {
        let base = evaluate(F.input(week: 9))
        let result = evaluate(F.input(today: F.weighInDay(9), weights: F.allWeights.filter { $0.day != F.weighInDay(5) }))
        XCTAssertNil(result.week(4)?.weightKg)
        XCTAssertNil(result.week(4)?.weightDay)
        XCTAssertEqual(result.week(4)?.waistCm, 98.0, "the waist reading of that week is untouched")
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, 0.8, 0.8, 0.8, nil, nil, 0.1, 0.1, 0.1],
                       "nothing is carried forward or interpolated into the missed week")
        for index in [0, 1, 2, 3, 5, 6, 7, 8] {
            XCTAssertEqual(result.week(index)?.weightKg, base.week(index)?.weightKg)
        }
        // The rate window (weeks 5 to 9) now holds four points, starting in week 6.
        assertCutRate(result, loss: 0.1, percent: 0.103)
        XCTAssertEqual(result.rate?.pointsUsed, 4)
        XCTAssertEqual(result.rate?.spanWeeks, 3)
        XCTAssertEqual(result.rate?.firstWeekStart, F.monday(6))
        // Weeks 7, 8 and 9 still have losses, so rule 3 still fires.
        XCTAssertEqual(result.rule(2)?.state, .fired)
        XCTAssertEqual(result.rule(2)?.consecutiveWeeks, 3)
        XCTAssertEqual(result.verdict, base.verdict)
    }

    func testWeightExactlyFlatIsSlowLossAndNotLosing() {
        let flat: [Double?] = [100.0, 100.0, 100.0, 100.0]
        let result = evaluate(F.scenario(weights: flat, waists: flat, lifts: F.holdingSessions(weeks: -1...4)))
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, 0.0, 0.0, 0.0], "a flat week is a loss of zero, not nil")
        assertCutRate(result, loss: 0.0, percent: 0.0)
        XCTAssertEqual(result.rule(2)?.state, .fired)
        XCTAssertEqual(result.rule(2)?.consecutiveWeeks, 3)
        assertCutVerdict(result, .reduceCarbs, .ruleFired, rule: r3, kcal: -250)
        assertCutProjection(result, .notLosing)
        XCTAssertEqual(result.projection.remainingKg, 6.0)
        XCTAssertEqual(result.signals.rateBand.reason, .belowBand)
    }

    /// Variant V8's intent. With the outlier as the last point of the window (fixture week 6 read as
    /// 99.9 instead of 97.4) the fitted loss moves from 0.450 to -0.050, a change of 0.5; the end-point
    /// difference, (99.2 - last) / 4, moves from 0.450 to -0.175, a change of 0.625.
    func testSingleOutlierWeekMovesRateLessThanEndpointDifference() throws {
        let today = F.weighInDay(6)
        let outlier = F.allWeights.map { $0.day == today ? F.weight($0.day, 99.9) : $0 }
        let base = try XCTUnwrap(evaluate(F.input(today: today)).rate)
        let moved = try XCTUnwrap(evaluate(F.input(today: today, weights: outlier)).rate)
        XCTAssertEqual(base.lossKgPerWeek, 0.45)
        XCTAssertEqual(moved.lossKgPerWeek, -0.05)
        XCTAssertEqual(moved.pointsUsed, 5)
        let fittedMove = abs(base.lossKgPerWeek - moved.lossKgPerWeek)
        let endpointMove = abs((99.2 - 97.4) / 4 - (99.2 - 99.9) / 4)
        XCTAssertEqual(fittedMove, 0.5, accuracy: 1e-9)
        XCTAssertEqual(endpointMove, 0.625, accuracy: 1e-9)
        XCTAssertLessThan(fittedMove, endpointMove)

        // An outlier in the middle of the window has no leverage on the slope at all: fixture week 8,
        // where week 6 is the centre of weeks 4 to 8.
        let centre = F.allWeights.map { $0.day == F.weighInDay(6) ? F.weight($0.day, 99.9) : $0 }
        XCTAssertEqual(evaluate(F.input(today: F.weighInDay(8), weights: centre)).rate?.lossKgPerWeek, 0.1)
    }

    /// Fixture week 20: 95.5 after 94.5.
    func testWeightRisingProjectionIsNotLosing() {
        let result = evaluate(F.input(week: 20))
        assertCutRate(result, loss: -0.12, percent: -0.127)
        XCTAssertEqual(result.weeks.last?.weeklyLossKg, -1.0)
        assertCutProjection(result, .notLosing)
        XCTAssertEqual(result.projection.remainingKg, 1.5)
        // A rising week is a slow week: rule 3 stays fired.
        XCTAssertEqual(result.rule(2)?.state, .fired)
        assertCutVerdict(result, .reduceCarbs, .ruleFired, rule: r3, kcal: -250)
    }

    func testWeeksAreContiguousFromTheEarliestReadingToToday() {
        // The earliest reading is a waist in week 1; weights start in week 3; today is in week 6.
        let result = evaluate(F.make(weights: [F.weight(F.weighInDay(3), 99.0)],
                                     waists: [F.waist(F.weighInDay(1), 100.0)],
                                     parameters: F.params { $0.maxWeighInAgeWeeks = 4 }, today: "2031-02-15"))
        XCTAssertEqual(result.weeks.map(\.weekStart),
                       ["2031-01-06", "2031-01-13", "2031-01-20", "2031-01-27", "2031-02-03", "2031-02-10"])
        XCTAssertEqual(result.weeks.map(\.weightKg), [nil, nil, 99.0, nil, nil, nil])
        XCTAssertEqual(result.weeks.map(\.waistCm), [100.0, nil, nil, nil, nil, nil])
        XCTAssertEqual(result.week(0)?.waistDay, F.weighInDay(1))
        XCTAssertEqual(result.judgedWeekStart, "2031-01-20")
    }

    // MARK: - Phase

    /// Variant V4.
    func testNoPhaseIsInsufficientDataNoActivePhaseButSeriesAndRateRemain() throws {
        let result = evaluate(F.input(today: F.weighInDay(4), phase: nil))
        assertCutVerdict(result, .insufficientData, .noActivePhase)
        assertCutRules(result, "UUU", reasons: [.noActivePhase, .noActivePhase, .noActivePhase])
        assertCutProjection(result, .noActivePhase)
        XCTAssertEqual(result.signals.rateBand.state, .unknown)
        XCTAssertEqual(result.signals.rateBand.reason, .noActivePhase)
        XCTAssertNil(result.invalidInput)

        let rate = try XCTUnwrap(result.rate)
        XCTAssertEqual(rate.lossKgPerWeek, 0.8)
        XCTAssertEqual(rate.percentPerWeek, 0.81)
        XCTAssertEqual(rate.pointsUsed, 4)
        XCTAssertEqual(rate.firstWeekStart, F.weekOneMonday)
        XCTAssertNil(result.rateUnavailable)

        XCTAssertEqual(result.weeks.map(\.weightKg), [100.0, 99.2, 98.4, 97.6])
        XCTAssertEqual(result.weeks.map(\.waistCm), [100.0, 99.5, 99.0, 98.5])
        XCTAssertEqual(result.weeks.map(\.inPhase), [false, false, false, false])
        XCTAssertEqual(result.currentWeightKg, 97.6)
        XCTAssertEqual(result.currentWeightDay, F.weighInDay(4))
        XCTAssertEqual(result.judgedWeekStart, F.monday(4))
        // Ruling R7: with no active phase the domain is every week, so the weekly losses are reported
        // for every pair of consecutive weighed weeks, while `inPhase` stays false.
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, 0.8, 0.8, 0.8])
    }

    func testPhaseNotStartedIsReported() {
        let lifts = F.holdingSessions(weeks: -1...4)
        func run(start: String) -> CutScorecardResult {
            evaluate(F.scenario(weights: steady, waists: shrinkingWaist, lifts: lifts, phase: F.phase(startDay: start)))
        }
        // Today is Wednesday 2031-01-29.
        for start in ["2031-02-03", "2031-01-30"] {
            let result = run(start: start)
            assertCutVerdict(result, .insufficientData, .phaseNotStarted, start)
            assertCutRules(result, "UUU", reasons: [.noActivePhase, .noActivePhase, .noActivePhase], start)
            assertCutProjection(result, .noActivePhase, start)
            XCTAssertEqual(result.signals.rateBand.reason, .noActivePhase, start)
            assertCutRate(result, loss: 0.8, percent: 0.81, start)
            XCTAssertEqual(result.weeks.map(\.inPhase), [false, false, false, false], start)
            XCTAssertEqual(result.signals.lifts.state, .met, start)
            XCTAssertEqual(result.signals.waist.state, .met, start)
        }
        // A phase that starts today has started.
        let startsToday = run(start: "2031-01-29")
        XCTAssertNotEqual(startsToday.verdict.reason, .phaseNotStarted)
        XCTAssertEqual(startsToday.weeks.map(\.inPhase), [false, false, false, true])
        assertCutVerdict(startsToday, .holdSteady, .noChangeRuleFired, unevaluated: [r1, r3])
    }

    /// Fault F23. The same data fires rule 2 (and rule 3) when the phase covers all five weeks, and
    /// neither when the phase starts in week 4.
    func testReadingsBeforePhaseStartDoNotFeedRules() {
        let weights: [Double?] = [100.0, 99.9, 99.8, 99.7, 99.6]
        let waists: [Double?] = [nil, nil, 101.0, 100.0, 100.0]
        let lifts = F.pressSessions([(1, 100), (2, 90), (3, 80), (4, 70), (5, 60)])

        let whole = evaluate(F.scenario(weights: weights, waists: waists, lifts: lifts))
        assertCutRules(whole, "NFF", "phase from week 1")
        assertCutVerdict(whole, .addCalories, .ruleFired, rule: r2, kcal: 300, overridden: [r3], "phase from week 1")
        XCTAssertEqual(whole.signals.waist.changeCm, -1.0, "phase from week 1")
        XCTAssertEqual(whole.rate?.pointsUsed, 5, "phase from week 1")

        let clipped = evaluate(F.scenario(weights: weights, waists: waists, lifts: lifts,
                                          phase: F.phase(startDay: F.monday(4))))
        XCTAssertEqual(clipped.weeks.map(\.inPhase), [false, false, false, true, true])
        XCTAssertEqual(clipped.weeks.map(\.weightKg), weights, "earlier readings still appear in `weeks`")
        XCTAssertEqual(clipped.weeks.map(\.weeklyLossKg), [nil, nil, nil, nil, 0.1])
        assertCutRules(clipped, "NUU", reasons: [nil, .fewerWeeksThanWindow, .fewerWeeksThanWindow])
        XCTAssertEqual(clipped.rule(1)?.consecutiveWeeks, 2, "weeks 4 and 5; week 3 is before the phase")
        XCTAssertEqual(clipped.rule(2)?.consecutiveWeeks, 1)
        assertCutVerdict(clipped, .holdSteady, .noChangeRuleFired, unevaluated: [r2, r3])
        // The rate is clipped to the phase: two points.
        assertCutRate(clipped, loss: 0.1, percent: 0.1)
        XCTAssertEqual(clipped.rate?.pointsUsed, 2)
        XCTAssertEqual(clipped.rate?.firstWeekStart, F.monday(4))
        // The waist reference is clipped to the phase: week 4's 100.0, not week 3's 101.0.
        XCTAssertEqual(clipped.signals.waist, CutScorecardWaistSignal(state: .notMet, reason: .notShrinking,
                                                                      currentCm: 100.0, referenceCm: 100.0,
                                                                      referenceWeekStart: F.monday(4), changeCm: 0.0))
        // The current weight ignores the phase.
        XCTAssertEqual(clipped.currentWeightKg, 99.6)
    }

    /// Variant V5, and the phase's first week.
    func testFirstInPhaseReadingIsTheBaseline() {
        let result = evaluate(F.input(today: "2031-02-19", phase: F.phase(startDay: "2031-02-03")))
        XCTAssertEqual(result.weeks.map(\.inPhase), [false, false, false, false, true, true, true])
        XCTAssertNil(result.week(4)?.weeklyLossKg, "week 5 is the baseline: week 4 is before the phase")
        XCTAssertEqual(result.week(4)?.weightKg, 97.5)
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, nil, nil, nil, nil, 0.1, 0.1])
        XCTAssertEqual(result.rule(2)?.state, .unknown)
        XCTAssertEqual(result.rule(2)?.unknownReason, .fewerWeeksThanWindow)
        XCTAssertEqual(result.rule(2)?.consecutiveWeeks, 2)
        XCTAssertEqual(result.rate?.firstWeekStart, "2031-02-03")

        // Only readings before the phase: the phase has started and holds no weigh-in.
        let none = evaluate(F.scenario(weights: steady, waists: shrinkingWaist,
                                       phase: F.phase(startDay: "2031-02-03"), today: "2031-02-03"))
        assertCutVerdict(none, .insufficientData, .noReadings)
        assertCutRules(none, "UUU", reasons: [.noReadings, .noReadings, .noReadings])
        assertCutNoRate(none, .noReadings)
        XCTAssertNil(none.judgedWeekStart)
        XCTAssertNil(none.evidenceStartDay)
        XCTAssertEqual(none.weeks.count, 5, "the earlier readings still appear in `weeks`")
        XCTAssertEqual(none.currentWeightKg, 97.6, "the current weight ignores the phase")

        // The phase is a set of Monday weeks (§7.2: "every week from weekStart(phase.startDay) on"). A
        // phase that starts on a Thursday includes that week's Wednesday weigh-in.
        let midWeek = evaluate(F.scenario(weights: steady, phase: F.phase(startDay: "2031-01-30"), today: "2031-01-30"))
        XCTAssertEqual(midWeek.weeks.map(\.inPhase), [false, false, false, true])
        XCTAssertEqual(midWeek.judgedWeekStart, "2031-01-27")
        assertCutNoRate(midWeek, .singleReading)
    }

    // MARK: - Projection (§7.8, in precedence order)

    /// Fixture week 22: 93.5 against a target of 94.0.
    func testTargetAlreadyReached() {
        let result = evaluate(F.input(week: 22))
        assertCutProjection(result, .targetReached)
        XCTAssertEqual(result.projection.remainingKg, -0.5)
    }

    /// Fixture week 21: 94.0 against a target of 94.0. The comparison is `remaining <= tolerance`.
    func testTargetEqualToCurrentWeightIsReached() {
        let result = evaluate(F.input(week: 21))
        assertCutProjection(result, .targetReached)
        XCTAssertEqual(result.projection.remainingKg, 0.0)

        // One quantum above the target with a tolerance of zero is not reached.
        let above = evaluate(F.input(today: F.weighInDay(21), phase: F.phase(target: 93.999)))
        XCTAssertEqual(above.projection.remainingKg, 0.001)
        assertCutProjection(above, .projected, targetDay: "2031-05-29")

        // The tolerance is the parameter. Fixture week 19 is 0.5 kg above the target.
        func week19(tolerance: Double) -> CutScorecardProjectionStatus {
            evaluate(F.input(today: F.weighInDay(19), parameters: F.params { $0.targetToleranceKg = tolerance }))
                .projection.status
        }
        XCTAssertEqual(week19(tolerance: 0.499), .projected)
        XCTAssertEqual(week19(tolerance: 0.5), .targetReached)
        XCTAssertEqual(week19(tolerance: 0.501), .targetReached)
    }

    /// A target above the current weight is reached, and that is decided before the rate is looked at.
    func testTargetAboveCurrentWeightIsReached() {
        let single = evaluate(F.scenario(weights: [90.0], phase: F.phase(target: 95.0)))
        assertCutNoRate(single, .singleReading)
        assertCutProjection(single, .targetReached)
        XCTAssertEqual(single.projection.remainingKg, -5.0)

        let rising = projecting(90.0, 91.0, target: 95.0)
        assertCutProjection(rising, .targetReached)
        XCTAssertEqual(rising.projection.remainingKg, -4.0)
    }

    /// Variant V6.
    func testNoTargetHasNoProjection() {
        let result = evaluate(F.input(today: F.weighInDay(4), phase: F.phase(target: nil)))
        assertCutProjection(result, .noTarget)
        XCTAssertNil(result.projection.remainingKg)
        assertCutVerdict(result, .holdSteady, .ruleFired, rule: r1)
        // No target is reported before an unknown rate and before a rising weight.
        assertCutProjection(evaluate(F.scenario(weights: [100.0], phase: F.phase(target: nil))), .noTarget)
        assertCutProjection(projecting(100.0, 100.5, target: nil), .noTarget)
    }

    func testProjectionWithUnknownRateIsRateUnknown() {
        let result = evaluate(F.scenario(weights: [100.0]))
        assertCutProjection(result, .rateUnknown)
        XCTAssertEqual(result.projection.remainingKg, 6.0)
    }

    /// Fault F18: dividing by a zero rate.
    func testProjectionWithZeroSlopeIsNotLosing() {
        let flat = projecting(100.0, 100.0, target: 94.0)
        assertCutRate(flat, loss: 0.0, percent: 0.0)
        assertCutProjection(flat, .notLosing)
        XCTAssertEqual(flat.projection.remainingKg, 6.0)

        // A loss that quantizes to zero is zero: 0.0004 kg in a week.
        let hair = projecting(100.0, 99.9996, target: 94.0)
        assertCutRate(hair, loss: 0.0, percent: 0.0)
        assertCutProjection(hair, .notLosing)

        // One quantum of loss is losing: 0.009 kg at 0.001 kg per week is nine weeks.
        let quantum = projecting(100.0, 99.999, target: 99.99)
        assertCutRate(quantum, loss: 0.001, percent: 0.001)
        assertCutProjection(quantum, .projected, targetDay: "2031-03-19")
        XCTAssertEqual(quantum.projection.weeksRemaining ?? 0, 9.0, accuracy: 1e-9)
    }

    func testProjectionWithPositiveSlopeIsNotLosing() {
        let rising = projecting(100.0, 100.5, target: 94.0)
        assertCutRate(rising, loss: -0.5, percent: -0.499)
        assertCutProjection(rising, .notLosing)
        XCTAssertEqual(rising.projection.remainingKg, 6.5)

        // One quantum of gain.
        let quantum = projecting(100.0, 100.001, target: 99.99)
        assertCutRate(quantum, loss: -0.001, percent: -0.001)
        assertCutProjection(quantum, .notLosing)
        XCTAssertEqual(quantum.projection.remainingKg, 0.011)
    }

    /// 0.2 kg at 0.8 kg per week is 1.75 days, so the day is Friday 2031-01-17, two days after the
    /// weigh-in. Once that day has passed the projection is withdrawn, not shown as a past date.
    func testProjectionIsNeverBeforeToday() {
        func run(today: String) -> CutScorecardResult { projecting(100.0, 99.2, target: 99.0, today: today) }
        assertCutProjection(run(today: "2031-01-15"), .projected, targetDay: "2031-01-17")
        assertCutProjection(run(today: "2031-01-16"), .projected, targetDay: "2031-01-17")
        assertCutProjection(run(today: "2031-01-17"), .projected, targetDay: "2031-01-17", "the day itself is not past")
        let passed = run(today: "2031-01-18")
        assertCutProjection(passed, .needsNewWeighIn)
        XCTAssertEqual(passed.projection.remainingKg, 0.2)
        assertCutProjection(run(today: "2031-01-26"), .needsNewWeighIn)
        assertCutProjection(run(today: "2031-01-27"), .weighInOverdue, "a week later the weigh-in itself is overdue")

        // Across the whole fixture, on every day from each weigh-in to the next: a projected day is
        // never before today, and a day is present exactly when the status is `projected`.
        for week in 1...F.weekCount {
            for offset in 0..<7 {
                let today = F.day(F.weighInDay(week), offset)
                let projection = evaluate(F.input(today: today)).projection
                XCTAssertEqual(projection.targetDay != nil, projection.status == .projected, today)
                if let targetDay = projection.targetDay {
                    XCTAssertGreaterThanOrEqual(targetDay, today, today)
                }
            }
        }
    }

    /// Fault F19, and variant V12. The comparison is `weeksRemaining > maxProjectionWeeks`.
    func testProjectionBeyondHorizonIsReported() {
        let v12 = evaluate(F.input(today: "2031-02-26", phase: F.phase(target: 80.0)))
        assertCutProjection(v12, .beyondHorizon)
        XCTAssertEqual(v12.projection.remainingKg, 17.2)

        // 2.0 kg at 0.5 kg per week is exactly 4 weeks.
        func run(target: Double, horizon: Int) -> CutScorecardResult {
            projecting(100.0, 99.5, target: target, parameters: F.params { $0.maxProjectionWeeks = horizon })
        }
        assertCutProjection(run(target: 97.5, horizon: 4), .projected, targetDay: "2031-02-12", "exactly at the horizon")
        assertCutProjection(run(target: 97.5, horizon: 3), .beyondHorizon)
        // 2.001 kg is 4.002 weeks.
        assertCutProjection(run(target: 97.499, horizon: 4), .beyondHorizon, "one quantum past the horizon")
        assertCutProjection(run(target: 97.499, horizon: 5), .projected, targetDay: "2031-02-13")
        XCTAssertEqual(run(target: 97.499, horizon: 4).projection.remainingKg, 2.001)
    }

    func testProjectionDateRoundsUpToWholeDays() {
        // 5.2 kg at 0.8 kg per week: 6.5 weeks, 45.5 days, so 46 days after 2031-01-15.
        let half = projecting(100.0, 99.2, target: 94.0)
        assertCutProjection(half, .projected, targetDay: "2031-03-02")
        XCTAssertEqual(half.projection.weeksRemaining ?? 0, 6.5, accuracy: 1e-9)
        XCTAssertEqual(half.projection.remainingKg, 5.2)
        // 2.0 kg at 0.5 kg per week: exactly 28 days. A whole number is not rounded further.
        assertCutProjection(projecting(100.0, 99.5, target: 97.5), .projected, targetDay: "2031-02-12")
        // 0.2 kg at 0.8: 1.75 days, so 2.
        assertCutProjection(projecting(100.0, 99.2, target: 99.0), .projected, targetDay: "2031-01-17")
        // 0.001 kg at 0.8: 0.00875 days, so 1.
        assertCutProjection(projecting(100.0, 99.2, target: 99.199), .projected, targetDay: "2031-01-16")
        // 0.001 kg at 20 kg per week: 0.00035 days, which quantizes to zero. At least one day.
        let tiny = projecting(120.0, 100.0, target: 99.999)
        assertCutRate(tiny, loss: 20.0, percent: 18.182)
        assertCutProjection(tiny, .projected, targetDay: "2031-01-16")
    }

    /// Fault F20. 2.1 / 0.3 x 7 is 49.00000000000001 in Double arithmetic; without quantizing before the
    /// ceiling the date is pushed to day 50. The mirror case, 0.7 / 0.1 x 7 = 48.99999999999999, must
    /// also land on day 49.
    func testProjectionOnExactWeekBoundaryIsNotPushedADayByFloatingPoint() {
        XCTAssertGreaterThan(2.1 / 0.3 * 7, 49, "the premise: the raw product is a hair above 49")
        let above = projecting(100.0, 99.7, target: 97.6)
        assertCutRate(above, loss: 0.3, percent: 0.3)
        XCTAssertEqual(above.projection.remainingKg, 2.1)
        assertCutProjection(above, .projected, targetDay: "2031-03-05")
        XCTAssertEqual(above.projection.weeksRemaining ?? 0, 7.0, accuracy: 1e-9)

        XCTAssertLessThan(0.7 / 0.1 * 7, 49, "the premise: the raw product is a hair below 49")
        let below = projecting(100.0, 99.9, target: 99.2)
        XCTAssertEqual(below.projection.remainingKg, 0.7)
        assertCutProjection(below, .projected, targetDay: "2031-03-05")
    }

    func testReachingTargetDoesNotChangeTheVerdict() {
        for (week, target) in [(19, 94.5), (9, 97.1), (15, 95.0), (4, 100.0)] {
            let open = evaluate(F.input(week: week))
            let reached = evaluate(F.input(today: F.weighInDay(week), phase: F.phase(target: target)))
            assertCutProjection(reached, .targetReached, "week \(week)")
            XCTAssertNotEqual(open.projection.status, .targetReached, "week \(week)")
            XCTAssertEqual(reached.verdict, open.verdict, "week \(week)")
            XCTAssertEqual(reached.rules, open.rules, "week \(week)")
            XCTAssertEqual(reached.signals, open.signals, "week \(week)")
            XCTAssertEqual(reached.rate, open.rate, "week \(week)")
        }
        assertCutVerdict(evaluate(F.input(today: F.weighInDay(19), phase: F.phase(target: 94.5))),
                         .addCalories, .ruleFired, rule: r2, kcal: 300, overridden: [r3])
    }

    /// Each status of §7.8 against the one that follows it in the order.
    func testProjectionStatusPrecedence() {
        // 1 before 2 and 3: no phase, or a phase not yet started, wins over an old weigh-in and over a
        // missing target.
        let old = F.make(weights: [F.weight(F.weighInDay(1), 100.0)], phase: nil, today: F.weighInDay(9))
        assertCutProjection(evaluate(old), .noActivePhase, "no phase")
        let notStarted = F.scenario(weights: [100.0, 99.2], phase: F.phase(startDay: "2031-06-02", target: nil))
        assertCutProjection(evaluate(notStarted), .noActivePhase, "phase not started")

        // 2 before 3 and 4: overdue wins over a missing target and over a target already reached.
        func overdue(target: Double?) -> CutScorecardResult {
            evaluate(F.scenario(weights: [100.0, 99.2], phase: F.phase(target: target), today: F.weighInDay(4)))
        }
        assertCutProjection(overdue(target: nil), .weighInOverdue, "overdue, no target")
        assertCutProjection(overdue(target: 99.5), .weighInOverdue, "overdue, target reached")

        // 3 before 4, 5 and 6 is `testNoTargetHasNoProjection`; 4 before 5 and 6 is
        // `testTargetAboveCurrentWeightIsReached`; 5 is `testProjectionWithUnknownRateIsRateUnknown`.

        // 7 before 9: 1.2 kg at 0.8 kg per week is 1.5 weeks, eleven days after 2031-01-15, so the day
        // would be 2031-01-26. On 2031-01-27 that day has passed. With a horizon of 1 week the horizon is
        // reported; with a horizon of 2 the passed day is.
        func late(horizon: Int) -> CutScorecardResult {
            projecting(100.0, 99.2, target: 98.0,
                       parameters: F.params { $0.maxProjectionWeeks = horizon; $0.maxWeighInAgeWeeks = 2 },
                       today: "2031-01-27")
        }
        assertCutProjection(late(horizon: 1), .beyondHorizon, "horizon before passed day")
        assertCutProjection(late(horizon: 2), .needsNewWeighIn, "passed day")
        // And one day earlier the day has not passed.
        assertCutProjection(projecting(100.0, 99.2, target: 98.0, today: "2031-01-26"), .projected, targetDay: "2031-01-26")
    }

    // MARK: - Week boundaries, in day-key space

    func testSundayAndMondayFallInDifferentWeeks() throws {
        // Sunday 2031-01-12 closes week 1; Monday 2031-01-13 opens week 2.
        let result = evaluate(F.make(weights: [F.weight("2031-01-12", 100.0), F.weight("2031-01-13", 99.2)],
                                     today: "2031-01-13"))
        XCTAssertEqual(result.weeks.map(\.weekStart), ["2031-01-06", "2031-01-13"])
        XCTAssertEqual(result.weeks.map(\.weightKg), [100.0, 99.2])
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, 0.8])
        XCTAssertEqual(try XCTUnwrap(result.rate).spanWeeks, 1)
        assertCutRate(result, loss: 0.8, percent: 0.803)

        // Monday and the following Sunday are one week, and the Sunday is its latest reading.
        let oneWeek = evaluate(F.make(weights: [F.weight("2031-01-06", 100.0), F.weight("2031-01-12", 99.2)],
                                      today: "2031-01-12"))
        XCTAssertEqual(oneWeek.weeks, [CutScorecardWeek(weekStart: "2031-01-06", weightKg: 99.2, weightDay: "2031-01-12",
                                                        waistCm: nil, waistDay: nil, inPhase: true, weeklyLossKg: nil)])
        assertCutNoRate(oneWeek, .singleReading)

        // `today` on a Sunday is still the week of the Monday before; the Monday after is a new week.
        XCTAssertEqual(evaluate(F.make(weights: [F.weight("2031-01-08", 100.0)], today: "2031-01-12")).weeks.count, 1)
        XCTAssertEqual(evaluate(F.make(weights: [F.weight("2031-01-08", 100.0)], today: "2031-01-13")).weeks.count, 2)

        let expected = ["2031-01-06": "2031-01-06", "2031-01-07": "2031-01-06", "2031-01-08": "2031-01-06",
                        "2031-01-09": "2031-01-06", "2031-01-10": "2031-01-06", "2031-01-11": "2031-01-06",
                        "2031-01-12": "2031-01-06", "2031-01-13": "2031-01-13"]
        for (day, monday) in expected {
            XCTAssertEqual(CutScorecard.weekStart(containing: day), monday, day)
        }
    }

    func testWeekSpanningAMonthAndAYearBoundary() {
        // Monday 2030-12-30 to Sunday 2031-01-05 is one week across the new year.
        for day in ["2030-12-30", "2030-12-31", "2031-01-01", "2031-01-05"] {
            XCTAssertEqual(CutScorecard.weekStart(containing: day), "2030-12-30", day)
        }
        XCTAssertEqual(CutScorecard.weekStart(containing: "2030-12-29"), "2030-12-23")
        XCTAssertEqual(CutScorecard.weekStart(containing: "2031-01-06"), "2031-01-06")

        let result = evaluate(F.make(weights: [F.weight("2030-12-24", 100.4), F.weight("2030-12-31", 100.0),
                                               F.weight("2031-01-04", 99.6), F.weight("2031-01-06", 99.2)],
                                     phase: F.phase(startDay: "2030-12-02"), today: "2031-01-06"))
        XCTAssertEqual(result.weeks.map(\.weekStart), ["2030-12-23", "2030-12-30", "2031-01-06"])
        XCTAssertEqual(result.weeks.map(\.weightKg), [100.4, 99.6, 99.2])
        XCTAssertEqual(result.weeks.map(\.weightDay), ["2030-12-24", "2031-01-04", "2031-01-06"])
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, 0.8, 0.4])
        XCTAssertEqual(result.rate?.spanWeeks, 2)
        XCTAssertEqual(result.evidenceStartDay, "2030-11-25", "six weeks before Monday 2031-01-06")
    }

    func testWeekContainingFebruaryTwentyNinth() {
        // 2028-02-29 is a Tuesday: the week runs Monday 2028-02-28 to Sunday 2028-03-05.
        for day in ["2028-02-28", "2028-02-29", "2028-03-01", "2028-03-05"] {
            XCTAssertEqual(CutScorecard.weekStart(containing: day), "2028-02-28", day)
        }
        XCTAssertEqual(CutScorecard.weekStart(containing: "2028-03-06"), "2028-03-06")
        // 2032-02-29 is a Sunday: it closes the week of Monday 2032-02-23.
        XCTAssertEqual(CutScorecard.weekStart(containing: "2032-02-29"), "2032-02-23")
        XCTAssertEqual(CutScorecard.weekStart(containing: "2032-03-01"), "2032-03-01")
        // 2031 is not a leap year and 2100 is not either.
        XCTAssertNil(CutScorecard.weekStart(containing: "2031-02-29"))
        XCTAssertNil(CutScorecard.weekStart(containing: "2100-02-29"))
        XCTAssertEqual(CutScorecard.weekStart(containing: "2000-02-29"), "2000-02-28")

        let press = F.pressName
        let result = evaluate(F.make(
            weights: [F.weight("2028-02-24", 100.0), F.weight("2028-02-29", 99.6), F.weight("2028-03-01", 99.2)],
            lifts: [CutScorecardLiftObservation(day: "2028-02-22", exercise: press, weightKg: 100),
                    CutScorecardLiftObservation(day: "2028-02-29", exercise: press, weightKg: 100)],
            phase: F.phase(startDay: "2028-02-07", target: 97.6), today: "2028-03-01"))
        XCTAssertEqual(result.weeks.map(\.weekStart), ["2028-02-21", "2028-02-28"])
        XCTAssertEqual(result.weeks.map(\.weightKg), [100.0, 99.2])
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, 0.8])
        // The seven days before Wednesday 2028-03-01 include the leap day.
        XCTAssertEqual(result.signals.lifts.reason, .holding)
        XCTAssertEqual(result.signals.lifts.windowStartDay, "2028-02-23")
        XCTAssertEqual(result.signals.lifts.windowEndDay, "2028-02-29")
        // 1.6 kg at 0.8 kg per week: 14 days after 2028-03-01.
        assertCutProjection(result, .projected, targetDay: "2028-03-15")

        // A projection that crosses the leap day: 4.0 kg at 0.8 is 35 days after 2028-02-10.
        let crossing = evaluate(F.make(weights: [F.weight("2028-02-03", 100.0), F.weight("2028-02-10", 99.2)],
                                       phase: F.phase(startDay: "2028-01-03", target: 95.2), today: "2028-02-10"))
        assertCutProjection(crossing, .projected, targetDay: "2028-03-16")
    }

    /// §12.7 item 3: day keys before 1970, where a naive integer division of a negative day count
    /// rounds the wrong way.
    func testWeeksBeforeTheEpoch() {
        XCTAssertEqual(CutScorecard.weekStart(containing: "1969-12-31"), "1969-12-29")
        XCTAssertEqual(CutScorecard.weekStart(containing: "1970-01-01"), "1969-12-29")
        XCTAssertEqual(CutScorecard.weekStart(containing: "1969-12-28"), "1969-12-22")
        XCTAssertEqual(CutScorecard.weekStart(containing: "1900-01-01"), "1900-01-01")

        let result = evaluate(F.make(weights: [F.weight("1969-12-10", 100.4), F.weight("1969-12-24", 100.0),
                                               F.weight("1969-12-31", 99.2)],
                                     phase: F.phase(startDay: "1969-12-01"), today: "1970-01-02"))
        XCTAssertEqual(result.weeks.map(\.weekStart), ["1969-12-08", "1969-12-15", "1969-12-22", "1969-12-29"])
        XCTAssertEqual(result.weeks.map(\.weeklyLossKg), [nil, nil, nil, 0.8])
        XCTAssertEqual(result.rate?.spanWeeks, 3)
        XCTAssertEqual(result.rate?.pointsUsed, 3)
        XCTAssertEqual(result.judgedWeekStart, "1969-12-29")
        XCTAssertEqual(result.evidenceStartDay, "1969-11-17")
    }

    func testWeekStartRejectsDaysThatAreNotCalendarDates() {
        for day in ["", "not-a-day", "2031-13-01", "2031-00-10", "2031-04-31", "2031-01-00", "2031-01-32"] {
            XCTAssertNil(CutScorecard.weekStart(containing: day), "\"\(day)\"")
        }
    }
}
