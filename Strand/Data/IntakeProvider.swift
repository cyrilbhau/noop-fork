import Foundation
import Combine
import StrandAnalytics
import WhoopStore

/// The repository-backed half of the intake funnel (stage 3 specification §9.4).
///
/// It fetches the candidates of the three source ids, holds them as a snapshot and answers every
/// reader through `IntakeResolver`: the Today card, the intake screen, the widget reading and the
/// scorecard's protein signal are four reads of one list (stage 1 ruling R41). No other code reads
/// an intake series key; `Tools/test_intake_single_resolver.py` enforces it.
///
/// With `noop.intakeEnabled` off the policy is `legacy` and the list is the `nutrition-csv` series,
/// value for value what the scorecard read before this stage. It then refreshes only when asked.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
@MainActor
final class IntakeProvider: ObservableObject {
    /// Totals read from Apple Health (Path A). Never `apple-health`: that source's delete must not
    /// reach intake history (§9.1).
    static let healthSourceId = "noop-intake-health"
    /// Totals of the entries made in the app (Path B).
    static let quickAddSourceId = "noop-intake"
    /// The existing nutrition CSV import.
    static let csvSourceId = "nutrition-csv"

    private static let proteinKey = IntakeAggregation.proteinKey
    private static let energyKey = IntakeAggregation.energyKey
    private static let readAtKey = IntakeAggregation.readAtKey

    /// Bumped when a refresh read something other than the snapshot already held, while the flag is
    /// on, so an observing view resolves again (stage 1 ruling R32).
    @Published private(set) var revision = 0
    /// The last Health read's outcome and when it ran, for the interface (§8.2). Nil: none this run.
    @Published private(set) var lastHealthOutcome: IntakeHealthSync.Outcome?
    @Published private(set) var lastHealthAttemptAt: Date?

    let repository: Repository
    let settings: IntakeSettings
    private var candidates = IntakeCandidates(appleHealth: [], quickAdd: [], nutritionCsv: [])
    private var refreshTail: Task<Void, Never>?
    private var repositoryObserver: AnyCancellable?

    init(repository: Repository, settings: IntakeSettings) {
        self.repository = repository
        self.settings = settings
        Self.register(self)
        // R32: after every completed repository refresh, but only while the flag is on. With it off
        // the signal costs one flag read and nothing else.
        repositoryObserver = repository.refreshCompleted.sink { [weak self] in
            guard let self, self.settings.isEnabled else { return }
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    // MARK: - The app's shared instance

    private final class WeakProvider {
        weak var value: IntakeProvider?
        init(_ value: IntakeProvider) { self.value = value }
    }

    private static var providers: [WeakProvider] = []
    private static var liveProviders: [WeakProvider] = []

    private static func register(_ provider: IntakeProvider) {
        providers.removeAll { $0.value == nil }
        providers.append(WeakProvider(provider))
    }

    /// The app's one instance for a repository, over the standard defaults. Held weakly here and
    /// strongly by its users, so a test's repository is not kept alive after the test.
    static func live(repository: Repository) -> IntakeProvider {
        liveProviders.removeAll { $0.value == nil }
        if let held = liveProviders.lazy.compactMap(\.value).first(where: { $0.repository === repository }) {
            return held
        }
        let provider = IntakeProvider(repository: repository, settings: IntakeSettings())
        liveProviders.append(WeakProvider(provider))
        if provider.settings.isEnabled {
            Task { @MainActor [weak provider] in await provider?.refresh() }
        }
        return provider
    }

    /// A funnel wrote under an intake id of `repository`: every provider over it reads again (R32).
    static func funnelDidWrite(_ repository: Repository) {
        providers.removeAll { $0.value == nil }
        for provider in providers.compactMap(\.value) where provider.repository === repository {
            Task { @MainActor [weak provider] in await provider?.refresh() }
        }
    }

    /// A Health read finished: its outcome and time are kept for the interface (§8.2).
    static func recordHealthAttempt(_ outcome: IntakeHealthSync.Outcome, at instant: Date, repository: Repository) {
        providers.removeAll { $0.value == nil }
        for provider in providers.compactMap(\.value) where provider.repository === repository {
            provider.lastHealthOutcome = outcome
            provider.lastHealthAttemptAt = instant
        }
    }

    // MARK: - Refresh

    /// Re-read the candidates. Refreshes run one after another in the order they were requested,
    /// so a read that started earlier can never publish over a later one.
    func refresh() async {
        let previous = refreshTail
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.readAndPublish()
        }
        refreshTail = task
        await task.value
    }

    private func readAndPublish() async {
        let read = IntakeCandidates(appleHealth: await storedDays(Self.healthSourceId, readAt: true),
                                    quickAdd: await storedDays(Self.quickAddSourceId, readAt: true),
                                    nutritionCsv: await storedDays(Self.csvSourceId, readAt: false))
        let changed = !(read.appleHealth == candidates.appleHealth && read.quickAdd == candidates.quickAdd
                        && read.nutritionCsv == candidates.nutritionCsv)
        candidates = read
        if changed, settings.isEnabled { revision += 1 }
    }

    /// One source's stored days, through the repository's generic series read.
    private func storedDays(_ source: String, readAt: Bool) async -> [IntakeStoredDay] {
        let protein = await repository.series(key: Self.proteinKey, source: source)
        let energy = await repository.series(key: Self.energyKey, source: source)
        let times = readAt ? await repository.series(key: Self.readAtKey, source: source) : []
        var proteinByDay: [String: Double] = [:]
        var energyByDay: [String: Double] = [:]
        var timeByDay: [String: Int] = [:]
        for point in protein { proteinByDay[point.day] = point.value }
        for point in energy { energyByDay[point.day] = point.value }
        for point in times where point.value.isFinite && abs(point.value) < 1e15 {
            timeByDay[point.day] = Int(point.value)
        }
        let days = Set(proteinByDay.keys).union(energyByDay.keys).sorted()
        return days.map {
            IntakeStoredDay(day: $0, proteinGrams: proteinByDay[$0], energyKcal: energyByDay[$0],
                            readAtEpochSeconds: timeByDay[$0])
        }
    }

    // MARK: - Reads of the snapshot

    /// The policy in force now: the flag and the source setting, read at each call.
    var policy: IntakePolicy {
        IntakeResolver.policy(flagEnabled: settings.isEnabled, sourceSetting: settings.source)
    }

    /// The resolved day, or nil when no source holds a usable value for it ("not measured").
    func day(_ day: String) -> ResolvedIntakeDay? {
        IntakeResolver.resolve(day: day, candidates: candidates, policy: policy)
    }

    /// Every day with a resolved value, ascending.
    func series() -> [ResolvedIntakeDay] {
        IntakeResolver.series(candidates: candidates, policy: policy)
    }

    /// What the scorecard reads. One entry per day with a protein value.
    func proteinDays() -> [CutScorecardProteinDay] {
        series().compactMap { day in day.protein.map { CutScorecardProteinDay(day: day.day, grams: $0.value) } }
    }

    /// The quick-add store's own total for `day`, as last read. For the "Restored total" row.
    func quickAddStoredDay(_ day: String) -> IntakeStoredDay? {
        candidates.quickAdd.first { $0.day == day }
    }
}
