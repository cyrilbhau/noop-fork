import Foundation
import WhoopStore

// The one per-day formatter of the Coach (stage 2 specification §6.1). The in-app Coach context and the
// coach packet both print a day through this type, so the two cannot drift: the packet differs only in
// its `CoachDayStyle` (labels, the separator after the day key, and the strain scale).
//
// Pure: no store, no clock, no `Calendar`, no `TimeZone`, no `Date`, no `Locale`. Every function is
// total. No Kotlin twin: the owner has skipped Android for the personal fork (stage 1 ruling R43).

/// How one day is worded: the three labels that differ between the in-app Coach and the packet, the
/// text between the day key and the first field, and the strain scale.
public struct CoachDayStyle: Equatable, Sendable {
    public let recoveryLabel: String
    public let strainLabel: String
    public let sleepLabel: String
    /// Between the day key and the first field.
    public let daySeparator: String
    /// Multiplies the stored 0–100 strain before it is formatted.
    public let strainFactor: Double

    public init(recoveryLabel: String, strainLabel: String, sleepLabel: String, daySeparator: String,
                strainFactor: Double) {
        self.recoveryLabel = recoveryLabel
        self.strainLabel = strainLabel
        self.sleepLabel = sleepLabel
        self.daySeparator = daySeparator
        self.strainFactor = strainFactor
    }

    /// The in-app Coach context exactly as it was: "charge", "effort", "rest", ":, ", 1.0.
    public static let coachContext = CoachDayStyle(recoveryLabel: "charge", strainLabel: "effort",
                                                   sleepLabel: "rest", daySeparator: ":, ",
                                                   strainFactor: 1.0)

    /// The packet: "recovery", "strain", "sleep", ": ", and the factor of the owner's display scale.
    public static func packet(strainFactor: Double) -> CoachDayStyle {
        CoachDayStyle(recoveryLabel: "recovery", strainLabel: "strain", sleepLabel: "sleep",
                      daySeparator: ": ", strainFactor: strainFactor)
    }
}

/// The shared per-day lines and averages of the Coach context and the coach packet.
public enum CoachDayFormat {
    /// "—" (U+2014). The one token for a value that was not measured.
    public static let notMeasured = "\u{2014}"

    /// Rule F1: the greatest magnitude that is still a value. Above it, as for NaN and the
    /// infinities, a number is treated as not measured (and `Int(_:)` can no longer trap on it).
    static let magnitudeLimit = 1e15

    /// Rule F1. `value` when it is finite and within `magnitudeLimit`, else nil.
    static func measured(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value.magnitude <= magnitudeLimit else { return nil }
        return value
    }

    /// The nine value fields of one day, in order: recovery, strain, sleep, deep, REM, light, eff,
    /// HRV, RHR. Each is "<label> <value>" or "<label> —".
    public static func fields(_ day: DailyMetric, style: CoachDayStyle) -> [String] {
        let recovery = measured(day.recovery).map { "\(Int($0.rounded()))" }
        let strain = scaledStrain(day.strain, style: style).map { String(format: "%.1f", $0) }
        let hrv = measured(day.avgHrv).map { "\(Int($0.rounded()))ms" }
        // The stored resting heart rate is a whole number and prints as it is, as it always has.
        let rhr = day.restingHr.map { "\($0)bpm" }
        return [
            style.recoveryLabel + " " + (recovery ?? notMeasured),
            style.strainLabel + " " + (strain ?? notMeasured),
            style.sleepLabel + " " + hours(day.totalSleepMin),
            "deep " + hours(day.deepMin),
            "REM " + hours(day.remMin),
            "light " + hours(day.lightMin),
            "eff " + efficiencyPercent(day.efficiency),
            "HRV " + (hrv ?? notMeasured),
            "RHR " + (rhr ?? notMeasured),
        ]
    }

    /// day + style.daySeparator + fields joined by ", ".
    public static func dayLine(_ day: DailyMetric, style: CoachDayStyle) -> String {
        day.day + style.daySeparator + fields(day, style: style).joined(separator: ", ")
    }

