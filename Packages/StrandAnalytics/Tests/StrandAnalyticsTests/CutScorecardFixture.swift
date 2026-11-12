import XCTest
@testable import StrandAnalytics

/// The synthetic cut-scorecard fixture of `docs/personal/superapp/specs/stage-1.md` §13.
///
/// Everything here is invented. "Fixture Person" does not exist, the numbers are round on purpose, and no
/// value was taken from a real person's log. The fixture is one 22-week cut that visits every verdict line
/// in order; `expectedWeeks` holds the result the algorithm of §7 gives when `evaluate` is called with
/// `today` set to each weekly weigh-in day and only the data up to that day.
///
/// The expected table was recomputed from §7 with a throwaway model before it was written down here. It is
/// not the output of any implementation.
///
/// Later stages extend the fixture by adding data and builders to this file. The existing rows are a
/// contract: `CutScorecardTests.testFixtureVerdictSequence` asserts them exactly.
enum CutScorecardFixture {

    // MARK: - Day arithmetic (independent of the engine)

    /// Days since 1970-01-01 for a "yyyy-MM-dd" key, by the civil-calendar algorithm. Deliberately not the
    /// engine's own date code, so a fault there cannot hide behind the same fault here.
    static func dayNumber(_ day: String) -> Int {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        precondition(parts.count == 3, "fixture day key must be yyyy-MM-dd: \(day)")
        let y = parts[1] <= 2 ? parts[0] - 1 : parts[0]
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (parts[1] + 9) % 12
        let doy = (153 * mp + 2) / 5 + parts[2] - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// The "yyyy-MM-dd" key for a day number from `dayNumber`.
    static func dayKey(_ number: Int) -> String {
        let z = number + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// `base` moved by `offset` days (negative moves back).
    static func day(_ base: String, _ offset: Int) -> String {
        dayKey(dayNumber(base) + offset)
    }

    /// Epoch seconds at `hour`:00 UTC of `day`. The fixture weighs in at 07:00 UTC.
    static func epoch(_ day: String, hour: Int = 7) -> Int {
        dayNumber(day) * 86_400 + hour * 3_600
    }

    // MARK: - Fixture Person (§13.1)

    /// Monday of fixture week 1, the day the fixture phase starts.
    static let weekOneMonday = "2031-01-06"
    static let weekCount = 22

    /// The Monday of fixture week `week`. Weeks before week 1 are 0, -1, and so on.
    static func monday(_ week: Int) -> String { day(weekOneMonday, 7 * (week - 1)) }

    /// The Wednesday of fixture week `week`: the fixture's weigh-in day.
    static func weighInDay(_ week: Int) -> String { day(monday(week), 2) }

    static let pressName = "Fixture Press"
    static let rowName = "Fixture Row"

    static let phase = CutScorecardPhase(name: "Fixture cut", startDay: weekOneMonday,
                                         targetWeightKg: 94.0,
                                         rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)

    /// The fixture's parameters. Every field is set explicitly, and several differ from the generic
    /// defaults on purpose, so a passing test proves the parameter was read.
    static let parameters = CutScorecardParameters(
        rateWindowWeeks: 4, waistWindowWeeks: 2, waistMinDecreaseCm: 0.5,
        liftDropTolerancePercent: 5, liftDropShare: 0.5, liftDropConsecutiveWeeks: 3,
        addCaloriesKcal: 300, slowLossThresholdKgPerWeek: 0.4, slowLossConsecutiveWeeks: 3,
        reduceCarbsKcal: 250, proteinFloorGrams: 100, proteinMinDaysPerWeek: 5,
        maxWeighInAgeWeeks: 1, maxProjectionWeeks: 104, targetToleranceKg: 0)

    /// The fixture parameters with one or more fields changed.
    static func params(_ change: (inout CutScorecardParameters) -> Void) -> CutScorecardParameters {
        var p = parameters
        change(&p)
        return p
    }

    /// The fixture phase with fields replaced.
    static func phase(startDay: String = weekOneMonday, target: Double? = 94.0,
                      low: Double = 0.40, high: Double = 1.20) -> CutScorecardPhase {
        CutScorecardPhase(name: "Fixture cut", startDay: startDay, targetWeightKg: target,
                          rateLowPercentPerWeek: low, rateHighPercentPerWeek: high)
    }

    // MARK: - Weekly readings (§13.3)

    /// Weight (kg) at each Wednesday weigh-in, index 0 = week 1. nil = no weigh-in that week.
    static let weeklyWeightKg: [Double?] = [
        100.0, 99.2, 98.4, 97.6, 97.5, 97.4, 97.3, 97.2, 97.1, nil, 96.0,
        95.2, 95.1, 95.0, 94.9, 94.8, 94.7, 94.6, 94.5, 95.5, 94.0, 93.5,
    ]

    /// Waist (cm) taken with each weigh-in, index 0 = week 1.
    static let weeklyWaistCm: [Double?] = [
        100.0, 99.5, 99.0, 98.5, 98.0, 97.5, 97.0, 97.0, 97.0, nil, 96.5,
        96.0, 95.5, 95.0, 94.5, 94.5, 94.5, 94.5, 94.5, 94.5, 94.0, 93.5,
    ]

    /// The one extra reading: Monday of week 3. It must lose to Wednesday's 98.4.
    static let extraWeight = weight("2031-01-20", 98.9)

    // MARK: - Lifts and protein (§13.2)

    /// One session each Monday: (week, Fixture Press kg, Fixture Row kg). Weeks 10 to 15 have none.
    static let sessions: [(week: Int, pressKg: Double, rowKg: Double)] = [
        (-1, 60.0, 50.0), (0, 60.0, 50.0), (1, 60.0, 50.0), (2, 60.0, 50.0), (3, 60.0, 50.0),
        (4, 60.0, 50.0), (5, 62.5, 50.0), (6, 62.5, 50.0), (7, 62.5, 52.5), (8, 62.5, 52.5),
        (9, 62.5, 52.5), (16, 62.5, 52.5), (17, 57.5, 47.5), (18, 52.5, 42.5), (19, 47.5, 40.0),
        (20, 47.5, 40.0), (21, 47.5, 40.0), (22, 50.0, 40.0),
    ]

    /// Protein (g) for the seven days before the weigh-in of a week, oldest first. nil = not logged.
    static let proteinByWeek: [(week: Int, grams: [Double?])] = [
        (2, [120, 120, 120, 80, 120, 120, 120]),
        (3, [120, 120, 120, 80, 120, 120, 120]),
        (4, [120, 120, 120, 80, 120, 120, 120]),
        (5, [120, 80, 80, 120, 80, 80, 120]),
        (6, [120, nil, 120, nil, nil, 120, nil]),
    ]

    // MARK: - Builders

    /// A weight reading (kg) on `day`, taken at `hour`:00 UTC.
    static func weight(_ day: String, _ kg: Double, hour: Int = 7) -> CutScorecardReading {
        CutScorecardReading(day: day, takenAt: epoch(day, hour: hour), value: kg)
    }

    /// A waist reading (cm) on `day`, taken at `hour`:00 UTC.
    static func waist(_ day: String, _ cm: Double, hour: Int = 7) -> CutScorecardReading {
        CutScorecardReading(day: day, takenAt: epoch(day, hour: hour), value: cm)
    }

    /// One reading per week on the Wednesday, `values[0]` in `firstWeek`. nil leaves the week empty.
    static func weekly(_ values: [Double?], firstWeek: Int = 1) -> [CutScorecardReading] {
        values.enumerated().compactMap { index, value in
            value.map { weight(weighInDay(firstWeek + index), $0) }
        }
    }

    /// One Monday session in fixture week `week` with one working set per named exercise.
    static func session(week: Int, _ sets: [(String, Double)]) -> [CutScorecardLiftObservation] {
        sets.map { CutScorecardLiftObservation(day: monday(week), exercise: $0.0, weightKg: $0.1) }
    }

    /// Monday sessions of a single exercise, Fixture Press: (week, kg).
    static func pressSessions(_ byWeek: [(Int, Double)]) -> [CutScorecardLiftObservation] {
        byWeek.flatMap { session(week: $0.0, [(pressName, $0.1)]) }
    }

    /// Monday sessions at an unchanging 60.0 / 50.0 for every week in `weeks`: lifts that hold.
    static func holdingSessions(weeks: ClosedRange<Int>) -> [CutScorecardLiftObservation] {
        weeks.flatMap { session(week: $0, [(pressName, 60.0), (rowName, 50.0)]) }
    }

    /// Protein days for the seven days before `anchor`, oldest first (`anchor - 7` … `anchor - 1`).
    static func protein(before anchor: String, _ grams: [Double?]) -> [CutScorecardProteinDay] {
        precondition(grams.count == 7, "seven days, oldest first")
        return grams.enumerated().compactMap { index, value in
            value.map { CutScorecardProteinDay(day: day(anchor, index - 7), grams: $0) }
        }
    }

    // MARK: - The whole fixture

    static var allWeights: [CutScorecardReading] { weekly(weeklyWeightKg) + [extraWeight] }
    static var allWaists: [CutScorecardReading] { weekly(weeklyWaistCm) }

    /// Every fixture lift observation. `pressName` and `renameFromWeek` serve variant V11.
    static func allLifts(pressName name: String = pressName,
                         renameFromWeek: Int = Int.min) -> [CutScorecardLiftObservation] {
        sessions.flatMap { s in
            session(week: s.week, [(s.week >= renameFromWeek ? name : pressName, s.pressKg),
                                   (rowName, s.rowKg)])
        }
    }

    static var allProtein: [CutScorecardProteinDay] {
        proteinByWeek.flatMap { protein(before: weighInDay($0.week), $0.grams) }
    }

    /// An input with exactly the arrays given: nothing is filtered or defaulted to fixture data.
    static func make(weights: [CutScorecardReading] = [], waists: [CutScorecardReading] = [],
                     lifts: [CutScorecardLiftObservation] = [],
                     proteinDays: [CutScorecardProteinDay] = [],
                     phase: CutScorecardPhase? = CutScorecardFixture.phase,
                     parameters: CutScorecardParameters = CutScorecardFixture.parameters,
                     today: String) -> CutScorecardInput {
        CutScorecardInput(weights: weights, waists: waists, lifts: lifts, proteinDays: proteinDays,
                          phase: phase, parameters: parameters, today: today)
    }

    /// A scenario of one Wednesday reading per week from week 1. `today` defaults to the Wednesday of the
    /// last week in `weights`.
    static func scenario(weights: [Double?], waists: [Double?] = [],
                         lifts: [CutScorecardLiftObservation] = [],
                         proteinDays: [CutScorecardProteinDay] = [],
                         phase: CutScorecardPhase? = CutScorecardFixture.phase,
                         parameters: CutScorecardParameters = CutScorecardFixture.parameters,
                         today: String? = nil) -> CutScorecardInput {
        make(weights: weekly(weights), waists: weekly(waists), lifts: lifts, proteinDays: proteinDays,
             phase: phase, parameters: parameters, today: today ?? weighInDay(max(weights.count, 1)))
    }

    /// The fixture as it stood on `today`: every array cut to the items dated on or before that day, as
    /// §13.3 states. Pass replacement arrays to build a variant; they are cut the same way.
    static func input(today: String,
                      weights: [CutScorecardReading]? = nil,
                      waists: [CutScorecardReading]? = nil,
                      lifts: [CutScorecardLiftObservation]? = nil,
                      proteinDays: [CutScorecardProteinDay]? = nil,
                      phase: CutScorecardPhase? = CutScorecardFixture.phase,
                      parameters: CutScorecardParameters = CutScorecardFixture.parameters) -> CutScorecardInput {
        make(weights: (weights ?? allWeights).filter { $0.day <= today },
             waists: (waists ?? allWaists).filter { $0.day <= today },
             lifts: (lifts ?? allLifts()).filter { $0.day <= today },
             proteinDays: (proteinDays ?? allProtein).filter { $0.day <= today },
             phase: phase, parameters: parameters, today: today)
    }

    /// The fixture on the weigh-in day of `week`.
    static func input(week: Int) -> CutScorecardInput { input(today: weighInDay(week)) }

    // MARK: - Expected sequence (§13.3)

    /// One row of the §13.3 table, plus the protein and rate-band columns §13.3 gives in prose.
    struct ExpectedWeek {
        let week: Int
        let day: String
        let weightKg: Double?
        let waistCm: Double?
        let weeklyLossKg: Double?
        /// (lossKgPerWeek, percentPerWeek); nil when there is no rate.
        let rate: (loss: Double, percent: Double)?
        let rateUnavailable: CutScorecardRateUnavailable?
        let waistState: CutScorecardSignalState
        let waistChangeCm: Double?
        let liftState: CutScorecardSignalState
        let liftReason: CutScorecardLiftReason
        let proteinReason: CutScorecardProteinReason
        let rateBandReason: CutScorecardRateBandReason
        let ruleStates: [CutScorecardRuleState]
        let verdict: CutScorecardVerdict
        let projection: CutScorecardProjectionStatus
        let targetDay: String?
    }

    private static let r1 = CutScorecardRule.liftsHoldingWaistShrinking
    private static let r2 = CutScorecardRule.liftsDropping
    private static let r3 = CutScorecardRule.slowLoss

    /// "F" fired, "N" not fired, "U" unknown, in the order rule 1, rule 2, rule 3.
    static func ruleStates(_ code: String) -> [CutScorecardRuleState] {
        code.map { $0 == "F" ? .fired : ($0 == "N" ? .notFired : .unknown) }
    }

    private static func verdict(_ kind: CutScorecardVerdictKind, _ reason: CutScorecardVerdictReason,
                                rule: CutScorecardRule? = nil, kcal: Int? = nil,
                                overridden: [CutScorecardRule] = [],
                                unevaluated: [CutScorecardRule] = []) -> CutScorecardVerdict {
        CutScorecardVerdict(kind: kind, reason: reason, rule: rule, calorieChangeKcal: kcal,
                            overriddenRules: overridden, unevaluatedRules: unevaluated)
    }

    private static let holdByRuleOne = verdict(.holdSteady, .ruleFired, rule: r1)
    private static let holdByRuleOneOverSlowLoss = verdict(.holdSteady, .ruleFired, rule: r1, overridden: [r3])
    private static let reduce = verdict(.reduceCarbs, .ruleFired, rule: r3, kcal: -250)
    private static let reduceNamingRuleTwo = verdict(.reduceCarbs, .ruleFired, rule: r3, kcal: -250,
                                                     unevaluated: [r2])
    private static let withheld = verdict(.insufficientData, .recompositionCheckIncomplete,
                                          unevaluated: [r1, r2])

    private static func row(_ week: Int, _ weightKg: Double?, _ waistCm: Double?, loss: Double?,
                            rate: (Double, Double)?, unavailable: CutScorecardRateUnavailable? = nil,
                            waist: CutScorecardSignalState, change: Double?,
                            lift: CutScorecardSignalState, _ liftReason: CutScorecardLiftReason,
                            protein: CutScorecardProteinReason = .noProteinData,
                            band: CutScorecardRateBandReason,
                            rules: String, _ verdict: CutScorecardVerdict,
                            _ projection: CutScorecardProjectionStatus, _ targetDay: String? = nil) -> ExpectedWeek {
        ExpectedWeek(week: week, day: weighInDay(week), weightKg: weightKg, waistCm: waistCm,
                     weeklyLossKg: loss, rate: rate.map { (loss: $0.0, percent: $0.1) },
                     rateUnavailable: unavailable, waistState: waist, waistChangeCm: change,
                     liftState: lift, liftReason: liftReason, proteinReason: protein,
                     rateBandReason: band, ruleStates: ruleStates(rules), verdict: verdict,
                     projection: projection, targetDay: targetDay)
    }

    /// The 22 rows. Week 10 has no reading: its signals, rate, rules, verdict and projection are week 9's.
    static let expectedWeeks: [ExpectedWeek] = [
        row(1, 100.0, 100.0, loss: nil, rate: nil, unavailable: .singleReading,
            waist: .unknown, change: nil, lift: .met, .holding, band: .rateUnknown, rules: "UNU",
            verdict(.holdSteady, .noChangeRuleFired, unevaluated: [r1, r3]), .rateUnknown),
        row(2, 99.2, 99.5, loss: 0.8, rate: (0.8, 0.803), waist: .met, change: -0.5,
            lift: .met, .holding, protein: .floorMet, band: .withinBand, rules: "FNN",
            holdByRuleOne, .projected, "2031-03-02"),
        row(3, 98.4, 99.0, loss: 0.8, rate: (0.8, 0.806), waist: .met, change: -1.0,
            lift: .met, .holding, protein: .floorMet, band: .withinBand, rules: "FNN",
            holdByRuleOne, .projected, "2031-03-02"),
        row(4, 97.6, 98.5, loss: 0.8, rate: (0.8, 0.81), waist: .met, change: -1.0,
            lift: .met, .holding, protein: .floorMet, band: .withinBand, rules: "FNN",
            holdByRuleOne, .projected, "2031-03-02"),
        row(5, 97.5, 98.0, loss: 0.1, rate: (0.66, 0.67), waist: .met, change: -1.0,
            lift: .met, .holding, protein: .floorMissed, band: .withinBand, rules: "FNN",
            holdByRuleOne, .projected, "2031-03-15"),
        row(6, 97.4, 97.5, loss: 0.1, rate: (0.45, 0.459), waist: .met, change: -1.0,
            lift: .met, .holding, protein: .incompleteLogging, band: .withinBand, rules: "FNN",
            holdByRuleOne, .projected, "2031-04-06"),
        row(7, 97.3, 97.0, loss: 0.1, rate: (0.24, 0.246), waist: .met, change: -1.0,
            lift: .met, .holding, band: .belowBand, rules: "FNF",
            holdByRuleOneOverSlowLoss, .projected, "2031-05-27"),
        row(8, 97.2, 97.0, loss: 0.1, rate: (0.1, 0.103), waist: .met, change: -0.5,
            lift: .met, .holding, band: .belowBand, rules: "FNF",
            holdByRuleOneOverSlowLoss, .projected, "2031-10-08"),
        row(9, 97.1, 97.0, loss: 0.1, rate: (0.1, 0.103), waist: .notMet, change: 0.0,
            lift: .met, .holding, band: .belowBand, rules: "NNF", reduce, .projected, "2031-10-08"),
        row(10, nil, nil, loss: nil, rate: (0.1, 0.103), waist: .notMet, change: 0.0,
            lift: .met, .holding, band: .belowBand, rules: "NNF", reduce, .projected, "2031-10-08"),
        row(11, 96.0, 96.5, loss: nil, rate: (0.331, 0.342), waist: .met, change: -0.5,
            lift: .unknown, .noSessionsThisWeek, band: .belowBand, rules: "UNU",
            verdict(.holdSteady, .noChangeRuleFired, unevaluated: [r1, r3]), .projected, "2031-05-01"),
        row(12, 95.2, 96.0, loss: 0.8, rate: (0.51, 0.529), waist: .met, change: -0.5,
            lift: .unknown, .noSessionsThisWeek, band: .withinBand, rules: "UUN",
            verdict(.holdSteady, .noChangeRuleFired, unevaluated: [r1, r2]), .projected, "2031-04-12"),
        row(13, 95.1, 95.5, loss: 0.1, rate: (0.531, 0.554), waist: .met, change: -1.0,
            lift: .unknown, .noSessionsThisWeek, band: .withinBand, rules: "UUN",
            verdict(.holdSteady, .noChangeRuleFired, unevaluated: [r1, r2]), .projected, "2031-04-17"),
        row(14, 95.0, 95.0, loss: 0.1, rate: (0.31, 0.325), waist: .met, change: -1.0,
            lift: .unknown, .noSessionsThisWeek, band: .belowBand, rules: "UUN",
            verdict(.holdSteady, .noChangeRuleFired, unevaluated: [r1, r2]), .projected, "2031-05-02"),
        row(15, 94.9, 94.5, loss: 0.1, rate: (0.24, 0.252), waist: .met, change: -1.0,
            lift: .unknown, .noSessionsThisWeek, band: .belowBand, rules: "UUF",
            withheld, .projected, "2031-05-13"),
        row(16, 94.8, 94.5, loss: 0.1, rate: (0.1, 0.105), waist: .met, change: -0.5,
            lift: .unknown, .noSessionsPriorWeek, band: .belowBand, rules: "UUF",
            withheld, .projected, "2031-06-18"),
        row(17, 94.7, 94.5, loss: 0.1, rate: (0.1, 0.105), waist: .notMet, change: 0.0,
            lift: .notMet, .dropping, band: .belowBand, rules: "NUF",
            reduceNamingRuleTwo, .projected, "2031-06-18"),
        row(18, 94.6, 94.5, loss: 0.1, rate: (0.1, 0.105), waist: .notMet, change: 0.0,
            lift: .notMet, .dropping, band: .belowBand, rules: "NUF",
            reduceNamingRuleTwo, .projected, "2031-06-18"),
        row(19, 94.5, 94.5, loss: 0.1, rate: (0.1, 0.106), waist: .notMet, change: 0.0,
            lift: .notMet, .dropping, band: .belowBand, rules: "NFF",
            verdict(.addCalories, .ruleFired, rule: r2, kcal: 300, overridden: [r3]),
            .projected, "2031-06-18"),
        row(20, 95.5, 94.5, loss: -1.0, rate: (-0.12, -0.127), waist: .notMet, change: 0.0,
            lift: .met, .holding, band: .belowBand, rules: "NNF", reduce, .notLosing),
        row(21, 94.0, 94.0, loss: 1.5, rate: (0.05, 0.053), waist: .met, change: -0.5,
            lift: .met, .holding, band: .belowBand, rules: "FNN", holdByRuleOne, .targetReached),
        row(22, 93.5, 93.5, loss: 0.5, rate: (0.27, 0.286), waist: .met, change: -1.0,
            lift: .met, .holding, band: .belowBand, rules: "FNN", holdByRuleOne, .targetReached),
    ]
}

// MARK: - Shared assertions

extension CutScorecardResult {
    /// The rule evaluation at `index` in precedence order, or nil when `rules` is shorter. Tests read
    /// through this so a result of the wrong shape fails an assertion instead of trapping the run.
    func rule(_ index: Int) -> CutScorecardRuleEvaluation? {
        rules.indices.contains(index) ? rules[index] : nil
    }

    /// The week at `index`, or nil when `weeks` is shorter.
    func week(_ index: Int) -> CutScorecardWeek? {
        weeks.indices.contains(index) ? weeks[index] : nil
    }
}

/// Asserts the whole verdict, so a stray `rule`, calorie amount or rule list fails as well as a wrong kind.
func assertCutVerdict(_ result: CutScorecardResult, _ kind: CutScorecardVerdictKind,
                      _ reason: CutScorecardVerdictReason, rule: CutScorecardRule? = nil,
                      kcal: Int? = nil, overridden: [CutScorecardRule] = [],
                      unevaluated: [CutScorecardRule] = [], _ label: String = "",
                      file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(result.verdict,
                   CutScorecardVerdict(kind: kind, reason: reason, rule: rule, calorieChangeKcal: kcal,
                                       overriddenRules: overridden, unevaluatedRules: unevaluated),
                   label, file: file, line: line)
}

/// Asserts the three rule states in precedence order ("F" fired, "N" not fired, "U" unknown), that the
/// rules are listed in precedence order, and that a reason is present exactly on the unknown ones. Pass
/// `reasons` to pin the reasons too.
func assertCutRules(_ result: CutScorecardResult, _ code: String,
                    reasons: [CutScorecardRuleUnknownReason?]? = nil, _ label: String = "",
                    file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(result.rules.map(\.rule), CutScorecardRule.allCases, "\(label) rule order",
                   file: file, line: line)
    XCTAssertEqual(result.rules.map(\.state), CutScorecardFixture.ruleStates(code), "\(label) rule states",
                   file: file, line: line)
    for evaluation in result.rules {
        XCTAssertEqual(evaluation.unknownReason != nil, evaluation.state == .unknown,
                       "\(label) \(evaluation.rule): a reason is set exactly when the rule is unknown",
                       file: file, line: line)
    }
    if let reasons {
        XCTAssertEqual(result.rules.map(\.unknownReason), reasons, "\(label) rule reasons",
                       file: file, line: line)
    }
}

/// Asserts a rate's two reported numbers. Both are quantized by §7.4, so the comparison is exact.
func assertCutRate(_ result: CutScorecardResult, loss: Double, percent: Double, _ label: String = "",
                   file: StaticString = #filePath, line: UInt = #line) {
    guard let rate = result.rate else {
        return XCTFail("\(label) expected a rate, got \(String(describing: result.rateUnavailable))",
                       file: file, line: line)
    }
    XCTAssertEqual(rate.lossKgPerWeek, loss, "\(label) lossKgPerWeek", file: file, line: line)
    XCTAssertEqual(rate.percentPerWeek, percent, "\(label) percentPerWeek", file: file, line: line)
    XCTAssertNil(result.rateUnavailable, "\(label) rateUnavailable is set exactly when rate is nil",
                 file: file, line: line)
}

/// Asserts there is no rate, and why.
func assertCutNoRate(_ result: CutScorecardResult, _ reason: CutScorecardRateUnavailable,
                     _ label: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNil(result.rate, "\(label) rate", file: file, line: line)
    XCTAssertEqual(result.rateUnavailable, reason, "\(label) rateUnavailable", file: file, line: line)
}

/// Asserts the projection status, and that a day and a week count are present exactly when projected.
func assertCutProjection(_ result: CutScorecardResult, _ status: CutScorecardProjectionStatus,
                         targetDay: String? = nil, _ label: String = "",
                         file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(result.projection.status, status, "\(label) projection status", file: file, line: line)
    XCTAssertEqual(result.projection.targetDay, targetDay, "\(label) targetDay", file: file, line: line)
    XCTAssertEqual(result.projection.weeksRemaining != nil, status == .projected,
                   "\(label) weeksRemaining is set only when projected", file: file, line: line)
    XCTAssertEqual(result.projection.targetDay != nil, status == .projected,
                   "\(label) targetDay is set only when projected", file: file, line: line)
}
