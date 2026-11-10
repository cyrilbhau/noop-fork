import XCTest
@testable import StrandAnalytics

private typealias F = CutScorecardFixture

/// `CutScorecard.evaluate`: the rejection behaviour of `docs/personal/superapp/specs/stage-1.md` §6.5.
/// Items that are dropped and counted, and the three kinds of invalid input.
///
/// Every dropped item here has exactly one defect. §6.5 does not say which category counts an item with
/// two (a NaN value on an impossible day), so no test depends on it.
final class CutScorecardRejectionTests: XCTestCase {

    private let today = "2031-01-15"
    private let good = [F.weight("2031-01-08", 100.0), F.weight("2031-01-15", 99.2)]

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

    /// Asserts everything but `rejections` is what it was without the dropped items.
    private func assertSameApartFromRejections(_ result: CutScorecardResult, _ clean: CutScorecardResult,
                                               _ label: String = "", file: StaticString = #filePath,
                                               line: UInt = #line) {
        XCTAssertEqual(result.weeks, clean.weeks, "\(label) weeks", file: file, line: line)
        XCTAssertEqual(result.judgedWeekStart, clean.judgedWeekStart, "\(label) judgedWeekStart", file: file, line: line)
        XCTAssertEqual(result.currentWeightKg, clean.currentWeightKg, "\(label) currentWeightKg", file: file, line: line)
        XCTAssertEqual(result.currentWeightDay, clean.currentWeightDay, "\(label) currentWeightDay", file: file, line: line)
        XCTAssertEqual(result.rate, clean.rate, "\(label) rate", file: file, line: line)
        XCTAssertEqual(result.rateUnavailable, clean.rateUnavailable, "\(label) rateUnavailable", file: file, line: line)
        XCTAssertEqual(result.projection, clean.projection, "\(label) projection", file: file, line: line)
        XCTAssertEqual(result.signals, clean.signals, "\(label) signals", file: file, line: line)
        XCTAssertEqual(result.rules, clean.rules, "\(label) rules", file: file, line: line)
        XCTAssertEqual(result.verdict, clean.verdict, "\(label) verdict", file: file, line: line)
        XCTAssertEqual(result.evidenceStartDay, clean.evidenceStartDay, "\(label) evidenceStartDay", file: file, line: line)
        XCTAssertNil(result.invalidInput, "\(label): dropping an item does not make the input invalid", file: file, line: line)
    }

    // MARK: - Dropped and counted

    func testNonFiniteWeightIsDroppedAndCounted() {
        let clean = evaluate(F.make(weights: good, today: today))
        let bad = [F.weight("2031-01-14", .nan), F.weight("2031-01-15", .infinity), F.weight("2031-01-15", -.infinity)]
        let result = evaluate(F.make(weights: bad + good + bad, today: today))
        XCTAssertEqual(result.rejections, rejections(6))
        assertSameApartFromRejections(result, clean)
        XCTAssertEqual(result.currentWeightKg, 99.2)

        // The same category counts waist readings, lift observations and protein days.
        let others = evaluate(F.make(weights: good,
                                     waists: [F.waist("2031-01-15", .nan)],
                                     lifts: [lift("2031-01-13", F.pressName, .infinity)],
                                     proteinDays: [CutScorecardProteinDay(day: "2031-01-14", grams: .nan)],
                                     today: today))
        XCTAssertEqual(others.rejections, rejections(3))
        assertSameApartFromRejections(others, clean)
        XCTAssertNil(others.weeks.last?.waistCm)
        XCTAssertEqual(others.signals.lifts.reason, .noLiftData)
    }

    func testNegativeAndZeroWeightAreDroppedAndCounted() {
        let clean = evaluate(F.make(weights: good, today: today))
        let result = evaluate(F.make(weights: good + [F.weight("2031-01-15", 0), F.weight("2031-01-15", -5.0)],
                                     today: today))
        XCTAssertEqual(result.rejections, rejections(0, 2))
        assertSameApartFromRejections(result, clean)

        let others = evaluate(F.make(weights: good,
                                     waists: [F.waist("2031-01-15", 0), F.waist("2031-01-15", -80)],
                                     lifts: [lift("2031-01-13", F.pressName, 0), lift("2031-01-13", F.pressName, -60)],
                                     proteinDays: [CutScorecardProteinDay(day: "2031-01-14", grams: -1)],
                                     today: today))
        XCTAssertEqual(others.rejections, rejections(0, 5))
        assertSameApartFromRejections(others, clean)

        // A protein total of exactly zero is valid: it is a logged day, not a rejection.
        let zeroProtein = evaluate(F.make(weights: good,
                                          proteinDays: [CutScorecardProteinDay(day: "2031-01-14", grams: 0)],
                                          today: today))
        XCTAssertEqual(zeroProtein.rejections, rejections())
        XCTAssertEqual(zeroProtein.signals.protein.daysLogged, 1)
        // The smallest positive weight is not "zero or negative".
        XCTAssertEqual(evaluate(F.make(weights: good + [F.weight("2031-01-09", 0.001)], today: today)).rejections,
                       rejections())
    }

