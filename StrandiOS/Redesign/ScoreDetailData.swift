import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Shared data for the Recovery and Strain detail screens (redesign Phase 4)
//
// Presentation-only. Every value here is read from the existing data layer through the SAME selectors the
// Today screens use (`TodayView.lastScoredRecoveryDay`, `LiquidTodayView.ChargeDisplay`,
// `ChargeBreakdownWiring`, `StrainScorer.effectiveEffort`, `CoupledView.optimalStrainRange`), so a detail
// screen and the Today ring it was opened from cannot disagree. Nothing is scored or stored here.

/// The day a detail screen describes, resolved exactly as Liquid Today resolves its selected day.
@MainActor
struct ScoreDetailDay {
    /// The `Repository` day key the day-scoped reads key on.
    let key: String
    /// True for today (Liquid's offset 0): only today carries a prior score, a live Strain or a calibration count.
    let isToday: Bool
    /// A moment inside the logical day; its calendar start anchors the HR window.
    let logicalDay: Date
    /// The stored row for the day, or nil when none exists.
    let row: DailyMetric?

    /// `dayKey` nil, or the key of today's row, or today's logical key, all mean today.
    static func resolve(dayKey: String?, repo: Repository, now: Date = Date()) -> ScoreDetailDay {
        let logicalKey = Repository.logicalDayKey(now)
        let todayKey = repo.today?.day ?? Repository.localDayKey(Repository.logicalDay(now))
        if dayKey == nil || dayKey == todayKey || dayKey == logicalKey {
            return ScoreDetailDay(key: todayKey, isToday: true, logicalDay: Repository.logicalDay(now),
                                  row: repo.today ?? repo.days.last(where: { $0.day == todayKey }))
        }
        let key = dayKey ?? todayKey
        return ScoreDetailDay(key: key, isToday: false,
                              logicalDay: ScoreDetailFormat.date(fromKey: key) ?? Repository.logicalDay(now),
                              row: repo.days.last(where: { $0.day == key }))
    }

    /// The HR / workout window, identical to Liquid Today's: the day-cycle onset markers when that mode is on,
    /// else calendar midnight to now (today) or to the next midnight (a past day).
    func window(repo: Repository, mode: DayCycleMode, now: Date = Date()) async -> (from: Int, to: Int) {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: logicalDay)
        let next = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let calendarFrom = Int(dayStart.timeIntervalSince1970)
        let calendarTo = isToday ? Int(now.timeIntervalSince1970) : Int(next.timeIntervalSince1970)
        let nextDayKey = Repository.localDayKey(next)
        let markers = mode == .sleepOnset
            ? await repo.exploreSeries(key: DayCycleIntelligenceIntegration.onsetKey, source: Repository.whoopSource)
            : []
        let from = markers.last(where: { $0.day == key }).map { Int($0.value) } ?? calendarFrom
        let toExclusive = markers.last(where: { $0.day == nextDayKey }).map { Int($0.value) } ?? calendarTo
        return (from, max(from, toExclusive - 1))
    }

    /// The 30 day keys ending on this day, oldest first.
    var last30Keys: [String] {
        guard let end = ScoreDetailFormat.date(fromKey: key) else { return [key] }
        let cal = Calendar.current
        return (0..<30).reversed().map { back in
            Repository.localDayKey(cal.date(byAdding: .day, value: -back, to: end) ?? end)
        }
    }
}

// MARK: - Provenance

/// Where a displayed score came from, so imported WHOOP and NOOP-computed scores stay distinguishable.
enum ScoreProvenance: Equatable {
    case computed
    case whoopImport
    /// Any other real source, carrying its existing display label (`TodayView.provenanceDisplayLabel`).
    case other(String)

