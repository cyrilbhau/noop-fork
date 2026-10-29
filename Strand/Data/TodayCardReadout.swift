import Foundation
import StrandAnalytics
import WhoopStore

/// Presentation resolved from an in-memory snapshot, shared by the redesigned Today rows and tiles.
struct TodayCardReadout: Equatable {
    enum Tint: Equatable { case hrv, heart, breath, lift, stress, recovery, sleep, temp, coach, muted }
    enum Tap: Equatable { case route(TabRoute), stepSources, coachSheet, none }

    var value: String? = nil
    var unit: String? = nil
    var caption: String? = nil
    var captionIsStale = false
    var tint: Tint
    var tap: Tap = .none
    var sparkKey: String? = nil
    /// Steps keeps its source-specific destination metadata while its current interaction opens a sheet.
    var route: TabRoute? = nil
}

/// A value snapshot; resolving a card never performs a repository read or consults stored preferences.
struct TodayCardInputs {
    var isToday = true
    var selectedDayKey = ""
    var displayDay: DailyMetric? = nil
    var hrvCarry: DailyMetric? = nil
    var restingHrCarry: DailyMetric? = nil
    var vitalsCarry: DailyMetric? = nil
    var respCarry: DailyMetric? = nil
    var skinTempCarry: DailyMetric? = nil
    var stepCount: Double? = nil
    var stepsDetail: MetricDescriptor? = nil
    var importedStepsDay: Int? = nil
    var caloriesCount: Double? = nil
    var caloriesDetail: MetricDescriptor? = nil
    var hasImportedKcal = false
    var stressToday: Double? = nil
    var stressPoint: (day: String, value: Double)? = nil
    var fitnessAgePoint: (day: String, value: Double)? = nil
    var vo2maxPoint: (day: String, value: Double)? = nil
    var vitalityPoint: (day: String, value: Double)? = nil
    var hydrationTotalML: Double? = nil
    var hydrationGoalML: Int? = nil
    var activeIsWhoop4: Bool? = nil
    var fahrenheit = false
    var locale = AppLanguage.activeLocale
    var rollingStepsAverage: RollingStepsAverage? = nil
}

/// Owns a completed value snapshot independently of the legacy loader's incrementally published fields.
/// A request identity also distinguishes two refreshes of the same day, not just changes of selection.
struct TodayCardSnapshotState {
    struct Request: Equatable {
        fileprivate let identity: UUID
        let dayKey: String
        let dayOffset: Int
    }

    private var activeRequest: Request?
    private(set) var inputs: TodayCardInputs?

    mutating func begin(dayKey: String, dayOffset: Int) -> Request {
        let request = Request(identity: UUID(), dayKey: dayKey, dayOffset: dayOffset)
        activeRequest = request
        inputs = nil
        return request
    }

    @discardableResult
    mutating func complete(_ snapshot: TodayCardInputs, for request: Request,
                           selectedDayKey: String, selectedDayOffset: Int, isCancelled: Bool) -> Bool {
        guard !isCancelled, request == activeRequest,
              request.dayKey == selectedDayKey, request.dayOffset == selectedDayOffset,
              snapshot.selectedDayKey == request.dayKey,
              snapshot.isToday == (request.dayOffset == 0) else { return false }
        inputs = snapshot
        return true
    }
}

enum TodayCardResolver {
    static func keyMetricTwin(for card: DashboardCard) -> KeyMetric? {
        switch card {
        case .hrv: return .hrv
        case .restingHr: return .restingHr
        case .respiratory: return .respiratory
        case .steps: return .steps
        case .bloodOxygen: return .bloodOxygen
        case .skinTemp: return .skinTemp
        case .calories: return .calories
        default: return nil
        }
    }

    /// The editor retains gated cards. Only an implicit default is deduplicated against rendered rows.
    static func selection(raw: String, visibleKeyMetrics: [KeyMetric]?) -> [DashboardCard] {
        let selected = DashboardCardPrefs.decodeEnabled(raw)
        guard raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let visibleKeyMetrics else { return selected }
        return selected.filter { card in
            guard let twin = keyMetricTwin(for: card) else { return true }
            return !visibleKeyMetrics.contains(twin)
        }
    }