    func testInvalidDayIsDroppedAndCounted() {
        let clean = evaluate(F.make(weights: good, today: today))
        let days = ["2031-02-30", "2031-13-01", "2030-02-29", "", "not-a-day", "2031-01-00"]
        let result = evaluate(F.make(weights: good + days.map { CutScorecardReading(day: $0, takenAt: 0, value: 90.0) },
                                     today: today))
        XCTAssertEqual(result.rejections, rejections(0, 0, 6))
        assertSameApartFromRejections(result, clean)

        let others = evaluate(F.make(weights: good,
                                     waists: [CutScorecardReading(day: "2031-02-31", takenAt: 0, value: 90.0)],
                                     lifts: [lift("2031-04-31", F.pressName, 60)],
                                     proteinDays: [CutScorecardProteinDay(day: "yesterday", grams: 120)],
                                     today: today))
        XCTAssertEqual(others.rejections, rejections(0, 0, 3))
        assertSameApartFromRejections(others, clean)

        // A lift observation with an empty exercise name counts here too.
        let unnamed = evaluate(F.make(weights: good, lifts: [lift("2031-01-13", "", 60)], today: today))
        XCTAssertEqual(unnamed.rejections, rejections(0, 0, 1))
        XCTAssertEqual(unnamed.signals.lifts.reason, .noLiftData)
        // A name of one space is a name: compared byte for byte, never trimmed.
        let space = evaluate(F.make(weights: good, lifts: [lift("2031-01-13", " ", 60)], today: today))
        XCTAssertEqual(space.rejections, rejections())
        XCTAssertEqual(space.signals.lifts.reason, .noSessionsPriorWeek)
    }

    func testFutureReadingIsIgnoredAndCounted() {
        let clean = evaluate(F.make(weights: good, today: today))
        let result = evaluate(F.make(weights: good + [F.weight("2031-01-16", 95.0), F.weight("2031-06-01", 90.0)],
                                     today: today))
        XCTAssertEqual(result.rejections, rejections(0, 0, 0, 2))
        assertSameApartFromRejections(result, clean)
        XCTAssertEqual(result.currentWeightKg, 99.2, "a future reading is not the current weight")
        XCTAssertEqual(result.weeks.count, 2, "and it does not extend `weeks` past today")

        let others = evaluate(F.make(weights: good,
                                     waists: [F.waist("2031-01-16", 90.0)],
                                     lifts: [lift("2031-01-16", F.pressName, 60)],
                                     proteinDays: [CutScorecardProteinDay(day: "2031-01-16", grams: 120)],
                                     today: today))
        XCTAssertEqual(others.rejections, rejections(0, 0, 0, 3))
        assertSameApartFromRejections(others, clean)

        // "After today" is strict: a reading dated today is valid, whatever its instant.
        let late = CutScorecardReading(day: today, takenAt: F.epoch(today, hour: 23), value: 99.0)
        let sameDay = evaluate(F.make(weights: good + [late], today: today))
        XCTAssertEqual(sameDay.rejections, rejections())
        XCTAssertEqual(sameDay.currentWeightKg, 99.0)
    }

