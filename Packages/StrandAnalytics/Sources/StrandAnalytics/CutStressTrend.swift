import Foundation

// Stage 6 of the personal fork: weekly means of nightly resting heart rate and nightly HRV on the
// scorecard's own Monday weeks (docs/personal/superapp/specs/stage-6.md §6.2 and §7.2).
//
// Display only. The output is an arithmetic mean of values the app already stores and shows, the number
// of nights behind it, and a signed difference between two weeks. There is no grade, adjective or
// boolean anywhere in it, on purpose, and nothing here is read by Recovery, Strain, the scorecard
// verdict, illness detection or the Coach. A week with too few nights is "not measured" (nil), never
// zero.
//
// Pure: no store, no clock, no `Date`, `Calendar` or `TimeZone`. "Today" is passed in as a day key and
// every day goes through `CanonicalDay`. Nothing here throws or traps on any input, and no output is
// NaN or infinite.
//
// No Kotlin twin: the owner has skipped Android for the personal fork (stage 1 ruling R43), so every
// declaration here is unpaired in the parity ledger.

/// One night's two readings. Nil is "not measured".
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct CutStressNight: Equatable, Sendable {
    public let day: String
    /// Beats per minute.
    public let restingHr: Double?
    /// Milliseconds.
    public let hrv: Double?

    public init(day: String, restingHr: Double?, hrv: Double?) {
        self.day = day
        self.restingHr = restingHr
        self.hrv = hrv
    }
}

/// The nights and the window to average them over.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct CutStressInput: Equatable, Sendable {
    public let nights: [CutStressNight]
    /// A Monday. Nil: start at the earliest night that has an admitted value.
    public let firstWeekStart: String?
    public let today: String
    /// The fewest admitted nights a week needs before it has a mean. 1 to 7.
    public let minNightsPerWeek: Int
    /// The most weeks shown, counted back from today's week. At least 1.
    public let maxWeeks: Int

    public init(nights: [CutStressNight], firstWeekStart: String?, today: String,
                minNightsPerWeek: Int = 4, maxWeeks: Int = 26) {
        self.nights = nights
        self.firstWeekStart = firstWeekStart
        self.today = today
        self.minNightsPerWeek = minNightsPerWeek
        self.maxWeeks = maxWeeks
    }
}

/// One Monday week.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct CutStressWeek: Equatable, Sendable {
    public let weekStart: String
    /// Nil: fewer than `minNightsPerWeek` admitted nights ("not measured").
    public let restingHrMean: Double?
    public let restingHrNights: Int
    /// Nil: fewer than `minNightsPerWeek` admitted nights ("not measured").
    public let hrvMean: Double?
    public let hrvNights: Int
    public let isCurrentWeek: Bool

    public init(weekStart: String, restingHrMean: Double?, restingHrNights: Int, hrvMean: Double?,
                hrvNights: Int, isCurrentWeek: Bool) {
        self.weekStart = weekStart
        self.restingHrMean = restingHrMean
        self.restingHrNights = restingHrNights
        self.hrvMean = hrvMean
        self.hrvNights = hrvNights
        self.isCurrentWeek = isCurrentWeek
    }
}

/// The difference between the earliest and the latest week that have a mean.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct CutStressChange: Equatable, Sendable {
    public let fromWeekStart: String
    public let toWeekStart: String
    public let from: Double
    public let to: Double
    /// `to` minus `from`.
    public let delta: Double

    public init(fromWeekStart: String, toWeekStart: String, from: Double, to: Double, delta: Double) {
        self.fromWeekStart = fromWeekStart
        self.toWeekStart = toWeekStart
        self.from = from
        self.to = to
        self.delta = delta
    }
}

/// What was left out, and why. `invalidDay`, `future` and `duplicateDay` count whole nights;
/// `nonFinite` and `outOfRange` count single values.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct CutStressRejections: Equatable, Sendable {
    public let nonFinite: Int
    public let outOfRange: Int
    public let invalidDay: Int
    public let future: Int
    public let duplicateDay: Int

    public init(nonFinite: Int, outOfRange: Int, invalidDay: Int, future: Int, duplicateDay: Int) {
        self.nonFinite = nonFinite
        self.outOfRange = outOfRange
        self.invalidDay = invalidDay
        self.future = future
        self.duplicateDay = duplicateDay
    }
}