    static func renderList(raw: String, hydrationEnabled: Bool, coachEnabled: Bool,
                           visibleKeyMetrics: [KeyMetric]?) -> [DashboardCard] {
        selection(raw: raw, visibleKeyMetrics: visibleKeyMetrics).filter {
            ($0 != .hydration || hydrationEnabled) && ($0 != .coach || coachEnabled)
        }
    }

    static func cardTitle(_ card: DashboardCard) -> String {
        switch card {
        case .hrv: return String(localized: "HRV")
        case .restingHr: return String(localized: "Resting heart rate")
        case .respiratory: return String(localized: "Respiratory rate")
        case .steps: return String(localized: "Steps")
        case .stepsAverage30: return String(localized: "30-day step average")
        case .stress: return String(localized: "Stress")
        case .fitnessAge: return String(localized: "Fitness age")
        case .vo2max: return String(localized: "VO₂ max")
        case .vitality: return String(localized: "Vitality")
        case .bloodOxygen: return String(localized: "Blood oxygen")
        case .skinTemp: return String(localized: "Skin temperature")
        case .sleep: return String(localized: "Sleep")
        case .calories: return String(localized: "Calories")
        case .hydration: return String(localized: "Hydration")
        case .coupled: return String(localized: "Coupled view")
        case .coach: return String(localized: "Coach")
        }
    }

    /// Twin rows keep their original captions, units, chart keys and routes, including nil captions.
    static func readout(_ metric: KeyMetric, _ inputs: TodayCardInputs) -> TodayCardReadout? {
        let day = inputs.displayDay
        func carried(_ value: String, from row: DailyMetric?) -> String? {
            guard inputs.isToday, let row else { return nil }
            let stamp = TodayView.carriedCaption(priorDayKey: row.day,
                                                todayKey: day?.day ?? inputs.selectedDayKey)
            return String(localized: "Last: \(value) · \(stamp)")
        }
        func metricReadout(value: String?, unit: String?, caption: String?, tint: TodayCardReadout.Tint,
                           key: String, route: TabRoute) -> TodayCardReadout {
            TodayCardReadout(value: value, unit: unit, caption: caption, tint: tint,
                             tap: .route(route), sparkKey: key, route: route)
        }
        switch metric {
        case .hrv:
            let own = day?.avgHrv
            let carry = own == nil && inputs.isToday ? inputs.hrvCarry : nil
            return metricReadout(value: own.map { String(Int($0.rounded())) }, unit: "ms",
                                 caption: carry?.avgHrv.flatMap { carried("\(Int($0.rounded())) ms", from: carry) },
                                 tint: .hrv, key: "hrv", route: .metric("hrv"))
        case .restingHr:
            let own = day?.restingHr
            let carry = own == nil && inputs.isToday ? inputs.restingHrCarry : nil
            return metricReadout(value: own.map { String($0) }, unit: "bpm",
                                 caption: carry?.restingHr.flatMap { carried("\($0) bpm", from: carry) },
                                 tint: .heart, key: "rhr", route: .metric("rhr"))
        case .respiratory:
            let own = day?.respRateBpm
            let carry = own == nil && inputs.isToday
                ? (inputs.vitalsCarry?.respRateBpm != nil ? inputs.vitalsCarry : inputs.respCarry) : nil
            return metricReadout(value: own.map { decimal($0, locale: inputs.locale) }, unit: "rpm",
                                 caption: carry?.respRateBpm.flatMap {
                                     carried(decimal($0, locale: inputs.locale) + " rpm", from: carry)
                                 }, tint: .breath, key: "resp_rate", route: .metric("resp_rate"))
        case .bloodOxygen:
            guard inputs.activeIsWhoop4 == false else {
                return TodayCardReadout(caption: inputs.activeIsWhoop4 == true
                    ? String(localized: "Not measured on WHOOP 4.0") : String(localized: "Not measured offline"),
                                        tint: .muted)
            }
            // Preserve the redesigned row's measured-value contract: no experimental candidate fallback.
            let own = day?.spo2Pct
            let carry = own == nil && inputs.isToday ? inputs.vitalsCarry : nil
            return metricReadout(value: own.map { String(Int($0.rounded())) }, unit: "%",
                                 caption: carry?.spo2Pct.flatMap { carried("\(Int($0.rounded()))%", from: carry) },
                                 tint: .hrv, key: "spo2", route: .metric("spo2"))
        case .skinTemp:
            let own = day?.skinTempDevC
            let carry = own == nil && inputs.isToday
                ? [inputs.vitalsCarry, inputs.skinTempCarry].compactMap { $0 }.first { $0.skinTempDevC != nil }
                : nil
            func format(_ value: Double) -> String {
                SkinTempDisplay.formatReading(.init(value: value, kind: .deviation), fahrenheit: inputs.fahrenheit)
            }
            return metricReadout(value: own.map(format), unit: nil,
                                 caption: carry?.skinTempDevC.flatMap { carried(format($0), from: carry) }
                                    ?? String(localized: "Relative to baseline"),
                                 tint: .temp, key: "skin_temp", route: .metric("skin_temp"))
        case .steps:
            let measured = day?.steps != nil
            let imported = !measured && inputs.importedStepsDay != nil
            let caption = inputs.stepCount == nil ? String(localized: "No step data for this day")
                : measured ? String(localized: "Strap")
                : imported ? "Apple Health" : String(localized: "Estimated from strap")
            let value = inputs.stepCount.map {
                let text = $0.formatted(.number.precision(.fractionLength(0)).locale(inputs.locale))
                return measured || imported ? text : "~" + text
            }
            let key = inputs.stepsDetail?.key ?? "steps_est"
            var result = metricReadout(value: value, unit: nil, caption: caption, tint: .lift, key: key,
                                       route: .metricSourced(key: key, source: inputs.stepsDetail?.source ?? Repository.whoopSource))
            result.tap = .stepSources
            return result
        case .calories:
            let key = inputs.caloriesDetail?.key ?? "energy_kcal"
            return metricReadout(value: inputs.caloriesCount.map { String(Int($0.rounded())) }, unit: "kcal",
                                 caption: nil, tint: .temp, key: "energy_kcal",
                                 route: .metricSourced(key: key, source: inputs.caloriesDetail?.source ?? Repository.whoopSource))
        case .weight, .charge, .effort, .rest:
            return nil
        }
    }