    @MainActor static func classify(rawSource: String, deviceId: String) -> ScoreProvenance {
        if rawSource.hasSuffix("-noop") { return .computed }
        if rawSource == deviceId || rawSource == Repository.whoopSource { return .whoopImport }
        let label = TodayView.provenanceDisplayLabel(rawSource: rawSource, deviceId: deviceId)
        return label == String(localized: "On-device") ? .computed : .other(label)
    }

    /// The caption text; `scale` names the Strain display scale for a computed score.
    func caption(scale: String? = nil) -> String {
        switch self {
        case .computed:
            if let scale { return String(localized: "NOOP score · \(scale) scale · computed on iPhone") }
            return String(localized: "NOOP score · computed on iPhone")
        case .whoopImport:
            return String(localized: "WHOOP import")
        case .other(let label):
            return label
        }
    }
}

// MARK: - Recovery

/// One "What shaped it" row: the day's value, the user's typical range (when a usable baseline exists) and
/// the driver's signed contribution from `ChargeBreakdownWiring` (when the night could be broken down).
struct RecoveryFactor: Identifiable {
    enum Kind: String { case hrv, restingHR, sleep, respiratory }
    let kind: Kind
    let value: Double?
    /// Baseline ± one robust sigma (`Baselines.sigma`): the same band `Baselines.deviation` calls normal,
    /// so the drawn band and the "usual range" sub-line cannot disagree.
    let typical: ClosedRange<Double>?
    /// The driver's signed points, or nil when the term was not part of the breakdown.
    let deltaPoints: Int?
    var id: String { kind.rawValue }
}

struct RecoveryDetailModel {
    let day: ScoreDetailDay
    let display: LiquidTodayView.ChargeDisplay
    let readiness: ReadinessEngine.Readiness
    let factors: [RecoveryFactor]
    let provenance: ScoreProvenance?
    /// The 30 daily Recovery values ending on the day (nil = no score that day). The selected day's own
    /// score only; a carried prior score is not drawn as today's bar.
    let bars: [Double?]
    let barKeys: [String]

