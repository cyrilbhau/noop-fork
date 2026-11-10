import XCTest
@testable import StrandAnalytics

private typealias F = CutScorecardFixture

/// `CutScorecard.evaluate`: properties over generated inputs, `quantize`, and the raw values that reach
/// the coach packet in stage 2 (`docs/personal/superapp/specs/stage-1.md` §7.9, §12.1 "Properties").
///
/// Generated inputs come from the linear congruential generator written out below with a fixed seed.
/// Nothing here draws randomness from the system, so every run sees the same inputs.
final class CutScorecardPropertyTests: XCTestCase {

    /// A 64-bit linear congruential generator (Knuth's MMIX constants). Written out, not a library
    /// generator, so the same stream can be reproduced anywhere.
    private struct Generator {
        var state: UInt64
        /// A value in `0 ..< bound`.
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33) % bound
        }
    }

    /// One generated case: an input whose judged week is the week of `judgedMonday`.
    private struct Generated {
        var weights: [CutScorecardReading] = []
        var waists: [CutScorecardReading] = []
        var lifts: [CutScorecardLiftObservation] = []
        var proteinDays: [CutScorecardProteinDay] = []
        var phase: CutScorecardPhase?
        var parameters = F.parameters
        var today = ""
        /// The largest of the four window and count parameters (§7.9's `m`).
        var widest = 0

        var input: CutScorecardInput {
            CutScorecardInput(weights: weights, waists: waists, lifts: lifts, proteinDays: proteinDays,
                              phase: phase, parameters: parameters, today: today)
        }
    }

    private let judgedMonday = "2031-06-02"
    private let exercises = [F.pressName, F.rowName, "fixture press"]
    private let noRejections = CutScorecardRejections(nonFinite: 0, nonPositive: 0, invalidDay: 0, future: 0)

    /// A valid input with a weigh-in in the week of `judgedMonday` and `today` in that week or the next.
    ///
    /// Varies the four windows and counts, the protein floor, the phase (none, not started, started long
    /// ago, started inside the windows), the target, which weeks have a weigh-in or a waist reading,
    /// their days and values, lift coverage across three exercise names (two differ only by case) and
    /// protein logging. Weights and waists lie in the weeks `J - m … J`; lifts and protein lie on or
    /// after `evidenceStartDay`. That is the region where §7.9 and the rest of §7 agree (see
    /// `testReadingBeforeEvidenceStartDayNeverChangesAnythingButWeeks`).
    private func generate(_ g: inout Generator) -> Generated {
        var c = Generated()
        c.parameters.liftDropConsecutiveWeeks = 1 + g.next(4)
        c.parameters.slowLossConsecutiveWeeks = 1 + g.next(4)
        c.parameters.rateWindowWeeks = 1 + g.next(5)
        c.parameters.waistWindowWeeks = 1 + g.next(5)
        c.parameters.proteinFloorGrams = g.next(3) == 0 ? nil : 100
        let m = max(c.parameters.liftDropConsecutiveWeeks, c.parameters.slowLossConsecutiveWeeks,
                    c.parameters.rateWindowWeeks, c.parameters.waistWindowWeeks)
        c.widest = m
        let weighInOffset = g.next(7)
        c.today = F.day(judgedMonday, weighInOffset + g.next(8))

        let mode = g.next(8)
        if mode != 0 {
            let start: String
            if mode == 1 {
                start = F.day(c.today, 1 + g.next(5))                           // not started yet
            } else if mode <= 4 {
                start = F.day(judgedMonday, -7 * (m + 12) + g.next(7))          // started long ago
            } else {
                start = F.day(judgedMonday, -7 * g.next(m + 1))                 // started inside the windows
            }
            let target = g.next(3)
            c.phase = F.phase(startDay: start, target: target == 0 ? nil : (target == 1 ? 85.0 : 99.0),
                              low: 0.4, high: 1.2)
        }

        for k in 0...m where k == 0 || g.next(4) != 0 {
            let offset = k == 0 ? weighInOffset : g.next(7)
            let takenAt = 1_000 + g.next(100)
            let value = 90.0 + Double(g.next(4_001)) / 1_000.0
            c.weights.append(CutScorecardReading(day: F.day(judgedMonday, -7 * k + offset), takenAt: takenAt, value: value))
        }
        for k in 0...m where g.next(3) != 0 {
            let offset = k == 0 ? g.next(weighInOffset + 1) : g.next(7)
            let takenAt = 1_000 + g.next(100)
            let value = 80.0 + Double(g.next(3_001)) / 1_000.0
            c.waists.append(CutScorecardReading(day: F.day(judgedMonday, -7 * k + offset), takenAt: takenAt, value: value))
        }
        if g.next(4) != 0 {
            for k in 0...(m + 1) {
                for exercise in exercises where g.next(2) == 0 {
                    let offset = k == 0 ? g.next(weighInOffset + 1) : g.next(7)
                    let kg = 40.0 + 2.5 * Double(g.next(9))
                    c.lifts.append(CutScorecardLiftObservation(day: F.day(judgedMonday, -7 * k + offset),
                                                               exercise: exercise, weightKg: kg))
                }
            }
        }
        for d in 0...(7 * (m + 1)) where g.next(3) != 0 {
            c.proteinDays.append(CutScorecardProteinDay(day: F.day(c.today, -d), grams: 80.0 + 10.0 * Double(g.next(5))))
        }
        return c
    }

    /// Fisher-Yates with the same generator.
    private func shuffled<T>(_ items: [T], _ g: inout Generator) -> [T] {
        var out = items
        guard out.count > 1 else { return out }
        for i in stride(from: out.count - 1, to: 0, by: -1) {
            out.swapAt(i, g.next(i + 1))
        }
        return out
    }

    // MARK: - §7.9

    /// Items dated before `evidenceStartDay` change nothing in the result except `weeks`, which only
    /// grows at the front. 400 generated inputs, each extended with up to 13 older items.
    ///
    /// SPEC-AMBIGUITY: §7.9 is stated without exception, but four other statements of §7 let an item
    /// dated before `evidenceStartDay` change something else:
    ///   1. §7.4: a rate that is nil for `singleReading` becomes `gapLongerThanWindow` when any older
    ///      weight exists in the phase (`CutScorecardSeriesTests.testGapLongerThanWindowHasNoRate`).
    ///   2. §7.5: `noLiftData` becomes `noSessionsThisWeek` when any older lift observation exists
    ///      (`CutScorecardSignalTests.testLiftUnknownReasonPrecedence`).
    ///   3. §7.6: `consecutiveWeeks` has no upper bound, so with weigh-ins further back than `J - m` an
    ///      older reading or lift can lengthen or shorten a run that already spans the window
    ///      (`CutScorecardTests.testConsecutiveWeeksKeepsCountingPastTheRequiredWindow`).
    ///   4. §7.3: an older weight in the week just before the first week of `weeks` gives that first
    ///      week a `weeklyLossKg`, which is a change inside `weeks` other than its length.
    /// The property is tested where all of §7 agrees: base weights and waists lie in `J - m … J`
    /// (ruling out 3 and 4), older weights are not added when the base rate is `singleReading` (1), and
    /// older lifts are not added when the base has no lift observation (2). Without the last two guards
    /// a throwaway model of §7 fails 94 of these 400 cases.
    func testReadingBeforeEvidenceStartDayNeverChangesAnythingButWeeks() throws {
        var g = Generator(state: 0x5EED_C0DE_2031)
        var kinds = Set<CutScorecardVerdictKind>()
        var statuses = Set<CutScorecardProjectionStatus>()
        var olderItems = 0

        for index in 0..<400 {
            let base = generate(&g)
            let label = "case \(index)"
            let before = CutScorecard.evaluate(base.input)
            kinds.insert(before.verdict.kind)
            statuses.insert(before.projection.status)

            let evidenceStart = F.day(judgedMonday, -7 * (base.widest + 2))
            XCTAssertEqual(before.judgedWeekStart, judgedMonday, label)
            XCTAssertEqual(before.evidenceStartDay, evidenceStart, "\(label): J moved back 7 x (m + 2) days")
            XCTAssertEqual(before.rejections, noRejections, label)
            XCTAssertNil(before.invalidInput, label)

            // Older items: one to sixty days before `evidenceStartDay`, so the day just before it is
            // drawn often. The draws are made unconditionally so the stream does not depend on results.
            var older = Generated()
            for _ in 0..<g.next(4) {
                let day = F.day(evidenceStart, -1 - g.next(60))
                let takenAt = 1_000 + g.next(100)
                older.weights.append(CutScorecardReading(day: day, takenAt: takenAt,
                                                         value: 90.0 + Double(g.next(4_001)) / 1_000.0))
            }
            for _ in 0..<(1 + g.next(3)) {
                let day = F.day(evidenceStart, -1 - g.next(60))
                let takenAt = 1_000 + g.next(100)
                older.waists.append(CutScorecardReading(day: day, takenAt: takenAt,
                                                        value: 80.0 + Double(g.next(3_001)) / 1_000.0))
            }
            for _ in 0..<g.next(4) {
                let day = F.day(evidenceStart, -1 - g.next(60))
                let exercise = exercises[g.next(3)]
                older.lifts.append(CutScorecardLiftObservation(day: day, exercise: exercise,
                                                               weightKg: 40.0 + 2.5 * Double(g.next(9))))
            }
            for _ in 0..<g.next(4) {
                let day = F.day(evidenceStart, -1 - g.next(60))
                older.proteinDays.append(CutScorecardProteinDay(day: day, grams: 80.0 + 10.0 * Double(g.next(5))))
            }
            if before.rateUnavailable == .singleReading { older.weights = [] }      // contradiction 1
            if base.lifts.isEmpty { older.lifts = [] }                              // contradiction 2
            olderItems += older.weights.count + older.waists.count + older.lifts.count + older.proteinDays.count
            XCTAssertTrue((older.weights.map(\.day) + older.waists.map(\.day) + older.lifts.map(\.day)
                           + older.proteinDays.map(\.day)).allSatisfy { $0 < evidenceStart }, label)

            var extended = base
            extended.weights = older.weights + base.weights
            extended.waists = older.waists + base.waists
            extended.lifts = older.lifts + base.lifts
            extended.proteinDays = older.proteinDays + base.proteinDays
            let after = CutScorecard.evaluate(extended.input)

            XCTAssertGreaterThan(after.weeks.count, before.weeks.count, "\(label): `weeks` grows")
            XCTAssertEqual(Array(after.weeks.suffix(before.weeks.count)), before.weeks, "\(label): existing weeks")
            XCTAssertEqual(after.judgedWeekStart, before.judgedWeekStart, "\(label) judgedWeekStart")
            XCTAssertEqual(after.currentWeightKg, before.currentWeightKg, "\(label) currentWeightKg")
            XCTAssertEqual(after.currentWeightDay, before.currentWeightDay, "\(label) currentWeightDay")
            XCTAssertEqual(after.rate, before.rate, "\(label) rate")
            XCTAssertEqual(after.rateUnavailable, before.rateUnavailable, "\(label) rateUnavailable")
            XCTAssertEqual(after.projection, before.projection, "\(label) projection")
            XCTAssertEqual(after.signals, before.signals, "\(label) signals")
            XCTAssertEqual(after.rules, before.rules, "\(label) rules")
            XCTAssertEqual(after.verdict, before.verdict, "\(label) verdict")
            XCTAssertEqual(after.evidenceStartDay, before.evidenceStartDay, "\(label) evidenceStartDay")
            XCTAssertEqual(after.rejections, before.rejections, "\(label) rejections")
            XCTAssertEqual(after.invalidInput, before.invalidInput, "\(label) invalidInput")
        }

        // The generator is the one that was checked against a throwaway model of §7 when this test was
        // written: the same seed and the same draws end in the same state.
        XCTAssertEqual(g.state, 7_234_633_130_411_528_470, "the generator's draw sequence changed")
        // The inputs are not degenerate: every verdict kind and most projection statuses occur.
        XCTAssertEqual(kinds, [.holdSteady, .addCalories, .reduceCarbs, .insufficientData])
        XCTAssertTrue(statuses.isSuperset(of: [.projected, .noActivePhase, .noTarget, .targetReached,
                                               .rateUnknown, .notLosing]))
        XCTAssertGreaterThan(olderItems, 1_000)
    }

    /// The four parameters `evidenceStartDay` depends on, each in turn as the largest.
    func testEvidenceStartDayUsesTheLargestWindow() {
        func start(_ change: (inout CutScorecardParameters) -> Void) -> String? {
            CutScorecard.evaluate(F.scenario(weights: [100.0, 99.2], parameters: F.params(change))).evidenceStartDay
        }
        // The judged week is Monday 2031-01-13. Fixture: m = 4, so 42 days back.
        XCTAssertEqual(start { _ in }, "2030-12-02")
        XCTAssertEqual(start { $0.rateWindowWeeks = 6 }, F.day("2031-01-13", -56))
        XCTAssertEqual(start { $0.waistWindowWeeks = 7 }, F.day("2031-01-13", -63))
        XCTAssertEqual(start { $0.slowLossConsecutiveWeeks = 8 }, F.day("2031-01-13", -70))
        XCTAssertEqual(start { $0.liftDropConsecutiveWeeks = 9 }, F.day("2031-01-13", -77))
        // The smallest: every window and count at 1 gives m = 1 and 21 days.
        XCTAssertEqual(start {
            $0.rateWindowWeeks = 1; $0.waistWindowWeeks = 1
            $0.slowLossConsecutiveWeeks = 1; $0.liftDropConsecutiveWeeks = 1
        }, "2030-12-23")
        // It is anchored on the Monday of the judged week, not on the weigh-in day or on today.
        XCTAssertEqual(CutScorecard.evaluate(F.scenario(weights: [100.0, 99.2], today: "2031-01-26")).evidenceStartDay,
                       "2030-12-02")
    }

    // MARK: - Order and determinism

    /// The result does not depend on the order of the four input arrays (§6.3). The generated inputs
    /// hold one protein entry per day, the one stated exception.
    func testInputOrderDoesNotChangeTheResult() {
        var g = Generator(state: 0x0BDE_2031)
        for index in 0..<200 {
            let base = generate(&g)
            var mixed = base
            mixed.weights = shuffled(base.weights, &g)
            mixed.waists = shuffled(base.waists, &g)
            mixed.lifts = shuffled(base.lifts, &g)
            mixed.proteinDays = shuffled(base.proteinDays, &g)
            XCTAssertEqual(CutScorecard.evaluate(mixed.input), CutScorecard.evaluate(base.input), "case \(index)")
            var reversed = base
            reversed.weights.reverse()
            reversed.waists.reverse()
            reversed.lifts.reverse()
            reversed.proteinDays.reverse()
            XCTAssertEqual(CutScorecard.evaluate(reversed.input), CutScorecard.evaluate(base.input), "case \(index) reversed")
        }

        // The whole fixture, at every weigh-in, reversed and shuffled.
        for week in 1...F.weekCount {
            let input = F.input(week: week)
            let expected = CutScorecard.evaluate(input)
            let reversed = F.make(weights: input.weights.reversed(), waists: input.waists.reversed(),
                                  lifts: input.lifts.reversed(), proteinDays: input.proteinDays.reversed(),
                                  today: input.today)
            XCTAssertEqual(CutScorecard.evaluate(reversed), expected, "week \(week) reversed")
            let mixed = F.make(weights: shuffled(input.weights, &g), waists: shuffled(input.waists, &g),
                               lifts: shuffled(input.lifts, &g), proteinDays: shuffled(input.proteinDays, &g),
                               today: input.today)
            XCTAssertEqual(CutScorecard.evaluate(mixed), expected, "week \(week) shuffled")
        }
    }

    func testSameInputAndTodayGiveEqualResults() {
        for week in 1...F.weekCount {
            let input = F.input(week: week)
            let first = CutScorecard.evaluate(input)
            XCTAssertEqual(CutScorecard.evaluate(input), first, "week \(week), same value")
            // An equal input built separately.
            XCTAssertEqual(F.input(week: week), input)
            XCTAssertEqual(CutScorecard.evaluate(F.input(week: week)), first, "week \(week), equal value")
        }
        var g = Generator(state: 0xD17E_2031)
        for index in 0..<100 {
            let input = generate(&g).input
            XCTAssertEqual(CutScorecard.evaluate(input), CutScorecard.evaluate(input), "case \(index)")
        }
        // Nothing but the input decides the result: evaluating something else in between changes nothing.
        let before = CutScorecard.evaluate(F.input(week: 19))
        _ = CutScorecard.evaluate(F.input(week: 3))
        XCTAssertEqual(CutScorecard.evaluate(F.input(week: 19)), before)
    }

    // MARK: - quantize

    /// `quantize(x) = sign(x) x floor(|x| x 1000 + 0.5) / 1000` (§7.1). Halves go away from zero in both
    /// directions: not to even (Swift's `rounded()` default on some paths, Kotlin's `Math.rint`) and not
    /// toward positive infinity (Kotlin's `roundToLong`, `Math.round`).
    func testQuantizeRoundsHalvesAwayFromZero() {
        // Exact binary halves at the fourth decimal: x x 1000 is exactly n + 0.5.
        let halves: [(Double, Double)] = [
            (0.0625, 0.063),        // 62.5: to-even would give 0.062
            (0.1875, 0.188),
            (0.3125, 0.313),        // 312.5: to-even would give 0.312
            (0.4375, 0.438),
            (3.0625, 3.063),        // 3062.5: to-even would give 3.062
            (0.0005, 0.001),
            (0.0015, 0.002),
            (0.0025, 0.003),
            (1.2345, 1.235),
            (123_456.7895, 123_456.79),
        ]
        for (x, expected) in halves {
            XCTAssertEqual(CutScorecard.quantize(x), expected, "\(x)")
            // Negative halves go away from zero too: toward-positive-infinity would give one quantum less.
            XCTAssertEqual(CutScorecard.quantize(-x), -expected, "-\(x)")
        }

        let others: [(Double, Double)] = [
            (0, 0), (1, 1), (97.6, 97.6), (0.001, 0.001), (5e-324, 0),
            (0.0004, 0), (0.00049, 0), (1.2344, 1.234), (1.2346, 1.235),
            (-0.0004, 0), (-1.2344, -1.234), (-1.2346, -1.235), (-97.6, -97.6),
            (0.7999999999999972, 0.8),          // 100.0 - 99.2 in Double arithmetic
            (-0.7999999999999972, -0.8),
            (49.00000000000001, 49),            // the product of testProjectionOnExactWeekBoundary…
            (48.99999999999999, 49),
            // The expression, not decimal rounding: 16.0005 x 1000 is 16000.499999999998 in Double.
            (16.0005, 16.0),
            (2.0005, 2.001),                    // 2000.5000000000002
        ]
        for (x, expected) in others {
            XCTAssertEqual(CutScorecard.quantize(x), expected, "\(x)")
        }
        // Idempotent on its own output.
        for (_, expected) in halves + others {
            XCTAssertEqual(CutScorecard.quantize(expected), expected, "\(expected)")
        }
    }

    // MARK: - Stable names

    /// Every raw value, pinned. They reach the coach packet in stage 2, so renaming a case is a data
    /// change and must fail here first.
    func testEveryEnumRawValueIsStable() {
        func pin<E: RawRepresentable & Equatable>(_ pairs: [(E, String)], file: StaticString = #filePath,
                                                  line: UInt = #line) where E.RawValue == String {
            for (value, name) in pairs {
                XCTAssertEqual(value.rawValue, name, file: file, line: line)
                XCTAssertEqual(E(rawValue: name), value, file: file, line: line)
            }
            XCTAssertEqual(Set(pairs.map { $0.1 }).count, pairs.count, "raw values are distinct", file: file, line: line)
        }
        pin([(CutScorecardSignalState.met, "met"), (.notMet, "notMet"), (.unknown, "unknown")])
        pin([(CutScorecardRateUnavailable.noReadings, "noReadings"), (.singleReading, "singleReading"),
             (.gapLongerThanWindow, "gapLongerThanWindow"), (.weighInOverdue, "weighInOverdue")])
        pin([(CutScorecardProjectionStatus.projected, "projected"), (.noActivePhase, "noActivePhase"),
             (.noTarget, "noTarget"), (.targetReached, "targetReached"), (.rateUnknown, "rateUnknown"),
             (.notLosing, "notLosing"), (.beyondHorizon, "beyondHorizon"), (.needsNewWeighIn, "needsNewWeighIn"),
             (.weighInOverdue, "weighInOverdue")])
        pin([(CutScorecardWaistReason.shrinking, "shrinking"), (.notShrinking, "notShrinking"),
             (.noWaistThisWeek, "noWaistThisWeek"), (.noEarlierWaist, "noEarlierWaist"),
             (.weighInOverdue, "weighInOverdue"), (.noReadings, "noReadings")])
        pin([(CutScorecardLiftReason.holding, "holding"), (.dropping, "dropping"), (.noLiftData, "noLiftData"),
             (.noSessionsThisWeek, "noSessionsThisWeek"), (.noSessionsPriorWeek, "noSessionsPriorWeek"),
             (.noCommonExercises, "noCommonExercises"), (.weighInOverdue, "weighInOverdue"),
             (.noReadings, "noReadings")])
        pin([(CutScorecardProteinReason.floorMet, "floorMet"), (.floorMissed, "floorMissed"),
             (.noFloorConfigured, "noFloorConfigured"), (.noProteinData, "noProteinData"),
             (.incompleteLogging, "incompleteLogging"), (.weighInOverdue, "weighInOverdue"),
             (.noReadings, "noReadings")])
        pin([(CutScorecardRateBandReason.withinBand, "withinBand"), (.belowBand, "belowBand"),
             (.aboveBand, "aboveBand"), (.noActivePhase, "noActivePhase"), (.rateUnknown, "rateUnknown"),
             (.weighInOverdue, "weighInOverdue"), (.noReadings, "noReadings")])
        pin([(CutScorecardRule.liftsHoldingWaistShrinking, "liftsHoldingWaistShrinking"),
             (.liftsDropping, "liftsDropping"), (.slowLoss, "slowLoss")])
        pin([(CutScorecardRuleState.fired, "fired"), (.notFired, "notFired"), (.unknown, "unknown")])
        pin([(CutScorecardRuleUnknownReason.liftSignalUnknown, "liftSignalUnknown"),
             (.waistSignalUnknown, "waistSignalUnknown"), (.fewerWeeksThanWindow, "fewerWeeksThanWindow"),
             (.missedWeighIn, "missedWeighIn"), (.noActivePhase, "noActivePhase"),
             (.weighInOverdue, "weighInOverdue"), (.noReadings, "noReadings")])
        pin([(CutScorecardVerdictKind.holdSteady, "holdSteady"), (.addCalories, "addCalories"),
             (.reduceCarbs, "reduceCarbs"), (.insufficientData, "insufficientData")])
        pin([(CutScorecardVerdictReason.ruleFired, "ruleFired"), (.noChangeRuleFired, "noChangeRuleFired"),
             (.recompositionCheckIncomplete, "recompositionCheckIncomplete"), (.noRuleEvaluable, "noRuleEvaluable"),
             (.noReadings, "noReadings"), (.noActivePhase, "noActivePhase"), (.phaseNotStarted, "phaseNotStarted"),
             (.weighInOverdue, "weighInOverdue"), (.invalidInput, "invalidInput")])
        pin([(CutScorecardInvalidInput.parameters, "parameters"), (.phase, "phase"), (.today, "today")])

        // The rules are listed in precedence order, which `rules` and the verdict's rule lists rely on.
        XCTAssertEqual(CutScorecardRule.allCases, [.liftsHoldingWaistShrinking, .liftsDropping, .slowLoss])
    }

    /// §6.3: the generic defaults, as documented beside each field.
    func testGenericParametersMatchTheDocumentedDefaults() {
        let generic = CutScorecardParameters.generic
        XCTAssertEqual(generic.rateWindowWeeks, 4)
        XCTAssertEqual(generic.waistWindowWeeks, 4)
        XCTAssertEqual(generic.waistMinDecreaseCm, 0.1)
        XCTAssertEqual(generic.liftDropTolerancePercent, 2.5)
        XCTAssertEqual(generic.liftDropShare, 0.5)
        XCTAssertEqual(generic.liftDropConsecutiveWeeks, 3)
        XCTAssertEqual(generic.addCaloriesKcal, 100)
        XCTAssertEqual(generic.slowLossThresholdKgPerWeek, 0.25)
        XCTAssertEqual(generic.slowLossConsecutiveWeeks, 3)
        XCTAssertEqual(generic.reduceCarbsKcal, 100)
        XCTAssertNil(generic.proteinFloorGrams)
        XCTAssertEqual(generic.proteinMinDaysPerWeek, 5)
        XCTAssertEqual(generic.maxWeighInAgeWeeks, 1)
        XCTAssertEqual(generic.maxProjectionWeeks, 104)
        XCTAssertEqual(generic.targetToleranceKg, 0)
        XCTAssertEqual(CutScorecardParameters(), generic, "every initialiser argument defaults to the generic value")
        // The fixture differs from the generic defaults on purpose (§13.1).
        XCTAssertNotEqual(F.parameters, generic)
    }
}