    /// One item of every category in every array, against fixture week 9, a week where each of the
    /// signals and all three rules have something to say. Variant V9 is the two-item form of this.
    func testDroppedReadingsLeaveTheResultUnchanged() {
        let day = F.weighInDay(9)
        let base = F.input(week: 9)
        let clean = evaluate(base)
        XCTAssertEqual(clean.rejections, rejections())

        let junkReadings = [F.weight("2031-03-04", .nan), F.weight("2031-03-04", -1), F.weight("2031-02-30", 90.0),
                            F.weight("2031-03-06", 90.0)]
        let junkLifts = [lift("2031-03-03", F.pressName, .infinity), lift("2031-03-03", F.pressName, 0),
                         lift("2031-03-03", "", 500), lift("2031-03-06", F.pressName, 500)]
        let junkProtein = [CutScorecardProteinDay(day: "2031-03-04", grams: .nan),
                           CutScorecardProteinDay(day: "2031-03-04", grams: -1),
                           CutScorecardProteinDay(day: "", grams: 200),
                           CutScorecardProteinDay(day: "2031-03-06", grams: 200)]
        let result = evaluate(F.make(weights: junkReadings + base.weights, waists: base.waists + junkReadings,
                                     lifts: junkLifts + base.lifts, proteinDays: base.proteinDays + junkProtein,
                                     today: day))
        XCTAssertEqual(result.rejections, rejections(4, 4, 4, 4))
        assertSameApartFromRejections(result, clean)
        assertCutVerdict(result, .reduceCarbs, .ruleFired, rule: .slowLoss, kcal: -250)
    }

    // MARK: - Invalid input

    /// Asserts the invalid result of §6.5 field by field. The input is fixture week 9 plus one droppable
    /// reading, so an implementation that carries on past an invalid input shows up in every assertion,
    /// and "zero rejections" is tested against an input that has something to reject.
    private func assertInvalid(_ kind: CutScorecardInvalidInput,
                               phase: CutScorecardPhase? = F.phase,
                               parameters: CutScorecardParameters = F.parameters,
                               today: String = F.weighInDay(9), _ label: String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
        let base = F.input(week: 9)
        let result = evaluate(F.make(weights: base.weights + [F.weight("2031-03-04", .nan)], waists: base.waists,
                                     lifts: base.lifts, proteinDays: base.proteinDays, phase: phase,
                                     parameters: parameters, today: today))
        XCTAssertEqual(result.invalidInput, kind, label, file: file, line: line)
        XCTAssertEqual(result.weeks, [], "\(label) weeks", file: file, line: line)
        XCTAssertNil(result.judgedWeekStart, "\(label) judgedWeekStart", file: file, line: line)
        XCTAssertNil(result.evidenceStartDay, "\(label) evidenceStartDay", file: file, line: line)
        XCTAssertNil(result.rate, "\(label) rate", file: file, line: line)
        XCTAssertEqual(result.rateUnavailable, .noReadings, "\(label) rateUnavailable", file: file, line: line)
        XCTAssertEqual(result.projection, CutScorecardProjection(status: .noActivePhase, targetDay: nil,
                                                                 weeksRemaining: nil, remainingKg: nil),
                       "\(label) projection", file: file, line: line)
        XCTAssertEqual(result.signals.waist.state, .unknown, "\(label) waist", file: file, line: line)
        XCTAssertEqual(result.signals.waist.reason, .noReadings, "\(label) waist", file: file, line: line)
        XCTAssertEqual(result.signals.lifts.state, .unknown, "\(label) lifts", file: file, line: line)
        XCTAssertEqual(result.signals.lifts.reason, .noReadings, "\(label) lifts", file: file, line: line)
        XCTAssertEqual(result.signals.protein.state, .unknown, "\(label) protein", file: file, line: line)
        XCTAssertEqual(result.signals.protein.reason, .noReadings, "\(label) protein", file: file, line: line)
        XCTAssertEqual(result.signals.rateBand.state, .unknown, "\(label) rate band", file: file, line: line)
        XCTAssertEqual(result.signals.rateBand.reason, .noReadings, "\(label) rate band", file: file, line: line)
        assertCutRules(result, "UUU", reasons: [.noReadings, .noReadings, .noReadings], label, file: file, line: line)
        assertCutVerdict(result, .insufficientData, .invalidInput, label, file: file, line: line)
        XCTAssertEqual(result.rejections, rejections(), "\(label) rejections", file: file, line: line)
    }

    /// The same input with nothing wrong is valid: the control for every invalid case below.
    private func assertValid(phase: CutScorecardPhase? = F.phase,
                             parameters: CutScorecardParameters = F.parameters, _ label: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        let base = F.input(week: 9)
        let result = evaluate(F.make(weights: base.weights, waists: base.waists, lifts: base.lifts,
                                     proteinDays: base.proteinDays, phase: phase, parameters: parameters,
                                     today: base.today))
        XCTAssertNil(result.invalidInput, label, file: file, line: line)
        XCTAssertNotEqual(result.verdict.reason, .invalidInput, label, file: file, line: line)
        XCTAssertEqual(result.weeks.count, 9, label, file: file, line: line)
    }