    @MainActor
    static func load(dayKey: String?, repo: Repository) async -> RecoveryDetailModel {
        let day = ScoreDetailDay.resolve(dayKey: dayKey, repo: repo)
        let row = day.row
        // Calibration and carry exactly as Liquid Today's load() resolves them.
        let calNights = day.isToday
            ? RecoveryScorer.calibrationNights(nightlyHrv: repo.chargeBaselines?.hrvHistory.values ?? [],
                                               dayKeys: repo.chargeBaselines?.hrvHistory.dayKeys ?? [],
                                               hasRecovery: row?.recovery != nil)
            : nil
        let prior = TodayView.lastScoredRecoveryDay(days: repo.days, selectedDayKey: day.key,
                                                    isToday: day.isToday, todayScored: row?.recovery != nil,
                                                    isCalibrating: calNights != nil)
        let display = LiquidTodayView.ChargeDisplay.resolve(todayRecovery: row?.recovery, priorScored: prior,
                                                            calibrationNights: calNights, todayKey: day.key)
        let readiness = ReadinessEngine.evaluate(days: repo.days, today: row?.day)

        // Sleep performance exactly as Today's Rest score (`TodayView.freshRestScore`).
        let restSeries = await repo.exploreSeries(key: "sleep_performance", source: Repository.whoopSource)
        let restByDay = Dictionary(restSeries.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        let restScore = TodayView.freshRestScore(todayValue: restByDay[day.key], lastDay: restSeries.last?.day,
                                                 lastValue: restSeries.last?.value,
                                                 isTodaySelected: day.isToday, todayKey: day.key)

        // The breakdown row Today's sheet reads: the carried scored day, else the day's own row.
        let breakdownRow = prior ?? row
        let baselines = repo.chargeBaselines
        let drivers: [ChargeDriver] = {
            guard let breakdownRow, let baselines else { return [] }
            return ChargeBreakdownWiring.breakdown(baselines: baselines, row: breakdownRow,
                                                   sleepPerfPercent: restScore)?.drivers ?? []
        }()
        func points(_ label: String) -> Int? { drivers.first(where: { $0.label == label })?.deltaPoints }
        func band(_ state: BaselineState?) -> ClosedRange<Double>? {
            guard let state, state.usable else { return nil }
            let sigma = Baselines.sigma(state)
            return (state.baseline - sigma)...(state.baseline + sigma)
        }
        let factors = [
            RecoveryFactor(kind: .hrv, value: breakdownRow?.avgHrv, typical: band(baselines?.hrv),
                           deltaPoints: points("Heart rate variability")),
            RecoveryFactor(kind: .restingHR, value: breakdownRow?.restingHr.map(Double.init),
                           typical: band(baselines?.restingHR), deltaPoints: points("Resting heart rate")),
            RecoveryFactor(kind: .sleep, value: restScore, typical: nil, deltaPoints: points("Sleep quality")),
            RecoveryFactor(kind: .respiratory, value: breakdownRow?.respRateBpm, typical: band(baselines?.resp),
                           deltaPoints: points("Respiratory rate")),
        ]

        // Provenance from the same resolver Liquid's hero badge asks, including the carried day.
        var provenance: ScoreProvenance?
        if display.pct != nil {
            let resolution = await repo.resolvedSeries(key: "recovery", source: Repository.whoopSource,
                                                       from: min(day.key, prior?.day ?? day.key), to: day.key)
            let winner = resolution.points.last(where: { $0.day == day.key })
                ?? prior.flatMap { p in resolution.points.last(where: { $0.day == p.day }) }
            provenance = winner.map { ScoreProvenance.classify(rawSource: $0.source, deviceId: repo.deviceId) }
        }

        let keys = day.last30Keys
        var byDay: [String: Double] = [:]
        for d in repo.days { if let r = d.recovery { byDay[d.day] = r } }
        return RecoveryDetailModel(day: day, display: display, readiness: readiness, factors: factors,
                                   provenance: provenance, bars: keys.map { byDay[$0] }, barKeys: keys)
    }
}

// MARK: - Strain

struct StrainDetailModel {
    let day: ScoreDetailDay
    /// The day's Effort on the stored 0–100 axis, via `StrainScorer.effectiveEffort` (live floor today).
    let effort: Double?
    /// The Recovery the optimal band is read from: the same value the Recovery screen shows.
    let recoveryForTarget: Double?
    let provenance: ScoreProvenance?
    let workouts: [WorkoutRow]
    /// Seconds in Zones 1…5 over the day's HR window, or nil when the window holds no HR.
    let zoneSeconds: [Double]?
    /// 30 daily Effort values (0–100) ending on the day; the last uses the same effective value as the hero.
    let bars: [Double?]
    let barKeys: [String]