    /// "<recovery>: A, <strain>: B, sleep: Ch, HRV: D ms, RHR: E bpm" over the rows given.
    public static func primaryAveragesLine(_ days: [DailyMetric], style: CoachDayStyle) -> String {
        // SPEC-NOTE: §6.1 writes the third label as "<sleep>", which with the Coach style would print
        // "rest:". The in-app Coach has always printed "sleep:" on this line ("rest" only on the day
        // line) and §8.1 requires its bytes unchanged, so the word is "sleep" in both styles.
        let sleepMinutes = days.compactMap { measured($0.totalSleepMin) }
        let sleep = mean(sleepMinutes).map { String(format: "%.1f", $0 / 60) } ?? notMeasured
        return "\(style.recoveryLabel): \(averageWhole(days.compactMap { measured($0.recovery) }))"
            + ", \(style.strainLabel): "
            + averageOneDecimal(days.compactMap { scaledStrain($0.strain, style: style) })
            + ", sleep: \(sleep)h"
            + ", HRV: \(averageWhole(days.compactMap { measured($0.avgHrv) })) ms"
            + ", RHR: \(averageWhole(days.compactMap { whole($0.restingHr) })) bpm"
    }

    /// "SpO2: A%, respiration: B/min, skin-temp deviation: C°C, steps: D/day, active energy: Ekcal/day".
    /// Used by the in-app Coach only.
    public static func vitalsAveragesLine(_ days: [DailyMetric]) -> String {
        "SpO2: \(averageWhole(days.compactMap { measured($0.spo2Pct) }))%"
            + ", respiration: \(averageOneDecimal(days.compactMap { measured($0.respRateBpm) }))/min"
            + ", skin-temp deviation: "
            + "\(averageOneDecimal(days.compactMap { measured($0.skinTempDevC) }))°C"
            + ", steps: \(averageWhole(days.compactMap { whole($0.steps) }))/day"
            + ", active energy: \(averageWhole(days.compactMap { measured($0.activeKcalEst) }))kcal/day"
    }

    /// A stored efficiency as "94%", normalising a value stored as a percentage; "—" otherwise.
    public static func efficiencyPercent(_ raw: Double?) -> String {
        guard var efficiency = measured(raw), efficiency > 0 else { return notMeasured }
        if efficiency > efficiencyPercentageThreshold { efficiency /= 100 }
        guard efficiency > 0, efficiency <= 1 else { return notMeasured }
        return "\(Int((efficiency * 100).rounded()))%"
    }

    /// A stored efficiency above this is a percentage (94), not a fraction (0.94).
    static let efficiencyPercentageThreshold = 1.5

    // MARK: - Parts

    /// The stored strain on the style's scale; nil when the stored value or the product is not a
    /// value under rule F1. With a factor of 1.0 the product is the stored value (rule F2).
    private static func scaledStrain(_ stored: Double?, style: CoachDayStyle) -> Double? {
        measured(stored).flatMap { measured($0 * style.strainFactor) }
    }

    /// Minutes as "7.4h", or the dash.
    private static func hours(_ minutes: Double?) -> String {
        measured(minutes).map { String(format: "%.1fh", $0 / 60) } ?? notMeasured
    }

    /// A stored whole number as a value to average.
    private static func whole(_ value: Int?) -> Double? {
        // SPEC-NOTE: §6.1 states rule F1 for the Double fields. It is applied to the whole-number
        // fields (resting heart rate, steps) in the averages as well, because `Int(_:)` of a mean near
        // `Int.max` would trap and every function here must be total. No real row is affected.
        measured(value.map(Double.init))
    }

    /// The arithmetic mean in the order given; nil for no values.
    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// The mean to the nearest whole number, halves away from zero (rule F3); the dash for no values.
    private static func averageWhole(_ values: [Double]) -> String {
        mean(values).map { "\(Int($0.rounded()))" } ?? notMeasured
    }

    /// The mean to one decimal; the dash for no values.
    private static func averageOneDecimal(_ values: [Double]) -> String {
        mean(values).map { String(format: "%.1f", $0) } ?? notMeasured
    }
}
