import Foundation
import WhoopStore
@testable import StrandAnalytics

// API ASSUMED BY THESE TESTS
//
// From the stage-2 implementation (docs/personal/superapp/specs/stage-2.md §6.2), every type with a
// public memberwise initialiser in declaration order:
//
//   enum CoachPacketSection: String, CaseIterable { case scorecard, weighIns = "weigh-ins",
//       recoverySleep = "recovery-sleep", trends, activity }
//   enum CoachPacketBodyKind: String { case weight, waist }
//   enum CoachPacketBodySource: String { case labBook = "lab-book", appleHealth = "apple-health", profile }
//   struct CoachPacketBodyReading { init(kind: CoachPacketBodyKind, value: Double,
//       source: CoachPacketBodySource, day: String?) }
//   struct CoachPacketPhase { init(name: String, startDay: String, targetWeightKg: Double?,
//       rateLowPercentPerWeek: Double, rateHighPercentPerWeek: Double) }
//   enum CoachPacketScorecard { case switchedOff
//       case evaluated(phase: CoachPacketPhase?, result: CutScorecardResult) }
//   struct CoachPacketBaseline { init(center: Double, typical: ClosedRange<Double>?, status: String,
//       nights: Int) }
//   enum CoachPacketStepSource: String { case strap, appleHealth = "apple-health",
//       strapEstimate = "strap-estimate" }
//   struct CoachPacketStepDay { init(day: String, steps: Double, source: CoachPacketStepSource) }
//   enum CoachPacketWorkoutSource: String { case whoop, appleHealth = "apple-health", detected, manual,
//       liftLog = "lift-log", activityFile = "activity-file" }
//   struct CoachPacketWorkout { init(day: String, startMinuteOfDay: Int, sport: String,
//       source: CoachPacketWorkoutSource, durationMinutes: Double?, avgHr: Int?, energyKcal: Double?,
//       distanceKm: Double?) }
//   struct CoachPacketInput { init(generatedAt: String, rangeStartDay: String, rangeEndDay: String,
//       sections: Set<CoachPacketSection>, days: [DailyMetric], strainFactor: Double,
//       scorecard: CoachPacketScorecard, body: [CoachPacketBodyReading],
//       hrvBaseline: CoachPacketBaseline?, restingHrBaseline: CoachPacketBaseline?,
//       steps: [CoachPacketStepDay], workouts: [CoachPacketWorkout]) }
//
// Existing API, already in the tree: `DailyMetric` (WhoopStore) through its public initialiser;
// `CutScorecardResult` and the types it is built from, and `CutScorecard.evaluate` (StrandAnalytics,
// stage 1); `CutScorecardFixture` (this test target, stage 1).

/// The synthetic coach-packet fixture of `docs/personal/superapp/specs/stage-2.md` §13.
///
/// Everything here is invented. It is the one Fixture Person of stage 1 §13, read on Sunday
/// 2031-03-16, plus the two weeks of daily rows, the two baselines, the steps and the workout summaries
/// stage 2 adds. No value was taken from a real person's data.
enum CoachPacketFixture {

    // MARK: - Clock, range and settings (§13.1)

    static let generatedAt = "2031-03-16T07:42:10+01:00"
    static let rangeStart = "2031-03-03"
    static let rangeEnd = "2031-03-16"
    static let strainFactor = 0.21

    /// The fourteen day keys of the fixture range, written out so no test depends on day arithmetic.
    static let rangeDays: [String] = [
        "2031-03-03", "2031-03-04", "2031-03-05", "2031-03-06", "2031-03-07", "2031-03-08",
        "2031-03-09", "2031-03-10", "2031-03-11", "2031-03-12", "2031-03-13", "2031-03-14",
        "2031-03-15", "2031-03-16",
    ]

    /// Every section of version 2 (packet v2, §7.12).
    static let allSections: Set<CoachPacketSection> = Set(CoachPacketSection.allCases)

    // MARK: - Daily rows (§13.2)