    @MainActor
    static func load(dayKey: String?, repo: Repository, profile: ProfileStore, mode: DayCycleMode) async -> StrainDetailModel {
        let day = ScoreDetailDay.resolve(dayKey: dayKey, repo: repo)
        let row = day.row
        let window = await day.window(repo: repo, mode: mode)

        // ONE whole-window HR read feeds both the live Effort (today) and the zone split, with the explicit
        // whole-window limit Liquid Today uses (the 8000 default truncates a real day).
        let samples = await repo.hrSamples(from: window.from, to: window.to, limit: 200_000)
        let maxHR = profile.effortHRmax
        let restHR = row?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        let method = PuffinExperiment.effortMethod
        let sex = profile.sex
        let zoneSet = profile.hrZoneSet
        let isToday = day.isToday
        let (live, tiz) = await Task.detached(priority: .utility) { () -> (Double?, TimeInZone?) in
            let live = isToday
                ? StrainScorer.strain(samples, maxHR: maxHR, restingHR: restHR, method: method, sex: sex)
                : nil
            let tiz = samples.isEmpty ? nil : HRZones.timeInZone(samples, zoneSet: zoneSet)
            return (live, tiz)
        }.value
        let effort = StrainScorer.effectiveEffort(live: live, stored: row?.strain)
        let zoneSeconds = tiz.flatMap { $0.seconds.contains(where: { $0 > 0 }) ? $0.seconds : nil }

        // Target Recovery: the day's own score, else (today only) the same carried score Today shows.
        let calNights = isToday
            ? RecoveryScorer.calibrationNights(nightlyHrv: repo.chargeBaselines?.hrvHistory.values ?? [],
                                               dayKeys: repo.chargeBaselines?.hrvHistory.dayKeys ?? [],
                                               hasRecovery: row?.recovery != nil)
            : nil
        let prior = TodayView.lastScoredRecoveryDay(days: repo.days, selectedDayKey: day.key, isToday: isToday,
                                                    todayScored: row?.recovery != nil,
                                                    isCalibrating: calNights != nil)
        let recovery = LiquidTodayView.ChargeDisplay.resolve(todayRecovery: row?.recovery, priorScored: prior,
                                                             calibrationNights: calNights, todayKey: day.key).pct

        // Provenance: a live value that beats the stored row was computed here; otherwise the stored winner.
        var provenance: ScoreProvenance?
        if let effort {
            if let live, effort == live, live != row?.strain {
                provenance = .computed
            } else {
                let resolution = await repo.resolvedSeries(key: "strain", source: Repository.whoopSource,
                                                           from: day.key, to: day.key)
                provenance = resolution.points.last(where: { $0.day == day.key })
                    .map { ScoreProvenance.classify(rawSource: $0.source, deviceId: repo.deviceId) }
            }
        }

        let workouts = await repo.workoutRows()
            .filter { $0.startTs >= window.from && $0.startTs < window.to }
            .sorted { $0.startTs < $1.startTs }

        let keys = day.last30Keys
        var byDay: [String: Double] = [:]
        for d in repo.days { if let s = d.strain { byDay[d.day] = s } }
        var bars = keys.map { byDay[$0] }
        if !bars.isEmpty { bars[bars.count - 1] = effort }
        return StrainDetailModel(day: day, effort: effort, recoveryForTarget: recovery, provenance: provenance,
                                 workouts: workouts, zoneSeconds: zoneSeconds, bars: bars, barKeys: keys)
    }
}

// MARK: - Formatting

enum ScoreDetailFormat {
    private static let keyParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(fromKey key: String) -> Date? { keyParser.date(from: key) }

    /// "29 Oct" in the app language.
    static func shortDate(_ key: String) -> String {
        guard let date = date(fromKey: key) else { return key }
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f.string(from: date)
    }

    /// "Wed, 29 Oct" in the app language.
    static func dayTitle(_ key: String) -> String {
        guard let date = date(fromKey: key) else { return key }
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: date)
    }

    /// Hero-number formatting identical to Liquid Today's `HeroScoreCell`.
    static func score(_ value: Double, decimals: Int) -> String {
        decimals > 0
            ? String(format: "%.\(decimals)f", locale: AppLanguage.activeLocale, value)
            : String(Int(value.rounded()))
    }

    /// "2h 22m" / "38m" in the app language.
    static func duration(seconds: Double) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        var cal = Calendar.current
        cal.locale = AppLanguage.activeLocale
        f.calendar = cal
        return f.string(from: max(0, seconds.rounded())) ?? ""
    }

    /// "6:40 PM" in the app language.
    static func time(_ ts: Int) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// First, middle and last captions for a 30-day bar chart; the last reads "Today" for today.
    static func barCaptions(keys: [String], isToday: Bool) -> [String] {
        guard let first = keys.first, let last = keys.last else { return [] }
        let middle = keys[keys.count / 2]
        return [shortDate(first), shortDate(middle), isToday ? String(localized: "Today") : shortDate(last)]
    }
}
