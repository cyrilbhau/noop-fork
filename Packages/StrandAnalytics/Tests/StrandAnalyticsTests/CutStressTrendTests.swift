import XCTest
@testable import StrandAnalytics

// API ASSUMED BY THESE TESTS
//
// Stage 6 specification, docs/personal/superapp/specs/stage-6.md §6.2. Every type is public, Equatable
// and Sendable, with a public memberwise init taking the stored properties in declaration order.
//
//   struct CutStressNight
//     init(day: String, restingHr: Double?, hrv: Double?)
//   struct CutStressInput
//     init(nights: [CutStressNight], firstWeekStart: String?, today: String,
//          minNightsPerWeek: Int = 4, maxWeeks: Int = 26)
//   struct CutStressWeek
//     let weekStart: String; let restingHrMean: Double?; let restingHrNights: Int
//     let hrvMean: Double?; let hrvNights: Int; let isCurrentWeek: Bool
//   struct CutStressChange
//     let fromWeekStart: String; let toWeekStart: String; let from: Double; let to: Double
//     let delta: Double
//   struct CutStressRejections
//     init(nonFinite: Int, outOfRange: Int, invalidDay: Int, future: Int, duplicateDay: Int)
//   enum CutStressInvalidInput: String { case today, firstWeekStart, parameters }
//   struct CutStressResult
//     let weeks: [CutStressWeek]; let restingHrChange: CutStressChange?
//     let hrvChange: CutStressChange?; let rejections: CutStressRejections
//     let invalidInput: CutStressInvalidInput?
//   enum CutStressTrend
//     static func weekly(_ input: CutStressInput) -> CutStressResult
//
// Existing API (not stage 6): Baselines.restingHRCfg and Baselines.hrvCfg (MetricCfg.minVal, .maxVal),
// CutScorecard.quantize(_:), and from the test target CutScorecardFixture.dayNumber(_:) / .dayKey(_:).
// These tests call neither CanonicalDay nor ChargeTypicalBand: the typical range is read by the
// cut-stress presenter in the app target (§8.2), not by this pure function.
//
// SPEC-AMBIGUITY (asserted): an invalid result is "empty" (§7.2 step 1). Read here as no weeks, no
// change and every rejection counter at zero, because nothing was judged.
// SPEC-AMBIGUITY (asserted): the three invalid causes of step 1 are checked in the order the step lists
// them: today, then parameters, then firstWeekStart.
// SPEC-AMBIGUITY (asserted): step 2 rejects whole nights before step 3 looks at values, so a night
// dropped as an earlier duplicate adds nothing to nonFinite or outOfRange, and nights rejected as
// invalidDay or future take no part in the duplicate count.
// SPEC-AMBIGUITY (not asserted): whether a non-finite or out-of-range value on a night before the first
// shown week is counted. Step 3 precedes step 4, step 5 says such nights are "not counted as rejected".
// No test here depends on either reading.

private typealias F = CutScorecardFixture

/// The fixture's values of §13.3. 2031-01-06 is a Monday, 2031-02-05 a Wednesday.
private let firstMonday = "2031-01-06"
private let fixtureToday = "2031-02-05"

/// `base` moved by `offset` days.
private func day(_ base: String, _ offset: Int) -> String {
    F.dayKey(F.dayNumber(base) + offset)
}

/// The Monday of the week containing `key`, from the fact that 2031-01-06 is a Monday.
private func monday(_ key: String) -> String {
    let distance = F.dayNumber(key) - F.dayNumber(firstMonday)
    let weeks = distance >= 0 ? distance / 7 : -((-distance + 6) / 7)
    return day(firstMonday, weeks * 7)
}

private func night(_ day: String, _ restingHr: Double?, _ hrv: Double?) -> CutStressNight {
    CutStressNight(day: day, restingHr: restingHr, hrv: hrv)
}

/// `count` consecutive nights from `start` with the same two values.
private func nights(from start: String, count: Int, _ restingHr: Double?,
                    _ hrv: Double?) -> [CutStressNight] {
    (0 ..< count).map { night(day(start, $0), restingHr, hrv) }
}

private func weekly(_ nights: [CutStressNight], first: String? = firstMonday,
                    today: String = fixtureToday, min: Int = 4,
                    maxWeeks: Int = 26) -> CutStressResult {
    CutStressTrend.weekly(CutStressInput(nights: nights, firstWeekStart: first, today: today,
                                         minNightsPerWeek: min, maxWeeks: maxWeeks))
}

private func rejections(nonFinite: Int = 0, outOfRange: Int = 0, invalidDay: Int = 0,
                        future: Int = 0, duplicateDay: Int = 0) -> CutStressRejections {
    CutStressRejections(nonFinite: nonFinite, outOfRange: outOfRange, invalidDay: invalidDay,
                        future: future, duplicateDay: duplicateDay)
}

private let nonCanonicalDays = [
    "", "2031-1-06", "2031-01-6", "20310106", "2031/01/06", "2031-02-30", "2031-13-01",
    "0000-01-01", "2031-01-06 ", "nonsense",
]

/// `CutStressTrend` (stage 6 specification §6.2, §7.2, test plan §12.1, fixture §13.3).
///
/// Every value here is invented. Expected values were worked by hand from §7.2; none is the output of an
/// implementation.
final class CutStressTrendTests: XCTestCase {

    private func week(_ result: CutStressResult, _ start: String,
                      file: StaticString = #filePath, line: UInt = #line) -> CutStressWeek? {
        let found = result.weeks.filter { $0.weekStart == start }
        XCTAssertEqual(found.count, 1, "week of \(start)", file: file, line: line)
        return found.first
    }