    /// One daily row. Only the fields the packet prints are set; every other column is nil.
    static func row(_ day: String, recovery: Double? = nil, strain: Double? = nil,
                    sleep: Double? = nil, deep: Double? = nil, rem: Double? = nil,
                    light: Double? = nil, eff: Double? = nil, hrv: Double? = nil, rhr: Int? = nil,
                    hrOnly: Bool? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: eff, deepMin: deep, remMin: rem,
                    lightMin: light, disturbances: nil, restingHr: rhr, avgHrv: hrv,
                    recovery: recovery, strain: strain, exerciseCount: nil, sleepHrOnly: hrOnly)
    }

    /// The thirteen rows of §13.2, oldest first. 2031-03-07 has no row.
    static let days: [DailyMetric] = [
        row("2031-03-03", recovery: 62, strain: 47, sleep: 444, deep: 78, rem: 102, light: 264,
            eff: 0.91, hrv: 58, rhr: 54),
        row("2031-03-04", recovery: 71, strain: 38, sleep: 462, deep: 84, rem: 108, light: 270,
            eff: 0.93, hrv: 63, rhr: 52),
        row("2031-03-05", recovery: 55, strain: 62, sleep: 402, deep: 66, rem: 90, light: 246,
            eff: 0.88, hrv: 52, rhr: 56),
        row("2031-03-06", recovery: 48, strain: 30, sleep: 378, deep: 60, rem: 84, light: 234,
            eff: 0.86, hrv: 47, rhr: 58),
        row("2031-03-08", recovery: 66, strain: 44, sleep: 450, deep: 81, rem: 105, light: 264,
            eff: 0.92, hrv: 60, rhr: 53),
        row("2031-03-09", recovery: 74, strain: 25, sleep: 480, deep: 90, rem: 114, light: 276,
            eff: 0.94, hrv: 66, rhr: 51),
        row("2031-03-10", recovery: 60, strain: 50, sleep: 432, deep: 75, rem: 99, light: 258,
            eff: 0.90, hrv: 57, rhr: 54),
        row("2031-03-11", recovery: 58, strain: 41, sleep: 420, hrv: 55, rhr: 55, hrOnly: true),
        row("2031-03-12", recovery: 64, strain: 58, sleep: 438, deep: 78, rem: 96, light: 264,
            eff: 0.91, hrv: 59, rhr: 54),
        row("2031-03-13", strain: 35),
        row("2031-03-14", recovery: 69, strain: 46, sleep: 456, deep: 84, rem: 102, light: 270,
            eff: 0.92, hrv: 62, rhr: 52),
        row("2031-03-15", recovery: 72, strain: 33, sleep: 468, deep: 87, rem: 108, light: 273,
            eff: 0.93, hrv: 64, rhr: 52),
        row("2031-03-16", recovery: 67, strain: 6, sleep: 450, deep: 81, rem: 102, light: 267,
            eff: 0.92, hrv: 61, rhr: 53),
    ]

    static let hrvBaseline = CoachPacketBaseline(center: 57.2, typical: 50.8...63.6,
                                                 status: "trusted", nights: 21)
    static let restingHrBaseline = CoachPacketBaseline(center: 54.1, typical: 51.9...56.3,
                                                       status: "trusted", nights: 21)

    // MARK: - Scorecard (§13.3)

    static let phase = CoachPacketPhase(name: "Fixture cut", startDay: "2031-01-06",
                                        targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                        rateHighPercentPerWeek: 1.20)

    /// One weekly point with a Wednesday reading, or an empty week when `weight` is nil.
    static func week(_ monday: String, _ weight: Double?, _ waist: Double?, on day: String?,
                     loss: Double?) -> CutScorecardWeek {
        CutScorecardWeek(weekStart: monday, weightKg: weight, weightDay: weight == nil ? nil : day,
                         waistCm: waist, waistDay: waist == nil ? nil : day, inPhase: true,
                         weeklyLossKg: loss)
    }

    /// Stage 1's ten weeks as they stand on 2031-03-16: nine Wednesday weigh-ins and the current week,
    /// which holds today and has no reading.
    static let weeks: [CutScorecardWeek] = [
        week("2031-01-06", 100.0, 100.0, on: "2031-01-08", loss: nil),
        week("2031-01-13", 99.2, 99.5, on: "2031-01-15", loss: 0.8),
        week("2031-01-20", 98.4, 99.0, on: "2031-01-22", loss: 0.8),
        week("2031-01-27", 97.6, 98.5, on: "2031-01-29", loss: 0.8),
        week("2031-02-03", 97.5, 98.0, on: "2031-02-05", loss: 0.1),
        week("2031-02-10", 97.4, 97.5, on: "2031-02-12", loss: 0.1),
        week("2031-02-17", 97.3, 97.0, on: "2031-02-19", loss: 0.1),
        week("2031-02-24", 97.2, 97.0, on: "2031-02-26", loss: 0.1),
        week("2031-03-03", 97.1, 97.0, on: "2031-03-05", loss: 0.1),
        week("2031-03-10", nil, nil, on: nil, loss: nil),
    ]

    static let rate = CutScorecardRate(lossKgPerWeek: 0.100, percentPerWeek: 0.103,
                                       referenceWeightKg: 97.3, pointsUsed: 5, spanWeeks: 4,
                                       firstWeekStart: "2031-02-03", lastWeekStart: "2031-03-03")

    static let projection = CutScorecardProjection(status: .projected, targetDay: "2031-10-08",
                                                   weeksRemaining: 31.0, remainingKg: 3.1)

    static let waistSignal = CutScorecardWaistSignal(state: .notMet, reason: .notShrinking,
                                                     currentCm: 97.0, referenceCm: 97.0,
                                                     referenceWeekStart: "2031-02-17", changeCm: 0.0)
    static let liftSignal = CutScorecardLiftSignal(state: .met, reason: .holding, commonExercises: 2,
                                                   dropped: 0, climbed: 0, held: 2,
                                                   windowStartDay: "2031-02-26",
                                                   windowEndDay: "2031-03-04")
    static let proteinSignal = CutScorecardProteinSignal(state: .unknown, reason: .noProteinData,
                                                         daysLogged: 0, daysAtOrAboveFloor: 0,
                                                         requiredDays: 5, floorGrams: 100)
    static let rateBandSignal = CutScorecardRateBandSignal(state: .notMet, reason: .belowBand,
                                                           percentPerWeek: 0.103,
                                                           lowPercentPerWeek: 0.40,
                                                           highPercentPerWeek: 1.20)

    static let rules: [CutScorecardRuleEvaluation] = [
        CutScorecardRuleEvaluation(rule: .liftsHoldingWaistShrinking, state: .notFired,
                                   unknownReason: nil, consecutiveWeeks: 0, requiredWeeks: 1),
        CutScorecardRuleEvaluation(rule: .liftsDropping, state: .notFired, unknownReason: nil,
                                   consecutiveWeeks: 0, requiredWeeks: 3),
        CutScorecardRuleEvaluation(rule: .slowLoss, state: .fired, unknownReason: nil,
                                   consecutiveWeeks: 5, requiredWeeks: 3),
    ]

    static let verdict = CutScorecardVerdict(kind: .reduceCarbs, reason: .ruleFired, rule: .slowLoss,
                                             calorieChangeKcal: -250, overriddenRules: [],
                                             unevaluatedRules: [])

    static let noRejections = CutScorecardRejections(nonFinite: 0, nonPositive: 0, invalidDay: 0,
                                                     future: 0)

    /// The hand-built result of §13.3 with any field replaced. A double optional lets a test pass
    /// `.some(nil)` to clear a field the fixture sets.
    static func result(weeks: [CutScorecardWeek] = CoachPacketFixture.weeks,
                       judgedWeekStart: String? = "2031-03-03",
                       rate: CutScorecardRate?? = nil,
                       rateUnavailable: CutScorecardRateUnavailable? = nil,
                       projection: CutScorecardProjection = CoachPacketFixture.projection,
                       waist: CutScorecardWaistSignal = CoachPacketFixture.waistSignal,
                       lifts: CutScorecardLiftSignal = CoachPacketFixture.liftSignal,
                       protein: CutScorecardProteinSignal = CoachPacketFixture.proteinSignal,
                       rateBand: CutScorecardRateBandSignal = CoachPacketFixture.rateBandSignal,
                       rules: [CutScorecardRuleEvaluation] = CoachPacketFixture.rules,
                       verdict: CutScorecardVerdict = CoachPacketFixture.verdict,
                       rejections: CutScorecardRejections = CoachPacketFixture.noRejections,
                       invalidInput: CutScorecardInvalidInput? = nil) -> CutScorecardResult {
        let fitted: CutScorecardRate? = rate ?? CoachPacketFixture.rate
        return CutScorecardResult(
            weeks: weeks, judgedWeekStart: judgedWeekStart, currentWeightKg: 97.1,
            currentWeightDay: "2031-03-05", rate: fitted, rateUnavailable: rateUnavailable,
            projection: projection,
            signals: CutScorecardSignals(waist: waist, lifts: lifts, protein: protein,
                                         rateBand: rateBand),
            rules: rules, verdict: verdict, evidenceStartDay: "2031-01-20", rejections: rejections,
            invalidInput: invalidInput)
    }

    /// A verdict with the fixture's kind and reason unless replaced.
    static func verdict(kind: CutScorecardVerdictKind = .reduceCarbs,
                        reason: CutScorecardVerdictReason = .ruleFired,
                        rule: CutScorecardRule? = nil, calories: Int? = nil,
                        overridden: [CutScorecardRule] = [],
                        unevaluated: [CutScorecardRule] = []) -> CutScorecardVerdict {
        CutScorecardVerdict(kind: kind, reason: reason, rule: rule, calorieChangeKcal: calories,
                            overriddenRules: overridden, unevaluatedRules: unevaluated)
    }

    /// What stage 1 returns for no readings and no phase on the fixture's day, with the fixture's
    /// parameters (protein floor 100 g): the scorecard of golden G2.
    static var emptyResult: CutScorecardResult {
        CutScorecard.evaluate(CutScorecardFixture.make(phase: nil, today: rangeEnd))
    }

    // MARK: - Body, steps and workouts (§13.3)

    static let body: [CoachPacketBodyReading] = [
        CoachPacketBodyReading(kind: .weight, value: 97.1, source: .labBook, day: "2031-03-05"),
        CoachPacketBodyReading(kind: .waist, value: 97.0, source: .labBook, day: "2031-03-05"),
    ]

    static func step(_ day: String, _ steps: Double,
                     _ source: CoachPacketStepSource = .appleHealth) -> CoachPacketStepDay {
        CoachPacketStepDay(day: day, steps: steps, source: source)
    }

    /// The thirteen step days of §7.9, oldest first. 2031-03-07 has no value.
    static let steps: [CoachPacketStepDay] = [
        step("2031-03-03", 9120), step("2031-03-04", 11240), step("2031-03-05", 8460),
        step("2031-03-06", 7300, .strapEstimate), step("2031-03-08", 12080),
        step("2031-03-09", 6540), step("2031-03-10", 9870), step("2031-03-11", 10310),
        step("2031-03-12", 8890), step("2031-03-13", 5200, .strapEstimate),
        step("2031-03-14", 9640), step("2031-03-15", 13020), step("2031-03-16", 1480),
    ]

    static func workout(_ day: String, _ hour: Int, _ minute: Int, _ sport: String,
                        _ source: CoachPacketWorkoutSource, min duration: Double? = nil,
                        hr: Int? = nil, kcal: Double? = nil, km: Double? = nil) -> CoachPacketWorkout {
        CoachPacketWorkout(day: day, startMinuteOfDay: hour * 60 + minute, sport: sport,
                           source: source, durationMinutes: duration, avgHr: hr, energyKcal: kcal,
                           distanceKm: km)
    }

    /// The five workout summaries of §7.9, oldest first.
    static let workouts: [CoachPacketWorkout] = [
        workout("2031-03-03", 18, 10, "strength", .liftLog, min: 62, hr: 108, kcal: 380),
        workout("2031-03-05", 7, 5, "cycling", .appleHealth, min: 45, hr: 132, kcal: 410, km: 18.4),
        workout("2031-03-08", 9, 30, "hiking", .manual, min: 95),
        workout("2031-03-10", 6, 50, "walking", .detected, min: 40, hr: 96, kcal: 170, km: 3.6),
        workout("2031-03-12", 18, 5, "rowing", .whoop, min: 30, hr: 128, kcal: 300),
    ]

    // MARK: - Identifiers for the privacy tests (§13.4)

    static let deviceId = "FIXTURE-STRAP-0001"
    static let nickname = "Fixture Band"
    static let peripheral = "00000000-0000-4000-8000-000000000001"
    static let account = "fixture.person@example.invalid"
    static let deviceName = "Fixture Phone"
    static let home = "/Users/fixture"

    static let identifiers: [String] = [deviceId, nickname, peripheral, account, deviceName, home]

    // MARK: - Inputs

    /// A packet input whose every field can be changed before it is built.
    struct Draft {
        var generatedAt = CoachPacketFixture.generatedAt
        var rangeStartDay = CoachPacketFixture.rangeStart
        var rangeEndDay = CoachPacketFixture.rangeEnd
        var sections = CoachPacketFixture.allSections
        var days = CoachPacketFixture.days
        var strainFactor = CoachPacketFixture.strainFactor
        var scorecard = CoachPacketScorecard.evaluated(phase: CoachPacketFixture.phase,
                                                       result: CoachPacketFixture.result())
        var body = CoachPacketFixture.body
        var hrvBaseline: CoachPacketBaseline? = CoachPacketFixture.hrvBaseline
        var restingHrBaseline: CoachPacketBaseline? = CoachPacketFixture.restingHrBaseline
        var steps = CoachPacketFixture.steps
        var workouts = CoachPacketFixture.workouts
        /// Packet v2: the Fixture Person logs no intake in the fixture range (stage 1 §13.2).
        var intake = CoachPacketIntake.days(CoachPacketV2Fixture.intakeSeries)
        /// Packet v2: stage 5's rows for the fixture range, private events left out.
        var events = CoachPacketV2Fixture.eventRows(from: CoachPacketFixture.rangeStart,
                                                    to: CoachPacketFixture.rangeEnd)

        var input: CoachPacketInput {
            CoachPacketInput(generatedAt: generatedAt, rangeStartDay: rangeStartDay,
                             rangeEndDay: rangeEndDay, sections: sections, days: days,
                             strainFactor: strainFactor, scorecard: scorecard, body: body,
                             hrvBaseline: hrvBaseline, restingHrBaseline: restingHrBaseline,
                             steps: steps, workouts: workouts, intake: intake, events: events)
        }

        /// The packet text for this draft.
        var text: String { CoachPacket.render(input) }

        /// Replace the scorecard with an evaluated result and, unless given, the fixture phase.
        mutating func setResult(_ result: CutScorecardResult,
                                phase: CoachPacketPhase? = CoachPacketFixture.phase) {
            scorecard = .evaluated(phase: phase, result: result)
        }
    }

    /// The full fixture with every section on: the input of golden G1.
    static var full: Draft { Draft() }

    /// The same clock and range with no data at all: the input of golden G2.
    static var empty: Draft {
        var draft = Draft()
        draft.days = []
        draft.scorecard = .evaluated(phase: nil, result: emptyResult)
        draft.body = []
        draft.hrvBaseline = nil
        draft.restingHrBaseline = nil
        draft.steps = []
        draft.workouts = []
        draft.intake = .days([])
        draft.events = CoachPacketV2Fixture.eventRows([], from: rangeStart, to: rangeEnd)
        return draft
    }

    /// The full fixture with one change.
    static func full(_ change: (inout Draft) -> Void) -> Draft {
        var draft = Draft()
        change(&draft)
        return draft
    }

    // MARK: - Reading a packet text

    /// The lines of a packet text without its final newline.
    static func lines(_ text: String) -> [String] {
        var body = text
        if body.hasSuffix("\n") { body.removeLast() }
        return body.components(separatedBy: "\n")
    }

    /// Line `index` of the text, or an empty string when the text is shorter, so a short packet fails
    /// an assertion instead of stopping the run.
    static func line(_ index: Int, of text: String) -> String {
        let all = lines(text)
        return index < all.count ? all[index] : ""
    }

    /// The lines under `heading`, up to the blank line that ends the section; nil when the heading is
    /// not in the text.
    static func section(_ heading: String, in text: String) -> [String]? {
        let all = lines(text)
        guard let start = all.firstIndex(of: heading) else { return nil }
        let rest = all[(start + 1)...]
        return Array(rest.prefix { !$0.isEmpty })
    }

    /// Every line of the text that begins with `prefix`.
    static func lines(startingWith prefix: String, in text: String) -> [String] {
        lines(text).filter { $0.hasPrefix(prefix) }
    }

    /// A deterministic generator (SplitMix64), so a generated-input test replays the same inputs on
    /// every run and on every machine.
    struct Generator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// A whole number in `range`.
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
        }

        /// A value in `range`, uniform over 2^53 steps.
        mutating func double(_ range: ClosedRange<Double>) -> Double {
            let unit = Double(next() >> 11) / Double(1 << 53)
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }

        /// True with probability `percent` in a hundred.
        mutating func chance(_ percent: Int) -> Bool { int(0...99) < percent }

        mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }

        /// A Fisher–Yates shuffle driven by this generator.
        mutating func shuffled<T>(_ items: [T]) -> [T] {
            var out = items
            guard out.count > 1 else { return out }
            for index in stride(from: out.count - 1, to: 0, by: -1) {
                out.swapAt(index, int(0...index))
            }
            return out
        }
    }
}