    func testNonFiniteParameterIsInvalidInput() {
        for bad in [Double.nan, .infinity, -.infinity] {
            assertInvalid(.parameters, parameters: F.params { $0.waistMinDecreaseCm = bad }, "waistMinDecreaseCm \(bad)")
            assertInvalid(.parameters, parameters: F.params { $0.liftDropTolerancePercent = bad }, "liftDropTolerancePercent \(bad)")
            assertInvalid(.parameters, parameters: F.params { $0.liftDropShare = bad }, "liftDropShare \(bad)")
            assertInvalid(.parameters, parameters: F.params { $0.slowLossThresholdKgPerWeek = bad }, "slowLossThresholdKgPerWeek \(bad)")
            assertInvalid(.parameters, parameters: F.params { $0.proteinFloorGrams = bad }, "proteinFloorGrams \(bad)")
            assertInvalid(.parameters, parameters: F.params { $0.targetToleranceKg = bad }, "targetToleranceKg \(bad)")
        }
        assertValid()
    }

    func testZeroWindowIsInvalidInput() {
        for bad in [0, -1] {
            assertInvalid(.parameters, parameters: F.params { $0.rateWindowWeeks = bad }, "rateWindowWeeks \(bad)")
            assertInvalid(.parameters, parameters: F.params { $0.waistWindowWeeks = bad }, "waistWindowWeeks \(bad)")
            assertInvalid(.parameters, parameters: F.params { $0.liftDropConsecutiveWeeks = bad }, "liftDropConsecutiveWeeks \(bad)")
            assertInvalid(.parameters, parameters: F.params { $0.slowLossConsecutiveWeeks = bad }, "slowLossConsecutiveWeeks \(bad)")
        }
        // One is the smallest valid window and count.
        assertValid(parameters: F.params {
            $0.rateWindowWeeks = 1; $0.waistWindowWeeks = 1
            $0.liftDropConsecutiveWeeks = 1; $0.slowLossConsecutiveWeeks = 1
        }, "every window and count at 1")
    }