/// Why an input could not be used. The first cause in this order is reported: `today`, `parameters`,
/// `firstWeekStart`.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum CutStressInvalidInput: String, Equatable, Sendable {
    case today, firstWeekStart, parameters
}

/// The weekly means, the change across them and what was left out.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct CutStressResult: Equatable, Sendable {
    /// Contiguous Monday weeks, ascending. Empty when nothing can be shown.
    public let weeks: [CutStressWeek]
    public let restingHrChange: CutStressChange?
    public let hrvChange: CutStressChange?
    public let rejections: CutStressRejections
    public let invalidInput: CutStressInvalidInput?

    public init(weeks: [CutStressWeek], restingHrChange: CutStressChange?, hrvChange: CutStressChange?,
                rejections: CutStressRejections, invalidInput: CutStressInvalidInput?) {
        self.weeks = weeks
        self.restingHrChange = restingHrChange
        self.hrvChange = hrvChange
        self.rejections = rejections
        self.invalidInput = invalidInput
    }
}

/// Weekly means of nightly resting heart rate and HRV (stage 6 specification §7.2).
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum CutStressTrend {
    /// The weekly means for `input` (§7.2). Never throws or traps.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func weekly(_ input: CutStressInput) -> CutStressResult {
        // Step 1, in the order the step lists its causes.
        guard let todayNumber = CanonicalDay.number(input.today),
              let lastWeek = weekNumber(input.today) else { return invalid(.today) }
        guard input.minNightsPerWeek >= 1, input.minNightsPerWeek <= daysPerWeek,
              input.maxWeeks >= 1 else { return invalid(.parameters) }
        var firstWeek: Int?
        if let firstWeekStart = input.firstWeekStart {
            guard let number = CanonicalDay.number(firstWeekStart), weekNumber(firstWeekStart) == number,
                  number <= todayNumber else { return invalid(.firstWeekStart) }
            firstWeek = number
        }

        // Step 2: whole nights. A night is rejected for its day before anything else is looked at;
        // among the nights left, the last in input order stands for its day.
        var invalidDay = 0, future = 0, duplicateDay = 0
        var kept: [Int: CutStressNight] = [:]
        for night in input.nights {
            guard let number = CanonicalDay.number(night.day) else {
                invalidDay += 1
                continue
            }
            guard number <= todayNumber else {
                future += 1
                continue
            }
            if kept.updateValue(night, forKey: number) != nil { duplicateDay += 1 }
        }

        // Step 3: each metric is judged by its own bounds, the ones `ChargeBaselines` and
        // `HRVReadiness` apply. Ascending day order makes each week's sum independent of input order.
        let restingHrBounds = Baselines.restingHRCfg, hrvBounds = Baselines.hrvCfg
        let judged = kept.keys.sorted().map { number -> JudgedNight in
            let night = kept[number]
            return JudgedNight(number: number, restingHr: judge(night?.restingHr, restingHrBounds),
                               hrv: judge(night?.hrv, hrvBounds))
        }

        // Step 4. The earliest shown week is never more than `maxWeeks - 1` weeks before today's.
        // 0001-01-01 is a Monday, so clamping the count of weeks keeps `bound` a canonical Monday and
        // the multiplication cannot overflow whatever `maxWeeks` is.
        let weeksBack = min(input.maxWeeks - 1, (lastWeek - CanonicalDay.firstDayNumber) / daysPerWeek)
        let bound = lastWeek - daysPerWeek * weeksBack
        let earliestMeasured = judged.first { $0.restingHr.admitted != nil || $0.hrv.admitted != nil }
        let unclamped = firstWeek ?? earliestMeasured.map { mondayNumber($0.number) }
        let start = unclamped.map { max($0, bound) }

        // SPEC-NOTE: §7.2 step 3 comes before step 4, and step 5 says nights before `start` "are unused
        // and not counted as rejected". Read here as: a value on a night before the first shown week
        // adds nothing to `nonFinite` or `outOfRange` either, so the counters describe the weeks shown.
        // With no week shown, no value is counted. Whole-night rejections (step 2) are counted always.
        var nonFinite = 0, outOfRange = 0
        var sums: [Int: WeekSums] = [:]
        if let start {
            for night in judged where night.number >= start {
                var week = sums[mondayNumber(night.number)] ?? WeekSums()
                for (value, isHrv) in [(night.restingHr, false), (night.hrv, true)] {
                    if value.isNonFinite { nonFinite += 1 }
                    if value.isOutOfRange { outOfRange += 1 }
                    guard let admitted = value.admitted else { continue }
                    if isHrv {
                        week.hrvSum += admitted
                        week.hrvNights += 1
                    } else {
                        week.restingHrSum += admitted
                        week.restingHrNights += 1
                    }
                }
                sums[mondayNumber(night.number)] = week
            }
        }

        // Steps 5 and 6: every Monday from `start` to today's week, measured or not.
        var weeks: [CutStressWeek] = []
        if let start {
            for monday in stride(from: start, through: lastWeek, by: daysPerWeek) {
                let week = sums[monday] ?? WeekSums()
                weeks.append(CutStressWeek(
                    weekStart: CanonicalDay.key(monday),
                    restingHrMean: mean(week.restingHrSum, week.restingHrNights, input.minNightsPerWeek),
                    restingHrNights: week.restingHrNights,
                    hrvMean: mean(week.hrvSum, week.hrvNights, input.minNightsPerWeek),
                    hrvNights: week.hrvNights,
                    isCurrentWeek: monday == lastWeek))
            }
        }

        return CutStressResult(
            weeks: weeks,
            restingHrChange: change(weeks, \.restingHrMean),
            hrvChange: change(weeks, \.hrvMean),
            rejections: CutStressRejections(nonFinite: nonFinite, outOfRange: outOfRange,
                                            invalidDay: invalidDay, future: future,
                                            duplicateDay: duplicateDay),
            invalidInput: nil)
    }

    private static let daysPerWeek = 7

    /// One value after §7.2 step 3: admitted, or dropped for one of two reasons, or absent.
    private struct JudgedValue {
        var admitted: Double?
        var isNonFinite = false
        var isOutOfRange = false
    }

    private struct JudgedNight {
        let number: Int
        let restingHr: JudgedValue
        let hrv: JudgedValue
    }

    private struct WeekSums {
        var restingHrSum = 0.0
        var restingHrNights = 0
        var hrvSum = 0.0
        var hrvNights = 0
    }

    /// An invalid input gives an empty result: no weeks, no change, nothing counted, because nothing
    /// was judged (§7.2 step 1).
    private static func invalid(_ cause: CutStressInvalidInput) -> CutStressResult {
        CutStressResult(weeks: [], restingHrChange: nil, hrvChange: nil,
                        rejections: CutStressRejections(nonFinite: 0, outOfRange: 0, invalidDay: 0,
                                                        future: 0, duplicateDay: 0),
                        invalidInput: cause)
    }

    /// The day number of the Monday of the week containing `key`; nil unless `key` is canonical.
    private static func weekNumber(_ key: String) -> Int? {
        CanonicalDay.weekStart(containing: key).flatMap(CanonicalDay.number)
    }

    /// The day number of the Monday of the week containing a canonical day number.
    private static func mondayNumber(_ number: Int) -> Int {
        weekNumber(CanonicalDay.key(number)) ?? number
    }

    /// §7.2 step 3 for one value: not finite, then outside the config's inclusive bounds.
    private static func judge(_ value: Double?, _ bounds: MetricCfg) -> JudgedValue {
        guard let value else { return JudgedValue() }
        guard value.isFinite else { return JudgedValue(isNonFinite: true) }
        guard value >= bounds.minVal, value <= bounds.maxVal else { return JudgedValue(isOutOfRange: true) }
        return JudgedValue(admitted: value)
    }

    /// §7.2 step 6: the quantized arithmetic mean, or nil ("not measured") below the minimum.
    private static func mean(_ sum: Double, _ nights: Int, _ minNights: Int) -> Double? {
        guard nights >= minNights, nights > 0 else { return nil }
        let value = CutScorecard.quantize(sum / Double(nights))
        return value.isFinite ? value : nil
    }

    /// §7.2 step 7: from the earliest week with a mean to the latest, when they are two different weeks.
    private static func change(_ weeks: [CutStressWeek],
                               _ metric: KeyPath<CutStressWeek, Double?>) -> CutStressChange? {
        let measured = weeks.filter { $0[keyPath: metric] != nil }
        guard measured.count >= 2, let first = measured.first, let last = measured.last,
              let from = first[keyPath: metric], let to = last[keyPath: metric] else { return nil }
        let delta = CutScorecard.quantize(to - from)
        guard delta.isFinite else { return nil }
        return CutStressChange(fromWeekStart: first.weekStart, toWeekStart: last.weekStart, from: from,
                               to: to, delta: delta)
    }
}