    static func readout(_ card: DashboardCard, _ inputs: TodayCardInputs) -> TodayCardReadout {
        if let metric = keyMetricTwin(for: card), var result = readout(metric, inputs) {
            // Tiles add context in otherwise empty caption slots; the underlying reading remains shared.
            if result.caption == nil {
                if result.value == nil { result.caption = String(localized: "No data") }
                else if card == .calories {
                    result.caption = inputs.hasImportedKcal ? "Apple Health" : String(localized: "Estimated from strap")
                } else { result.caption = nightCaption(inputs) }
            }
            return result
        }
        switch card {
        case .stepsAverage30:
            let result = inputs.rollingStepsAverage
            return routed(value: result?.mean.map {
                $0.formatted(.number.precision(.fractionLength(0)).locale(inputs.locale))
            }, caption: result.map { String(localized: "\($0.observedDays) of 30 days") }
                ?? String(localized: "No data"), tint: .lift,
                          route: .metricSourced(key: "steps", source: MetricCatalog.combinedStepsSource))
        case .stress:
            let point = validPoint(inputs.stressPoint, onOrBefore: inputs.selectedDayKey)
            let score = inputs.isToday ? inputs.stressToday : point?.value
            var caption = score.map(stressCaption) ?? String(localized: "No data")
            if !inputs.isToday, let point, point.day != inputs.selectedDayKey {
                caption += " · " + asOfCaption(point.day, locale: inputs.locale)
            }
            return routed(value: score.map { decimal($0, locale: inputs.locale) },
                          unit: String(localized: "of \("3")"), caption: caption, tint: .stress, route: .stress)
        case .fitnessAge, .vo2max, .vitality:
            let candidate = card == .fitnessAge ? inputs.fitnessAgePoint
                : card == .vo2max ? inputs.vo2maxPoint : inputs.vitalityPoint
            let point = validPoint(candidate, onOrBefore: inputs.selectedDayKey)
            let value = point.map {
                card == .fitnessAge ? fitnessAgeBoundSymbol($0.value) + String(Int($0.value.rounded()))
                    : card == .vo2max ? decimal($0.value, locale: inputs.locale) : String(Int($0.value.rounded()))
            }
            let caption = point.map { point in
                card == .vo2max
                    ? String(localized: "Estimated · as of \(shortDate(point.day, locale: inputs.locale))")
                    : asOfCaption(point.day, locale: inputs.locale)
            } ?? String(localized: "No data")
            var result = routed(value: value, unit: card == .fitnessAge ? String(localized: "yrs") : nil,
                                caption: caption, tint: card == .vitality ? .sleep : .recovery,
                                route: .metric(card == .fitnessAge ? "fitness_age" : card == .vo2max ? "vo2max_est" : "vitality"))
            result.captionIsStale = point.map { isStale(day: $0.day, relativeTo: inputs.selectedDayKey) } ?? false
            return result
        case .sleep:
            let value = inputs.displayDay?.totalSleepMin.map { UnitFormatter.nightSleepDurationDisplay(minutes: $0) }
            return routed(value: value, caption: value == nil ? String(localized: "No data") : nightCaption(inputs),
                          tint: .sleep, route: inputs.isToday ? .sleep : .metric("sleep_total_min"))
        case .hydration:
            guard inputs.isToday else {
                return TodayCardReadout(caption: String(localized: "Logged for today only"), tint: .hrv)
            }
            let value = inputs.hydrationGoalML.map {
                HydrationGoal.cardValueString(totalML: inputs.hydrationTotalML ?? 0, goalML: $0)
            }
            return routed(value: value, caption: value == nil ? String(localized: "No data") : String(localized: "Today's fluid"),
                          tint: .hrv, route: .hydration)
        case .coupled:
            return routed(value: nil, caption: String(localized: "Recovery, strain and sleep in one glance"),
                          tint: .recovery, route: .coupled)
        case .coach:
            return TodayCardReadout(caption: String(localized: "Ask about your recovery, strain, sleep and workouts, grounded in your own numbers."),
                                    tint: .coach, tap: .coachSheet)
        case .hrv, .restingHr, .respiratory, .steps, .bloodOxygen, .skinTemp, .calories:
            preconditionFailure("Every twin is resolved before the card-only cases")
        }
    }