    /// The remaining parameter rules of §6.5, each with its nearest valid neighbour.
    func testOutOfRangeParameterIsInvalidInput() {
        // maxWeighInAgeWeeks below 0.
        assertInvalid(.parameters, parameters: F.params { $0.maxWeighInAgeWeeks = -1 }, "maxWeighInAgeWeeks -1")
        assertValid(parameters: F.params { $0.maxWeighInAgeWeeks = 0 }, "maxWeighInAgeWeeks 0")
        // maxProjectionWeeks below 1.
        assertInvalid(.parameters, parameters: F.params { $0.maxProjectionWeeks = 0 }, "maxProjectionWeeks 0")
        assertValid(parameters: F.params { $0.maxProjectionWeeks = 1 }, "maxProjectionWeeks 1")
        // liftDropTolerancePercent outside 0 ..< 100.
        assertInvalid(.parameters, parameters: F.params { $0.liftDropTolerancePercent = -0.001 }, "tolerance -0.001")
        assertInvalid(.parameters, parameters: F.params { $0.liftDropTolerancePercent = 100 }, "tolerance 100")
        assertValid(parameters: F.params { $0.liftDropTolerancePercent = 0 }, "tolerance 0")
        assertValid(parameters: F.params { $0.liftDropTolerancePercent = 99.999 }, "tolerance 99.999")
        // liftDropShare outside 0 < share <= 1.
        assertInvalid(.parameters, parameters: F.params { $0.liftDropShare = 0 }, "share 0")
        assertInvalid(.parameters, parameters: F.params { $0.liftDropShare = -0.5 }, "share -0.5")
        assertInvalid(.parameters, parameters: F.params { $0.liftDropShare = 1.001 }, "share 1.001")
        assertValid(parameters: F.params { $0.liftDropShare = 0.001 }, "share 0.001")
        assertValid(parameters: F.params { $0.liftDropShare = 1 }, "share 1")
        // Negative amounts and thresholds; zero is valid for each.
        assertInvalid(.parameters, parameters: F.params { $0.waistMinDecreaseCm = -0.001 }, "waistMinDecreaseCm")
        assertInvalid(.parameters, parameters: F.params { $0.slowLossThresholdKgPerWeek = -0.001 }, "slowLossThresholdKgPerWeek")
        assertInvalid(.parameters, parameters: F.params { $0.targetToleranceKg = -0.001 }, "targetToleranceKg")
        assertInvalid(.parameters, parameters: F.params { $0.addCaloriesKcal = -1 }, "addCaloriesKcal")
        assertInvalid(.parameters, parameters: F.params { $0.reduceCarbsKcal = -1 }, "reduceCarbsKcal")
        assertValid(parameters: F.params {
            $0.waistMinDecreaseCm = 0; $0.slowLossThresholdKgPerWeek = 0; $0.targetToleranceKg = 0
            $0.addCaloriesKcal = 0; $0.reduceCarbsKcal = 0
        }, "every amount and threshold at 0")
        // proteinMinDaysPerWeek outside 1…7.
        assertInvalid(.parameters, parameters: F.params { $0.proteinMinDaysPerWeek = 0 }, "proteinMinDaysPerWeek 0")
        assertInvalid(.parameters, parameters: F.params { $0.proteinMinDaysPerWeek = 8 }, "proteinMinDaysPerWeek 8")
        assertValid(parameters: F.params { $0.proteinMinDaysPerWeek = 1 }, "proteinMinDaysPerWeek 1")
        assertValid(parameters: F.params { $0.proteinMinDaysPerWeek = 7 }, "proteinMinDaysPerWeek 7")
        // proteinFloorGrams set and not positive; nil and the smallest positive are valid.
        assertInvalid(.parameters, parameters: F.params { $0.proteinFloorGrams = 0 }, "proteinFloorGrams 0")
        assertInvalid(.parameters, parameters: F.params { $0.proteinFloorGrams = -100 }, "proteinFloorGrams -100")
        assertValid(parameters: F.params { $0.proteinFloorGrams = nil }, "proteinFloorGrams nil")
        assertValid(parameters: F.params { $0.proteinFloorGrams = 0.001 }, "proteinFloorGrams 0.001")
        // The generic defaults are valid.
        assertValid(parameters: .generic, "generic")
    }

    func testBandLowAboveHighIsInvalidInput() {
        assertInvalid(.phase, phase: F.phase(low: 1.20, high: 0.40), "low above high")
        assertInvalid(.phase, phase: F.phase(low: 0.401, high: 0.40), "low one quantum above high")
        assertValid(phase: F.phase(low: 0.40, high: 0.40), "low equal to high")
    }

    /// The remaining phase rules of §6.5.
    func testInvalidPhaseIsInvalidInput() {
        for start in ["", "soon", "2031-02-30", "2031-13-01"] {
            assertInvalid(.phase, phase: F.phase(startDay: start), "startDay \"\(start)\"")
        }
        for target in [0, -94.0, Double.nan, .infinity, -.infinity] {
            assertInvalid(.phase, phase: F.phase(target: target), "target \(target)")
        }
        for bound in [-0.001, Double.nan, .infinity, -.infinity] {
            assertInvalid(.phase, phase: F.phase(low: bound, high: 1.20), "low \(bound)")
        }
        for bound in [-0.001, Double.nan, .infinity] {
            assertInvalid(.phase, phase: F.phase(low: 0, high: bound), "high \(bound)")
        }
        // No target, a band from zero, and no phase at all are valid.
        assertValid(phase: F.phase(target: nil), "no target")
        assertValid(phase: F.phase(low: 0, high: 0), "band 0 to 0")
        assertValid(phase: nil, "no phase")
        // A phase that has not started is validated like any other.
        assertInvalid(.phase, phase: F.phase(startDay: "2031-12-01", low: 2, high: 1), "future phase, low above high")
    }

    func testUnparseableTodayIsInvalidInput() {
        for bad in ["", "today", "2031-02-30", "2031-13-01", "2031-03-00"] {
            assertInvalid(.today, today: bad, "today \"\(bad)\"")
        }
        // With no phase and nothing to evaluate, an unparseable today is still reported.
        let empty = evaluate(F.make(phase: nil, today: "tomorrow"))
        XCTAssertEqual(empty.invalidInput, .today)
        XCTAssertEqual(empty.verdict.reason, .invalidInput)
    }

    // MARK: - Totality