    private func assertEmptyInvalid(_ result: CutStressResult, _ cause: CutStressInvalidInput,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.invalidInput, cause, file: file, line: line)
        XCTAssertEqual(result.weeks, [], file: file, line: line)
        XCTAssertNil(result.restingHrChange, file: file, line: line)
        XCTAssertNil(result.hrvChange, file: file, line: line)
        // SPEC-AMBIGUITY: "empty result" read as zero counters too (see the header).
        XCTAssertEqual(result.rejections, rejections(), file: file, line: line)
    }

    // MARK: - Which weeks are shown

    func testEmptyNightsAndNoFirstWeekGiveNoWeeks() {
        let result = weekly([], first: nil)
        XCTAssertEqual(result.weeks, [])
        XCTAssertNil(result.restingHrChange)
        XCTAssertNil(result.hrvChange)
        XCTAssertEqual(result.rejections, rejections())
        XCTAssertNil(result.invalidInput)
        // Nights that carry no admitted value do not start a week either.
        let unmeasured = weekly([night("2031-01-15", nil, nil), night("2031-01-16", 500, .nan)],
                                first: nil)
        XCTAssertEqual(unmeasured.weeks, [])
        XCTAssertNil(unmeasured.invalidInput)
        let future = weekly([night("2031-02-06", 60, 50)], first: nil)
        XCTAssertEqual(future.weeks, [])
        XCTAssertEqual(future.rejections, rejections(future: 1))
    }

    func testWeeksAreContiguousFromFirstWeekToTodaysWeek() {
        let expected = ["2031-01-06", "2031-01-13", "2031-01-20", "2031-01-27", "2031-02-03"]
        // No nights at all: every week is still listed, as not measured.
        let empty = weekly([])
        XCTAssertEqual(empty.weeks.map(\.weekStart), expected)
        XCTAssertNil(empty.invalidInput)
        for week in empty.weeks {
            XCTAssertNil(week.restingHrMean)
            XCTAssertNil(week.hrvMean)
            XCTAssertEqual(week.restingHrNights, 0)
            XCTAssertEqual(week.hrvNights, 0)
        }
        XCTAssertEqual(empty.weeks.map(\.isCurrentWeek), [false, false, false, false, true])
        // Nights in only the first and last weeks leave the gap weeks in place.
        let gapped = weekly(nights(from: "2031-01-06", count: 4, 60, 50)
                            + nights(from: "2031-02-03", count: 3, 64, 45))
        XCTAssertEqual(gapped.weeks.map(\.weekStart), expected)
        // Today on the Monday and on the Sunday of the same week ends at the same week; the next
        // Monday adds one.
        XCTAssertEqual(weekly([], today: "2031-02-03").weeks.map(\.weekStart), expected)
        XCTAssertEqual(weekly([], today: "2031-02-09").weeks.map(\.weekStart), expected)
        XCTAssertEqual(weekly([], today: "2031-02-10").weeks.map(\.weekStart), expected + ["2031-02-10"])
        XCTAssertEqual(weekly([], today: "2031-02-02").weeks.map(\.weekStart), Array(expected.dropLast()))
        // A first week that is today's week gives one week.
        let one = weekly([], first: "2031-02-03")
        XCTAssertEqual(one.weeks.map(\.weekStart), ["2031-02-03"])
        XCTAssertEqual(one.weeks.map(\.isCurrentWeek), [true])
    }

    func testFirstWeekEarlierThanMaxWeeksIsClamped() {
        // Today's week is 2031-02-03. With maxWeeks 3 the earliest week shown is 2031-01-20.
        let all = nights(from: "2031-01-06", count: 31, 60, 50)
        let three = weekly(all, maxWeeks: 3)
        XCTAssertEqual(three.weeks.map(\.weekStart), ["2031-01-20", "2031-01-27", "2031-02-03"])
        XCTAssertNil(three.invalidInput)
        // Nights before the clamped start are unused, not rejected.
        XCTAssertEqual(three.rejections, rejections())
        XCTAssertEqual(three.restingHrChange?.fromWeekStart, "2031-01-20")
        // The boundary: five weeks fit exactly in maxWeeks 5; 4 drops one; 6 adds none.
        XCTAssertEqual(weekly(all, maxWeeks: 5).weeks.count, 5)
        XCTAssertEqual(weekly(all, maxWeeks: 5).weeks.first?.weekStart, "2031-01-06")
        XCTAssertEqual(weekly(all, maxWeeks: 4).weeks.map(\.weekStart).first, "2031-01-13")
        XCTAssertEqual(weekly(all, maxWeeks: 4).weeks.count, 4)
        XCTAssertEqual(weekly(all, maxWeeks: 6).weeks.count, 5)
        XCTAssertEqual(weekly(all, maxWeeks: 1).weeks.map(\.weekStart), ["2031-02-03"])
        // The same clamp applies when the start comes from the earliest night.
        XCTAssertEqual(weekly(all, first: nil, maxWeeks: 3).weeks.map(\.weekStart),
                       ["2031-01-20", "2031-01-27", "2031-02-03"])
        // The default is 26 weeks: 40 weeks of nights show the last 26.
        let long = nights(from: day("2031-02-03", -7 * 39), count: 7 * 39 + 3, 60, 50)
        let byDefault = CutStressTrend.weekly(
            CutStressInput(nights: long, firstWeekStart: nil, today: fixtureToday))
        XCTAssertEqual(byDefault.weeks.count, 26)
        XCTAssertEqual(byDefault.weeks.first?.weekStart, day("2031-02-03", -7 * 25))
        XCTAssertEqual(byDefault.weeks.last?.weekStart, "2031-02-03")
    }

    func testNilFirstWeekStartsAtTheEarliestAdmittedNight() {
        // A Wednesday night: its week starts on the Monday before.
        let result = weekly([night("2031-01-15", 60, nil)], first: nil)
        XCTAssertEqual(result.weeks.map(\.weekStart), ["2031-01-13", "2031-01-20", "2031-01-27", "2031-02-03"])
        // One admitted value of either metric is enough.
        XCTAssertEqual(weekly([night("2031-01-15", nil, 50)], first: nil).weeks.first?.weekStart,
                       "2031-01-13")
        // An earlier night with no admitted value does not move the start.
        let withJunk = weekly([night("2031-01-07", 500, nil), night("2031-01-08", nil, nil),
                               night("2031-01-09", nil, .infinity), night("2031-01-15", 60, nil)],
                              first: nil)
        XCTAssertEqual(withJunk.weeks.first?.weekStart, "2031-01-13")
        XCTAssertEqual(withJunk.weeks.count, 4)
        // Input order does not matter: the earliest day decides.
        let unordered = weekly([night("2031-01-30", 60, 50), night("2031-01-12", 60, 50),
                                night("2031-01-22", 60, 50)], first: nil)
        XCTAssertEqual(unordered.weeks.first?.weekStart, "2031-01-06")
        // A Monday night starts its own week; the Sunday before starts the week before.
        XCTAssertEqual(weekly([night("2031-01-13", 60, 50)], first: nil).weeks.first?.weekStart,
                       "2031-01-13")
        XCTAssertEqual(weekly([night("2031-01-12", 60, 50)], first: nil).weeks.first?.weekStart,
                       "2031-01-06")
    }

    func testNightsBeforeTheFirstWeekAreUnusedAndNotRejected() {
        let inside = nights(from: "2031-01-13", count: 4, 61, 48)
        let before = nights(from: "2030-12-30", count: 7, 90, 20)
        let with = weekly(before + inside, first: "2031-01-13")
        XCTAssertEqual(with.rejections, rejections())
        XCTAssertEqual(with.weeks.map(\.weekStart), ["2031-01-13", "2031-01-20", "2031-01-27", "2031-02-03"])
        XCTAssertEqual(with, weekly(inside, first: "2031-01-13"))
        // The Sunday immediately before the first Monday is outside; the Monday itself is inside.
        let edge = weekly([night("2031-01-12", 90, 20)] + inside, first: "2031-01-13")
        XCTAssertEqual(week(edge, "2031-01-13")?.restingHrNights, 4)
        XCTAssertEqual(week(edge, "2031-01-13")?.restingHrMean, 61)
        XCTAssertEqual(edge.rejections, rejections())
    }

    // MARK: - Means and the minimum

    func testWeekBelowTheMinimumHasNoMeanButReportsItsNights() {
        let result = weekly(nights(from: "2031-01-13", count: 3, 61, 48))
        let short = week(result, "2031-01-13")
        // "Not measured" is nil, never zero.
        XCTAssertNil(short?.restingHrMean)
        XCTAssertNil(short?.hrvMean)
        XCTAssertEqual(short?.restingHrNights, 3)
        XCTAssertEqual(short?.hrvNights, 3)
        // A week with no nights reports zero nights and no mean.
        let none = week(result, "2031-01-20")
        XCTAssertNil(none?.restingHrMean)
        XCTAssertNil(none?.hrvMean)
        XCTAssertEqual(none?.restingHrNights, 0)
        XCTAssertEqual(none?.hrvNights, 0)
        // One below a different minimum.
        let six = weekly(nights(from: "2031-01-13", count: 6, 61, 48), min: 7)
        XCTAssertNil(week(six, "2031-01-13")?.restingHrMean)
        XCTAssertEqual(week(six, "2031-01-13")?.restingHrNights, 6)
    }

    func testWeekAtExactlyTheMinimumHasAMean() {
        let four = week(weekly(nights(from: "2031-01-13", count: 4, 61, 48)), "2031-01-13")
        XCTAssertEqual(four?.restingHrMean, 61)
        XCTAssertEqual(four?.hrvMean, 48)
        XCTAssertEqual(four?.restingHrNights, 4)
        XCTAssertEqual(four?.hrvNights, 4)
        let five = week(weekly(nights(from: "2031-01-13", count: 5, 61, 48)), "2031-01-13")
        XCTAssertEqual(five?.restingHrMean, 61)
        XCTAssertEqual(five?.restingHrNights, 5)
        // The minimum is the parameter, not the constant four.
        let seven = weekly(nights(from: "2031-01-13", count: 7, 61, 48), min: 7)
        XCTAssertEqual(week(seven, "2031-01-13")?.restingHrMean, 61)
        let oneNight = weekly(nights(from: "2031-01-13", count: 1, 61, 48), min: 1)
        XCTAssertEqual(week(oneNight, "2031-01-13")?.hrvMean, 48)
        XCTAssertNil(week(oneNight, "2031-01-20")?.hrvMean)
        let twoOfThree = weekly(nights(from: "2031-01-13", count: 2, 61, 48), min: 3)
        XCTAssertNil(week(twoOfThree, "2031-01-13")?.hrvMean)
        let threeOfThree = weekly(nights(from: "2031-01-13", count: 3, 61, 48), min: 3)
        XCTAssertEqual(week(threeOfThree, "2031-01-13")?.hrvMean, 48)
    }

    func testMeanIsQuantizedToThreeDecimals() {
        // 421 ÷ 7 = 60.142857…, 423 ÷ 7 = 60.428571… (rounds up, so truncation is caught).
        let rhr: [Double] = [60, 60, 60, 60, 60, 60, 61]
        let hrv: [Double] = [60, 60, 60, 60, 61, 61, 61]
        let all = (0 ..< 7).map { night(day("2031-01-13", $0), rhr[$0], hrv[$0]) }
        let found = week(weekly(all), "2031-01-13")
        XCTAssertEqual(found?.restingHrMean, CutScorecard.quantize(421.0 / 7.0))
        XCTAssertEqual(found?.hrvMean, CutScorecard.quantize(423.0 / 7.0))
        XCTAssertEqual(found?.restingHrMean ?? 0, 60.143, accuracy: 1e-9)
        XCTAssertEqual(found?.hrvMean ?? 0, 60.429, accuracy: 1e-9)
        XCTAssertNotEqual(found?.restingHrMean, 421.0 / 7.0)
        // A mean that needs no rounding is unchanged: 245 ÷ 4.
        let quarter: [Double] = [61, 61, 61, 62]
        let exact = (0 ..< 4).map { night(day("2031-01-20", $0), quarter[$0], nil) }
        XCTAssertEqual(week(weekly(exact), "2031-01-20")?.restingHrMean, 61.25)
    }

    func testMetricsAreCountedIndependently() {
        var all = nights(from: "2031-01-13", count: 3, 61, 48)
        all += [night("2031-01-16", 61, nil), night("2031-01-17", 61, nil)]
        let found = week(weekly(all), "2031-01-13")
        XCTAssertEqual(found?.restingHrNights, 5)
        XCTAssertEqual(found?.restingHrMean, 61)
        XCTAssertEqual(found?.hrvNights, 3)
        XCTAssertNil(found?.hrvMean)
        // The other way round, with the resting heart rate dropped as out of range on one night.
        var other = nights(from: "2031-01-20", count: 3, 62, 47)
        other += [night("2031-01-23", 500, 47), night("2031-01-24", nil, 47)]
        let result = weekly(other)
        XCTAssertEqual(week(result, "2031-01-20")?.restingHrNights, 3)
        XCTAssertNil(week(result, "2031-01-20")?.restingHrMean)
        XCTAssertEqual(week(result, "2031-01-20")?.hrvNights, 5)
        XCTAssertEqual(week(result, "2031-01-20")?.hrvMean, 47)
        XCTAssertEqual(result.rejections, rejections(outOfRange: 1))
        XCTAssertNil(result.restingHrChange)
        XCTAssertNil(result.hrvChange)
    }

    // MARK: - Rejected values and nights

    func testOutOfRangeAndNonFiniteValuesAreDroppedAndCounted() {
        // Week of 01-13: four good resting heart rates and three that must not reach the mean.
        var all = nights(from: "2031-01-13", count: 4, 60, nil)
        all += [night("2031-01-17", 500, nil), night("2031-01-18", .nan, nil),
                night("2031-01-19", -.infinity, nil)]
        // Week of 01-20: the same for HRV, with a value below the lower bound as well.
        all += nights(from: "2031-01-20", count: 4, nil, 50)
        all += [night("2031-01-24", nil, 1000), night("2031-01-25", nil, .infinity),
                night("2031-01-26", nil, 1)]
        // Week of 01-27: a night where both values are bad, and one where each is bad differently.
        all += [night("2031-01-27", .nan, .nan), night("2031-01-28", 0, .signalingNaN),
                night("2031-01-29", -60, -50)]
        let result = weekly(all)
        XCTAssertEqual(week(result, "2031-01-13")?.restingHrNights, 4)
        XCTAssertEqual(week(result, "2031-01-13")?.restingHrMean, 60)
        XCTAssertEqual(week(result, "2031-01-20")?.hrvNights, 4)
        XCTAssertEqual(week(result, "2031-01-20")?.hrvMean, 50)
        XCTAssertEqual(week(result, "2031-01-27")?.restingHrNights, 0)
        XCTAssertEqual(week(result, "2031-01-27")?.hrvNights, 0)
        // nonFinite: NaN, -inf (01-13 week); +inf (01-20 week); NaN, NaN, NaN (01-27 week) = 6.
        // outOfRange: 500; 1000, 1; 0, -60, -50 = 6.
        XCTAssertEqual(result.rejections, rejections(nonFinite: 6, outOfRange: 6))
        XCTAssertNil(result.invalidInput)
        // A missing value is not a rejection.
        XCTAssertEqual(weekly([night("2031-01-13", nil, nil)]).rejections, rejections())
    }

    func testBoundsAreTheBaselineConfigsInclusive() {
        let rhr = Baselines.restingHRCfg, hrv = Baselines.hrvCfg
        /// Nights admitted and values counted out of range when four nights carry `value`.
        func restingHr(_ value: Double) -> (nights: Int?, mean: Double?, outOfRange: Int) {
            let result = weekly(nights(from: "2031-01-13", count: 4, value, nil))
            let found = week(result, "2031-01-13")
            return (found?.restingHrNights, found?.restingHrMean, result.rejections.outOfRange)
        }
        func heartRateVariability(_ value: Double) -> (nights: Int?, mean: Double?, outOfRange: Int) {
            let result = weekly(nights(from: "2031-01-13", count: 4, nil, value))
            let found = week(result, "2031-01-13")
            return (found?.hrvNights, found?.hrvMean, result.rejections.outOfRange)
        }
        for (cfg, probe) in [(rhr, restingHr), (hrv, heartRateVariability)] {
            // At each bound: admitted.
            XCTAssertEqual(probe(cfg.minVal).nights, 4)
            XCTAssertEqual(probe(cfg.minVal).mean, CutScorecard.quantize(cfg.minVal))
            XCTAssertEqual(probe(cfg.minVal).outOfRange, 0)
            XCTAssertEqual(probe(cfg.maxVal).nights, 4)
            XCTAssertEqual(probe(cfg.maxVal).mean, CutScorecard.quantize(cfg.maxVal))
            XCTAssertEqual(probe(cfg.maxVal).outOfRange, 0)
            // One representable step inside: admitted.
            XCTAssertEqual(probe(cfg.minVal.nextUp).nights, 4)
            XCTAssertEqual(probe(cfg.maxVal.nextDown).nights, 4)
            // One representable step outside: dropped and counted.
            XCTAssertEqual(probe(cfg.minVal.nextDown).nights, 0)
            XCTAssertNil(probe(cfg.minVal.nextDown).mean)
            XCTAssertEqual(probe(cfg.minVal.nextDown).outOfRange, 4)
            XCTAssertEqual(probe(cfg.maxVal.nextUp).nights, 0)
            XCTAssertNil(probe(cfg.maxVal.nextUp).mean)
            XCTAssertEqual(probe(cfg.maxVal.nextUp).outOfRange, 4)
        }
        // The two metrics use their own configs: a value inside one and outside the other.
        XCTAssertLessThan(hrv.minVal, rhr.minVal)
        XCTAssertLessThan(rhr.maxVal, hrv.maxVal)
        let low = (hrv.minVal + rhr.minVal) / 2, high = (rhr.maxVal + hrv.maxVal) / 2
        for value in [low, high] {
            XCTAssertEqual(restingHr(value).nights, 0, "\(value)")
            XCTAssertEqual(heartRateVariability(value).nights, 4, "\(value)")
        }
    }

    func testFutureAndInvalidDaysAreRejected() {
        var all = nights(from: "2031-02-03", count: 3, 64, 45)   // Monday to Wednesday (today)
        all.append(night("2031-02-06", 99, 99))                    // tomorrow
        all.append(night("2031-03-01", 99, 99))
        all += nonCanonicalDays.map { night($0, 99, 99) }
        let result = weekly(all, min: 1)
        XCTAssertEqual(result.rejections,
                       rejections(invalidDay: nonCanonicalDays.count, future: 2))
        // Today's own night is kept: the current week holds exactly Monday to Wednesday.
        XCTAssertEqual(week(result, "2031-02-03")?.restingHrNights, 3)
        XCTAssertEqual(week(result, "2031-02-03")?.restingHrMean, 64)
        XCTAssertEqual(week(result, "2031-02-03")?.hrvMean, 45)
        XCTAssertEqual(result.weeks.last?.weekStart, "2031-02-03")
        // A rejected night's values are not looked at: no value counter moves.
        let bad = weekly([night("2031-02-06", .nan, 5000), night("nonsense", .nan, 5000)])
        XCTAssertEqual(bad.rejections, rejections(invalidDay: 1, future: 1))
    }

    func testDuplicateDayKeepsTheLast() {
        let base = nights(from: "2031-01-14", count: 3, 60, 50)
        let twice = weekly([night("2031-01-13", 90, 90)] + base + [night("2031-01-13", 64, 54)])
        XCTAssertEqual(twice.rejections, rejections(duplicateDay: 1))
        XCTAssertEqual(week(twice, "2031-01-13")?.restingHrNights, 4)
        XCTAssertEqual(week(twice, "2031-01-13")?.restingHrMean, 61)    // (60 × 3 + 64) ÷ 4
        XCTAssertEqual(week(twice, "2031-01-13")?.hrvMean, 51)
        // The other input order keeps the other night.
        let swapped = weekly([night("2031-01-13", 64, 54)] + base + [night("2031-01-13", 90, 90)])
        XCTAssertEqual(week(swapped, "2031-01-13")?.restingHrMean, 67.5)  // (180 + 90) ÷ 4
        // Each earlier copy is counted.
        let thrice = weekly([night("2031-01-13", 90, 90), night("2031-01-13", 80, 80)] + base
                            + [night("2031-01-13", 64, 54)])
        XCTAssertEqual(thrice.rejections, rejections(duplicateDay: 2))
        XCTAssertEqual(week(thrice, "2031-01-13")?.restingHrMean, 61)
        // The last night is kept whole: its missing value is not filled from the earlier copy.
        let partial = weekly([night("2031-01-13", 64, 54)] + base + [night("2031-01-13", nil, 58)])
        XCTAssertEqual(week(partial, "2031-01-13")?.restingHrNights, 3)
        XCTAssertNil(week(partial, "2031-01-13")?.restingHrMean)
        XCTAssertEqual(week(partial, "2031-01-13")?.hrvMean, 52)         // (150 + 58) ÷ 4
        // SPEC-AMBIGUITY: an earlier copy is rejected whole, so its bad values are not counted too;
        // and nights already rejected as future are not counted again as duplicates.
        let junk = weekly([night("2031-01-13", .nan, 5000)] + base + [night("2031-01-13", 64, 54)])
        XCTAssertEqual(junk.rejections, rejections(duplicateDay: 1))
        let future = weekly([night("2031-02-08", 60, 50), night("2031-02-08", 60, 50)])
        XCTAssertEqual(future.rejections, rejections(future: 2))
    }

    // MARK: - The week

    func testSundayAndMondayFallInDifferentWeeks() {
        // Thursday to Sunday in one week, Monday to Thursday in the next.
        let all = nights(from: "2031-01-09", count: 4, 60, 50) + nights(from: "2031-01-13", count: 4, 70, 40)
        let result = weekly(all)
        XCTAssertEqual(week(result, "2031-01-06")?.restingHrNights, 4)
        XCTAssertEqual(week(result, "2031-01-06")?.restingHrMean, 60)
        XCTAssertEqual(week(result, "2031-01-06")?.hrvMean, 50)
        XCTAssertEqual(week(result, "2031-01-13")?.restingHrNights, 4)
        XCTAssertEqual(week(result, "2031-01-13")?.restingHrMean, 70)
        XCTAssertEqual(week(result, "2031-01-13")?.hrvMean, 40)
        // Every week start is a Monday.
        for found in result.weeks { XCTAssertEqual(found.weekStart, monday(found.weekStart)) }
        // A single Sunday night counts for the week that ends on it, not the one that follows.
        let sunday = weekly([night("2031-01-19", 61, 49)], min: 1)
        XCTAssertEqual(week(sunday, "2031-01-13")?.restingHrNights, 1)
        XCTAssertEqual(week(sunday, "2031-01-20")?.restingHrNights, 0)
    }

    func testCurrentWeekIsFlaggedAndFollowsTheSameMinimum() {
        let earlier = nights(from: "2031-01-27", count: 7, 62, 48)
        // Today is Wednesday: three nights so far, below the minimum.
        let three = weekly(earlier + nights(from: "2031-02-03", count: 3, 64, 45))
        XCTAssertEqual(three.weeks.filter(\.isCurrentWeek).map(\.weekStart), ["2031-02-03"])
        XCTAssertEqual(three.weeks.last?.isCurrentWeek, true)
        XCTAssertNil(three.weeks.last?.restingHrMean)
        XCTAssertEqual(three.weeks.last?.restingHrNights, 3)
        XCTAssertNil(three.restingHrChange)
        // Thursday: the fourth night gives the current week a mean, and it takes part in the change.
        let four = weekly(earlier + nights(from: "2031-02-03", count: 4, 64, 45), today: "2031-02-06")
        XCTAssertEqual(four.weeks.filter(\.isCurrentWeek).map(\.weekStart), ["2031-02-03"])
        XCTAssertEqual(four.weeks.last?.restingHrMean, 64)
        XCTAssertEqual(four.weeks.last?.hrvMean, 45)
        XCTAssertEqual(four.restingHrChange?.toWeekStart, "2031-02-03")
        XCTAssertEqual(four.restingHrChange?.delta, 2)
        XCTAssertEqual(four.hrvChange?.delta, -3)
    }

    // MARK: - Change

    func testChangeRunsFromEarliestToLatestWeekWithAMean() {
        // Weeks: 01-06 short, 01-13 mean, 01-20 mean, 01-27 mean, 02-03 (current) short.
        var all = nights(from: "2031-01-06", count: 3, 90, 20)
        all += [night("2031-01-13", 61, 50), night("2031-01-14", 61, 50), night("2031-01-15", 61, 50),
                night("2031-01-16", 62, 50)]                          // 61.25, 50
        all += nights(from: "2031-01-20", count: 4, 70, 60)           // a peak in the middle
        all += [night("2031-01-27", 64, 44), night("2031-01-28", 64, 44), night("2031-01-29", 65, 45),
                night("2031-01-30", 65, 45)]                          // 64.5, 44.5
        all += nights(from: "2031-02-03", count: 2, 30, 250)
        let result = weekly(all)
        let rhr = result.restingHrChange
        XCTAssertEqual(rhr?.fromWeekStart, "2031-01-13")
        XCTAssertEqual(rhr?.toWeekStart, "2031-01-27")
        XCTAssertEqual(rhr?.from, 61.25)
        XCTAssertEqual(rhr?.to, 64.5)
        XCTAssertEqual(rhr?.delta, 3.25)
        let hrv = result.hrvChange
        XCTAssertEqual(hrv?.fromWeekStart, "2031-01-13")
        XCTAssertEqual(hrv?.toWeekStart, "2031-01-27")
        XCTAssertEqual(hrv?.from, 50)
        XCTAssertEqual(hrv?.to, 44.5)
        XCTAssertEqual(hrv?.delta, -5.5)                              // to minus from, signed
        // The endpoints are the means the week rows show.
        XCTAssertEqual(rhr?.from, week(result, "2031-01-13")?.restingHrMean)
        XCTAssertEqual(rhr?.to, week(result, "2031-01-27")?.restingHrMean)
    }

    func testChangeIsNilWithOneMean() {
        let one = weekly(nights(from: "2031-01-13", count: 4, 61, 48)
                         + nights(from: "2031-01-20", count: 3, 70, 40))
        XCTAssertNil(one.restingHrChange)
        XCTAssertNil(one.hrvChange)
        XCTAssertNil(weekly([]).restingHrChange)
        // Per metric: two resting heart rate means, one HRV mean.
        let mixed = weekly(nights(from: "2031-01-13", count: 4, 61, 48)
                           + nights(from: "2031-01-20", count: 4, 63, nil))
        XCTAssertEqual(mixed.restingHrChange?.delta, 2)
        XCTAssertNil(mixed.hrvChange)
        // Two weeks with the same mean are two weeks: a change of zero, not "no change to show".
        let level = weekly(nights(from: "2031-01-13", count: 4, 61, 48)
                           + nights(from: "2031-01-27", count: 4, 61, 48))
        XCTAssertEqual(level.restingHrChange?.delta, 0)
        XCTAssertEqual(level.restingHrChange?.fromWeekStart, "2031-01-13")
        XCTAssertEqual(level.restingHrChange?.toWeekStart, "2031-01-27")
    }

    // MARK: - Invalid input

    func testFirstWeekNotAMondayIsInvalid() {
        let all = nights(from: "2031-01-06", count: 28, 60, 50)
        for offset in 1 ... 6 {
            assertEmptyInvalid(weekly(all, first: day(firstMonday, offset)), .firstWeekStart)
        }
        for bad in nonCanonicalDays {
            assertEmptyInvalid(weekly(all, first: bad), .firstWeekStart)
        }
        // The Mondays either side are valid.
        XCTAssertNil(weekly(all, first: "2031-01-13").invalidInput)
        XCTAssertNil(weekly(all, first: "2030-12-30").invalidInput)
    }

    func testFirstWeekAfterTodayIsInvalid() {
        let all = nights(from: "2031-01-06", count: 28, 60, 50)
        // Today is Wednesday 2031-02-05. The Monday of today's week is valid; the next is not.
        XCTAssertNil(weekly(all, first: "2031-02-03").invalidInput)
        assertEmptyInvalid(weekly(all, first: "2031-02-10"), .firstWeekStart)
        assertEmptyInvalid(weekly(all, first: "2031-06-02"), .firstWeekStart)
        // A Monday that is today is not after today.
        XCTAssertNil(weekly(all, first: "2031-02-03", today: "2031-02-03").invalidInput)
        assertEmptyInvalid(weekly(all, first: "2031-02-03", today: "2031-02-02"), .firstWeekStart)
    }

    func testInvalidParametersAndToday() {
        let all = nights(from: "2031-01-06", count: 28, 60, 50) + [night("nonsense", 60, 50)]
        for bad in nonCanonicalDays {
            assertEmptyInvalid(weekly(all, today: bad), .today)
            assertEmptyInvalid(weekly(all, first: nil, today: bad), .today)
        }
        // minNightsPerWeek: 1 to 7 inclusive.
        assertEmptyInvalid(weekly(all, min: 0), .parameters)
        assertEmptyInvalid(weekly(all, min: -1), .parameters)
        assertEmptyInvalid(weekly(all, min: 8), .parameters)
        XCTAssertNil(weekly(all, min: 1).invalidInput)
        XCTAssertNil(weekly(all, min: 7).invalidInput)
        // maxWeeks: at least 1.
        assertEmptyInvalid(weekly(all, maxWeeks: 0), .parameters)
        assertEmptyInvalid(weekly(all, maxWeeks: -5), .parameters)
        XCTAssertNil(weekly(all, maxWeeks: 1).invalidInput)
        XCTAssertNil(weekly(all, maxWeeks: Int.max).invalidInput)
        XCTAssertEqual(weekly(all, maxWeeks: Int.max).weeks.count, 5)
        // SPEC-AMBIGUITY: causes are reported in the order §7.2 step 1 lists them.
        assertEmptyInvalid(weekly(all, first: "2031-01-07", today: "nonsense", min: 0), .today)
        assertEmptyInvalid(weekly(all, first: "2031-01-07", min: 0), .parameters)
        // A valid input reports no cause.
        XCTAssertNil(weekly(all).invalidInput)
    }

    // MARK: - Fixture

    private func fixtureNights() -> [CutStressNight] {
        var all = nights(from: "2031-01-06", count: 7, 60, 50)
        all += nights(from: "2031-01-13", count: 4, 61, 48)
        all += nights(from: "2031-01-20", count: 3, 62, 47)
        let rhr: [Double] = [63, 63, 64, 64, 65, 65, 66]
        let hrv: [Double] = [46, 46, 45, 45, 44, 44, 43]
        all += (0 ..< 7).map { night(day("2031-01-27", $0), rhr[$0], hrv[$0]) }
        all += nights(from: "2031-02-03", count: 3, 64, 45)
        // Extra nights that must change nothing but the counters.
        all += [night("2031-01-17", 500, nil), night("2031-01-18", nil, .nan),
                night("2031-02-09", 64, 45), night("2030-12-30", 60, 50)]
        return all
    }

    func testFixtureWeeksGiveTheExpectedTable() {
        let result = weekly(fixtureNights())
        XCTAssertNil(result.invalidInput)
        let expected: [(String, Double?, Int, Double?, Int)] = [
            ("2031-01-06", 60.000, 7, 50.000, 7),
            ("2031-01-13", 61.000, 4, 48.000, 4),
            ("2031-01-20", nil, 3, nil, 3),
            ("2031-01-27", 64.286, 7, 44.714, 7),   // 450 ÷ 7 and 313 ÷ 7
            ("2031-02-03", nil, 3, nil, 3),
        ]
        XCTAssertEqual(result.weeks.map(\.weekStart), expected.map(\.0))
        for (found, row) in zip(result.weeks, expected) {
            XCTAssertEqual(found.restingHrNights, row.2, row.0)
            XCTAssertEqual(found.hrvNights, row.4, row.0)
            XCTAssertEqual(found.restingHrMean == nil, row.1 == nil, row.0)
            XCTAssertEqual(found.hrvMean == nil, row.3 == nil, row.0)
            if let mean = row.1 { XCTAssertEqual(found.restingHrMean ?? .nan, mean, accuracy: 1e-9, row.0) }
            if let mean = row.3 { XCTAssertEqual(found.hrvMean ?? .nan, mean, accuracy: 1e-9, row.0) }
            XCTAssertEqual(found.isCurrentWeek, row.0 == "2031-02-03", row.0)
        }
        XCTAssertEqual(result.rejections, rejections(nonFinite: 1, outOfRange: 1, future: 1))

        let rhr = result.restingHrChange
        XCTAssertEqual(rhr?.fromWeekStart, "2031-01-06")
        XCTAssertEqual(rhr?.toWeekStart, "2031-01-27")
        XCTAssertEqual(rhr?.from ?? .nan, 60.000, accuracy: 1e-9)
        XCTAssertEqual(rhr?.to ?? .nan, 64.286, accuracy: 1e-9)
        XCTAssertEqual(rhr?.delta ?? .nan, 4.286, accuracy: 1e-9)
        let hrv = result.hrvChange
        XCTAssertEqual(hrv?.fromWeekStart, "2031-01-06")
        XCTAssertEqual(hrv?.toWeekStart, "2031-01-27")
        XCTAssertEqual(hrv?.from ?? .nan, 50.000, accuracy: 1e-9)
        XCTAssertEqual(hrv?.to ?? .nan, 44.714, accuracy: 1e-9)
        XCTAssertEqual(hrv?.delta ?? .nan, -5.286, accuracy: 1e-9)
        // The delta is the quantized difference of the two shown means.
        XCTAssertEqual(rhr?.delta, CutScorecard.quantize(CutScorecard.quantize(450.0 / 7.0) - 60))
        XCTAssertEqual(hrv?.delta, CutScorecard.quantize(CutScorecard.quantize(313.0 / 7.0) - 50))
    }

    func testAddingANightOutsideTheShownWeeksChangesNothing() {
        let base = weekly(fixtureNights())
        for extra in ["2030-12-01", "2031-01-05", "2029-06-15"] {
            XCTAssertEqual(weekly(fixtureNights() + [night(extra, 99, 99)]), base, extra)
            XCTAssertEqual(weekly([night(extra, 99, 99)] + fixtureNights()), base, extra)
        }
        // With the shown weeks clamped by maxWeeks, a night in a clamped-away week changes nothing.
        let clamped = weekly(fixtureNights(), maxWeeks: 2)
        XCTAssertEqual(weekly(fixtureNights() + [night("2031-01-25", 99, 99)], maxWeeks: 2), clamped)
        // A night inside a shown week does change the result (so the checks above can fail).
        XCTAssertNotEqual(weekly(fixtureNights() + [night("2031-01-23", 99, 99)]), base)
    }

    // MARK: - Shape, determinism, order

    func testResultHasNoStateOrTierField() {
        let result = weekly(fixtureNights())
        guard let week = result.weeks.first, let change = result.restingHrChange else {
            return XCTFail("the fixture must give a week and a change to reflect")
        }
        func labels(_ value: Any) -> [String] { Mirror(reflecting: value).children.compactMap(\.label) }
        let all = labels(result) + labels(week) + labels(change) + labels(result.rejections)
        XCTAssertFalse(all.isEmpty)
        for label in all {
            for banned in ["state", "tier", "band", "score", "elevated", "suppressed"] {
                XCTAssertFalse(label.lowercased().contains(banned), "\(label) contains \(banned)")
            }
        }
        // The output is exactly the fields of §6.2: nothing that grades a week has been added.
        XCTAssertEqual(labels(result),
                       ["weeks", "restingHrChange", "hrvChange", "rejections", "invalidInput"])
        XCTAssertEqual(labels(week), ["weekStart", "restingHrMean", "restingHrNights", "hrvMean",
                                      "hrvNights", "isCurrentWeek"])
        XCTAssertEqual(labels(change), ["fromWeekStart", "toWeekStart", "from", "to", "delta"])
        XCTAssertEqual(labels(result.rejections),
                       ["nonFinite", "outOfRange", "invalidDay", "future", "duplicateDay"])
    }

    func testSameInputSameOutput() {
        let input = CutStressInput(nights: fixtureNights(), firstWeekStart: firstMonday,
                                   today: fixtureToday, minNightsPerWeek: 4, maxWeeks: 26)
        let first = CutStressTrend.weekly(input)
        for _ in 0 ..< 3 { XCTAssertEqual(CutStressTrend.weekly(input), first) }
        _ = weekly(nights(from: "2031-01-06", count: 10, 99, 99), today: "2031-01-20")
        XCTAssertEqual(CutStressTrend.weekly(input), first)
    }

    func testNightOrderDoesNotMatterWhenDaysAreDistinct() {
        // The fixture has one night per day, so the keep-the-last rule has nothing to decide.
        let all = fixtureNights()
        let base = weekly(all)
        XCTAssertEqual(weekly(Array(all.reversed())), base)
        let interleaved = stride(from: 0, to: all.count, by: 2).map { all[$0] }
            + stride(from: 1, to: all.count, by: 2).map { all[$0] }
        XCTAssertEqual(weekly(interleaved), base)
        XCTAssertEqual(weekly(Array(all.reversed()), first: nil), weekly(all, first: nil))
    }

    // MARK: - Properties over generated inputs

    /// A 64-bit linear congruential generator (Knuth's MMIX constants) with a fixed seed. Nothing here
    /// draws randomness from the system, so every run sees the same inputs.
    private struct Generator {
        var state: UInt64
        /// A value in `0 ..< bound`.
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33) % bound
        }
    }

    func testGeneratedNightsGiveTheWeeklyArithmeticMean() {
        var generator = Generator(state: 0x57_2E55)
        var means = 0, shortWeeks = 0
        for index in 0 ..< 120 {
            let label = "case \(index)"
            let today = day("2031-03-01", generator.next(60))
            let minimum = 1 + generator.next(7)
            let maxWeeks = 1 + generator.next(14)
            // One night per day at most, whole-number values inside both configs, about one value in
            // five missing. Whole numbers keep every sum exact whatever the order of addition.
            var all: [CutStressNight] = []
            for back in 0 ..< 84 where generator.next(4) != 0 {
                let rhr: Double? = generator.next(5) == 0 ? nil : Double(40 + generator.next(50))
                let hrv: Double? = generator.next(5) == 0 ? nil : Double(20 + generator.next(90))
                all.append(night(day(today, -back), rhr, hrv))
            }
            let explicitFirst: String? = generator.next(2) == 0
                ? nil : day(monday(today), -7 * generator.next(14))
            let result = weekly(all, first: explicitFirst, today: today, min: minimum,
                                maxWeeks: maxWeeks)
            XCTAssertNil(result.invalidInput, label)
            XCTAssertEqual(result.rejections, rejections(), label)

            // The weeks this input should show, worked out here from §7.2 steps 4 and 5.
            let last = monday(today)
            let bound = day(last, -7 * (maxWeeks - 1))
            let measured = all.filter { $0.restingHr != nil || $0.hrv != nil }.map(\.day)
            var expectedStarts: [String] = []
            if let start = explicitFirst ?? measured.min().map(monday) {
                var cursor = max(start, bound)
                while cursor <= last {
                    expectedStarts.append(cursor)
                    cursor = day(cursor, 7)
                }
            }
            XCTAssertEqual(result.weeks.map(\.weekStart), expectedStarts, label)
            XCTAssertLessThanOrEqual(result.weeks.count, maxWeeks, label)
            XCTAssertEqual(result.weeks.filter(\.isCurrentWeek).map(\.weekStart),
                           expectedStarts.isEmpty ? [] : [last], label)

            for found in result.weeks {
                let inWeek = all.filter { monday($0.day) == found.weekStart }
                for (values, nightCount, mean) in [
                    (inWeek.compactMap(\.restingHr), found.restingHrNights, found.restingHrMean),
                    (inWeek.compactMap(\.hrv), found.hrvNights, found.hrvMean),
                ] {
                    XCTAssertEqual(nightCount, values.count, label)
                    XCTAssertLessThanOrEqual(nightCount, 7, label)
                    if values.count >= minimum {
                        means += 1
                        let expected = CutScorecard.quantize(values.reduce(0, +) / Double(values.count))
                        XCTAssertEqual(mean, expected, label)
                        // A mean lies between the least and greatest night it averages.
                        XCTAssertGreaterThanOrEqual(expected, values.min()!, label)
                        XCTAssertLessThanOrEqual(expected, values.max()!, label)
                    } else {
                        shortWeeks += 1
                        XCTAssertNil(mean, label)
                    }
                }
            }

            // The change joins the first and last weeks that have a mean, and only when there are two.
            for (change, keyPath) in [(result.restingHrChange, \CutStressWeek.restingHrMean),
                                      (result.hrvChange, \CutStressWeek.hrvMean)] {
                let withMean = result.weeks.filter { $0[keyPath: keyPath] != nil }
                guard withMean.count >= 2, let from = withMean.first, let to = withMean.last else {
                    XCTAssertNil(change, label)
                    continue
                }
                XCTAssertEqual(change?.fromWeekStart, from.weekStart, label)
                XCTAssertEqual(change?.toWeekStart, to.weekStart, label)
                XCTAssertEqual(change?.from, from[keyPath: keyPath], label)
                XCTAssertEqual(change?.to, to[keyPath: keyPath], label)
                XCTAssertEqual(change?.delta,
                               CutScorecard.quantize(to[keyPath: keyPath]! - from[keyPath: keyPath]!),
                               label)
            }

            // One night per day: the order the nights arrive in changes nothing.
            var shuffled = all
            for i in stride(from: shuffled.count - 1, to: 0, by: -1) {
                shuffled.swapAt(i, generator.next(i + 1))
            }
            XCTAssertEqual(weekly(shuffled, first: explicitFirst, today: today, min: minimum,
                                  maxWeeks: maxWeeks), result, label)
        }
        // The generator must reach both branches for the properties above to mean anything.
        XCTAssertGreaterThan(means, 200)
        XCTAssertGreaterThan(shortWeeks, 200)
    }
}