    static func latestPoint(_ points: [(day: String, value: Double)], onOrBefore day: String) -> (day: String, value: Double)? {
        points.filter { $0.day <= day && $0.value.isFinite }.max { $0.day < $1.day }
    }

    /// StressModel parses its chart days at UTC midnight; conversion must use the same time zone.
    static func utcDayKey(_ date: Date) -> String { dayFormatter().string(from: date) }

    static func isStale(day: String, relativeTo selectedDay: String) -> Bool {
        let formatter = dayFormatter()
        guard let date = formatter.date(from: day), let selected = formatter.date(from: selectedDay) else { return false }
        return selected.timeIntervalSince(date) > 14 * 24 * 60 * 60
    }

    private static func validPoint(_ point: (day: String, value: Double)?, onOrBefore day: String) -> (day: String, value: Double)? {
        guard let point, point.day <= day, point.value.isFinite else { return nil }
        return point
    }

    private static func routed(value: String?, unit: String? = nil, caption: String?,
                               tint: TodayCardReadout.Tint, route: TabRoute) -> TodayCardReadout {
        TodayCardReadout(value: value, unit: unit, caption: caption, tint: tint, tap: .route(route), route: route)
    }

    private static func decimal(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    private static func stressCaption(_ score: Double) -> String {
        switch StressBand(score: score) {
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Moderate")
        case .high: return String(localized: "High")
        }
    }

    private static func nightCaption(_ inputs: TodayCardInputs) -> String {
        inputs.isToday ? String(localized: "Last night")
            : String(localized: "Night of \(shortDate(inputs.selectedDayKey, locale: inputs.locale))")
    }

    private static func asOfCaption(_ day: String, locale: Locale) -> String {
        String(localized: "as of \(shortDate(day, locale: locale))")
    }

    private static func shortDate(_ day: String, locale: Locale) -> String {
        let formatter = dayFormatter()
        guard let date = formatter.date(from: day) else { return day }
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
