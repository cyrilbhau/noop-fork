import Combine
import Foundation
import StrandAnalytics

// "Recovery context" (stage 6 specification §7.2, §8.2, §10.7): the one caller of
// `CutStressTrend.weekly`, over the nights `Repository.days` already holds. Nothing here is read by
// Recovery, Strain, the scorecard verdict, illness detection, the Coach, the coach packet or a widget,
// and nothing is written. The screen opens from the scorecard only, so the model is idle while either
// `noop.cutStressEnabled` or the scorecard's own flag is off.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

@MainActor
final class CutStressModel: ObservableObject {
    static let enabledKey = "noop.cutStressEnabled"

    /// The one observable copy of the flag (§9.4). The Settings switch and the scorecard link observe it.
    @MainActor static let flag = ObservableDefaultsFlag(key: enabledKey)

    enum State: Equatable {
        case idle, loading
        case loaded(CutStressPresentation)
    }

    @Published private(set) var state: State = .idle
    /// The pure input and result of the latest load; nil while idle.
    private(set) var input: CutStressInput?
    private(set) var result: CutStressResult?

    private let repository: Repository
    private let scorecardSettings: CutScorecardSettings
    private let defaults: UserDefaults
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let locale: () -> Locale

    init(repository: Repository, scorecardSettings: CutScorecardSettings = CutScorecardSettings(),
         defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .current },
         locale: @escaping () -> Locale = { AppLanguage.activeLocale }) {
        self.repository = repository
        self.scorecardSettings = scorecardSettings
        self.defaults = defaults
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
    }

    /// Whether the screen may be shown: both its own flag and the scorecard's.
    var isReachable: Bool { defaults.bool(forKey: Self.enabledKey) && scorecardSettings.isEnabled }

    func load() async {
        guard isReachable else {
            input = nil
            result = nil
            if state != .idle { state = .idle }
            return
        }
        let today = LocalDayWindows(timeZone: timeZone()).dayKey(for: now())
        let nights = repository.days.map {
            CutStressNight(day: $0.day, restingHr: $0.restingHr.map(Double.init), hrv: $0.avgHrv)
        }
        // A cut phase that has started fixes the first week; otherwise the latest twelve weeks.
        let phase = scorecardSettings.activePhase(on: today)
        let firstWeek = phase?.kind == .cut ? phase.flatMap { CanonicalDay.weekStart(containing: $0.startDay) } : nil
        let built = CutStressInput(
            nights: nights, firstWeekStart: firstWeek, today: today,
            minNightsPerWeek: CutStressPresenter.minNightsPerWeek,
            maxWeeks: firstWeek == nil ? CutStressPresenter.weeksWithoutPhase : CutStressPresenter.maxWeeksWithPhase)
        let weekly = CutStressTrend.weekly(built)
        input = built
        result = weekly
        let baselines = repository.chargeBaselines
        let presentation = CutStressPresenter.present(weekly, restingHrBaseline: baselines?.restingHR,
                                                      hrvBaseline: baselines?.hrv, firstWeekStart: firstWeek,
                                                      locale: locale())
        if state != .loaded(presentation) { state = .loaded(presentation) }
    }
}