    /// §6.5: "`evaluate` never throws and never traps. It is total over every input." The values here
    /// sit where integer conversion and day arithmetic are most likely to trap.
    func testExtremeButValidInputsReturnWithoutTrapping() {
        // Readings so large that a sum, a product or `quantize` would overflow to infinity. Ruling R3:
        // a reading, lift weight or protein total above 1e100 in magnitude is rejected and counted as
        // `nonFinite`, so none of them reaches the arithmetic. They are dropped, the result is exactly
        // what it would be had they never been passed (here: no reading at all), and nothing traps.
        // Before R3 this test asserted that the two huge weights appeared as two weeks.
        let huge = evaluate(F.make(weights: [F.weight("2031-01-08", 1.7e308), F.weight("2031-01-15", 1.0e308)],
                                   waists: [F.waist("2031-01-08", 1.7e308), F.waist("2031-01-15", 1.0e308)],
                                   lifts: [CutScorecardLiftObservation(day: "2031-01-06", exercise: "A", weightKg: 1.7e308),
                                           CutScorecardLiftObservation(day: "2031-01-13", exercise: "A", weightKg: 1.0e308)],
                                   proteinDays: [CutScorecardProteinDay(day: "2031-01-14", grams: 1.7e308)],
                                   today: today))
        XCTAssertNil(huge.invalidInput)
        XCTAssertEqual(huge.rejections, rejections(7))
        XCTAssertEqual(huge.weeks, [])
        assertSameApartFromRejections(huge, evaluate(F.make(today: today)), "huge values dropped")
        assertCutVerdict(huge, .insufficientData, .noReadings)

        // Mixed with ordinary readings, the huge ones leave no trace but the count.
        let mixed = evaluate(F.make(weights: good + [F.weight("2031-01-15", 1.7e308), F.weight("2031-01-14", -1.7e308)],
                                    today: today))
        XCTAssertEqual(mixed.rejections, rejections(2))
        assertSameApartFromRejections(mixed, evaluate(F.make(weights: good, today: today)), "mixed")

        // The smallest positive values, and instants at the ends of Int.
        let tiny = evaluate(F.make(weights: [CutScorecardReading(day: "2031-01-08", takenAt: .min, value: 5e-324),
                                             CutScorecardReading(day: "2031-01-15", takenAt: .max, value: 5e-324)],
                                   waists: [CutScorecardReading(day: "2031-01-15", takenAt: .min, value: 5e-324)],
                                   today: today))
        XCTAssertNil(tiny.invalidInput)
        XCTAssertEqual(tiny.rejections, rejections())
        XCTAssertEqual(tiny.weeks.count, 2)

        // Very long windows, horizons and amounts. All are at or above their minimum, so all are valid.
        let wide = F.params {
            $0.rateWindowWeeks = 100_000; $0.waistWindowWeeks = 100_000
            $0.liftDropConsecutiveWeeks = 100_000; $0.slowLossConsecutiveWeeks = 100_000
            $0.maxWeighInAgeWeeks = .max; $0.maxProjectionWeeks = .max
            $0.addCaloriesKcal = .max; $0.reduceCarbsKcal = .max
        }
        let result = evaluate(F.input(today: F.weighInDay(9), parameters: wide))
        XCTAssertNil(result.invalidInput)
        XCTAssertEqual(result.weeks.count, 9)
        XCTAssertEqual(result.rate?.pointsUsed, 9, "a window longer than the phase is clipped to the phase")
        XCTAssertEqual(result.rule(1)?.state, .notFired, "a holding week inside the phase still settles rule 2")
        XCTAssertEqual(result.rule(2)?.state, .notFired, "an ordinary week inside the phase still settles rule 3")

        // A very old first reading: about 52,000 weeks of `weeks`, none of them filled.
        let old = evaluate(F.make(weights: [F.weight("1031-01-08", 100.0), F.weight("2031-01-15", 99.2)], today: today))
        XCTAssertNil(old.invalidInput)
        XCTAssertEqual(old.weeks.first?.weekStart, CutScorecard.weekStart(containing: "1031-01-08"))
        XCTAssertEqual(old.weeks.last?.weekStart, "2031-01-13")
        XCTAssertEqual(old.weeks.count, (F.dayNumber("2031-01-13") - F.dayNumber(old.weeks.first?.weekStart ?? "2031-01-13")) / 7 + 1)
        XCTAssertEqual(old.currentWeightKg, 99.2)
    }
}
