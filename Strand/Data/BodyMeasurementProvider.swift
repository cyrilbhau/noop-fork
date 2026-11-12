import Foundation
import Combine
import WhoopStore

/// The weight points a Today view draws and resolves its tile from, fetched in one read.
///
/// `policy` is fixed when the read starts, so a flag flipped while the read is suspended cannot make
/// the tile and its sparkline answer under two different rules. It stays with the value, so a view
/// that holds or caches a series can tell that the flag has changed since: the series' policy is
/// then no longer `BodyMeasurementProvider.displayPolicy` (ruling R38).
struct BodyWeightSeries: Sendable {
    let policy: BodyMeasurementPolicy
    /// Ascending by day. Flag off: the Apple Health `weight` series inside the view's own window.
    /// Flag on: the unified series inside the same window.
    let points: [(day: String, value: Double)]
}

/// What a Today weight tile shows: the value and the sparkline behind it, as one reading (ruling
/// R40). Both parts were resolved under `policy`, so a view cannot refresh one without the other.
struct BodyWeightDisplay {
    let policy: BodyMeasurementPolicy
    /// The dated reading, or the profile value when there is none.
    let value: ResolvedBodyMeasurement
    /// False when `value` is the profile fallback.
    let isDated: Bool
    let sparkline: [(day: String, value: Double)]
}

/// The day a Today view resolves its weight tile for.
enum BodyWeightAsOf {
    /// Liquid and the redesign: the day the wearer is looking at, and whether it is the current
    /// day. Those views select the logical day (04:00 rollover), so under the unified policy the
    /// current day resolves as of the later of it and the calendar day (ruling R33).
    case day(String, isCurrent: Bool)
    /// Classic Today: the latest reading, whichever day is selected.
    case latest
}

/// The repository-backed half of the body-measurement funnel (specification §8.4, §8.5).
///
/// It fetches the candidates, holds them as a snapshot, answers every reader through
/// `BodyMeasurementResolver`, and is the ONE writer of the profile mirror. No reader of a body weight
/// or a waist resolves it any other way; `Tools/test_body_measurement_single_resolver.py` enforces it.
///
/// With `noop.cutScorecardEnabled` off (the default) it reproduces what each reader did before it
/// existed: an estimate gets the profile value, read at the moment of the call, and a Today view gets
/// the Apple Health value under that view's own window and as-of rule, else the profile value. In the
/// app it then runs no store read of its own beyond the one Apple Health series read each Today view
/// already made, and it never writes the profile.
@MainActor
final class BodyMeasurementProvider: ObservableObject {
    private static let weightDefaultsKey = "profile.weightKg"
    private static let waistDefaultsKey = "profile.waistCm"
    /// Greater than every day key, for "the latest reading whatever its day".
    private static let latestDay = "\u{10FFFF}"

    /// What the last `refresh()` read. Lab Book rows are already de-duplicated across strap ids.
    private struct Snapshot {
        var weightRows: [LabMarkerRow] = []
        var waistRows: [LabMarkerRow] = []
        var appleWeight: [(day: String, value: Double)] = []

        func isSame(as other: Snapshot) -> Bool {
            weightRows == other.weightRows && waistRows == other.waistRows
                && appleWeight.elementsEqual(other.appleWeight) { $0.day == $1.day && $0.value == $1.value }
        }
    }

    /// Bumped when a refresh read something other than the snapshot already held, so an observing
    /// view re-resolves. A refresh that changed nothing leaves it alone, and so does every refresh
    /// with the flag off, when no reader uses the snapshot (ruling R32).
    @Published private(set) var revision = 0

    private let repository: Repository
    private let defaults: UserDefaults
    private let today: () -> String
    /// The app's live profile (ruling R28). Nil in tests, where the injected defaults stand in for it.
    private let profile: ProfileStore?
    private var snapshot = Snapshot()
    private var refreshTail: Task<Void, Never>?
    private var repositoryObserver: AnyCancellable?

    init(repository: Repository, defaults: UserDefaults = .standard,
         today: @escaping () -> String = { Repository.localDayKey(Date()) }) {
        self.repository = repository
        self.defaults = defaults
        self.today = today
        self.profile = nil
        followRepository()
    }

    private init(repository: Repository, profile: ProfileStore) {
        self.repository = repository
        self.defaults = .standard
        self.today = { Repository.localDayKey(Date()) }
        self.profile = profile
        followRepository()
        if flagEnabled {
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    /// §8.4, ruling R32: refresh after every completed `Repository.refresh()`, including one that
    /// found its caches unchanged, which is all a Lab Book write produces. Only while the flag is
    /// on: with it off no reader uses the snapshot, so the signal costs one flag read and nothing
    /// else.
    private func followRepository() {
        repositoryObserver = repository.refreshCompleted.sink { [weak self] in
            guard let self, self.flagEnabled else { return }
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    // MARK: - The app's shared instance

    private final class WeakProvider {
        weak var value: BodyMeasurementProvider?
        init(_ value: BodyMeasurementProvider) { self.value = value }
    }

    private static var liveProviders: [WeakProvider] = []

    /// The provider every reader of this `repository` and `profile` shares.
    ///
    /// Held weakly here and strongly by its users (the intelligence engine, for the app's lifetime),
    /// so the app has one and a test's repository is not kept alive after the test. Keyed on the
    /// profile as well, so a reader always gets the profile it was handed.
    static func live(repository: Repository, profile: ProfileStore) -> BodyMeasurementProvider {
        liveProviders.removeAll { $0.value == nil }
        if let held = liveProviders.lazy.compactMap(\.value)
            .first(where: { $0.repository === repository && $0.profile === profile }) {
            return held
        }
        let provider = BodyMeasurementProvider(repository: repository, profile: profile)
        liveProviders.append(WeakProvider(provider))
        return provider
    }

    // MARK: - Flag and profile

    /// The feature flag, read at each use.
    private var flagEnabled: Bool { defaults.bool(forKey: CutScorecardSettings.enabledKey) }

    /// The profile value as the readers saw it before this type existed: the live `ProfileStore`
    /// value in the app, the stored default in tests. Read at the moment of the call, never cached.
    private func profileValue(_ kind: BodyMeasurementKind) -> (value: Double, isSet: Bool) {
        switch kind {
        case .weight:
            let stored = defaults.object(forKey: Self.weightDefaultsKey) as? Double
            return (profile?.weightKg ?? stored ?? 75, stored != nil)
        case .waist:
            let stored = defaults.object(forKey: Self.waistDefaultsKey) as? Double
            return (profile?.waistCm ?? stored ?? 0, stored != nil)
        }
    }

    /// The mirror's single write. Through the live `ProfileStore` in the app, so its published value
    /// and the stored default cannot disagree (ruling R28).
    private func writeProfile(_ kind: BodyMeasurementKind, _ value: Double) {
        switch kind {
        case .weight:
            if let profile { profile.weightKg = value } else { defaults.set(value, forKey: Self.weightDefaultsKey) }
        case .waist:
            if let profile { profile.waistCm = value } else { defaults.set(value, forKey: Self.waistDefaultsKey) }
        }
    }

    // MARK: - Refresh

    /// Re-read the candidates and mirror today's resolved values into the profile.
    ///
    /// Refreshes run one after another in the order they were requested, so a read that started
    /// earlier can never publish over a later one.
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
        // Captured before the first suspension: the ids this read unions belong to one moment.
        let activeDeviceId = repository.deviceId
        guard let store = await repository.storeHandle() else { return }
        let weightRows = await Self.labBookRows(.weight, store: store, activeDeviceId: activeDeviceId)
        let waistRows = await Self.labBookRows(.waist, store: store, activeDeviceId: activeDeviceId)
        // One source, two stores (§8.2): merged per day, the daily column winning.
        let appleSeries = await repository.series(key: "weight", source: "apple-health")
        let appleDaily = await repository.appleDailyRows()
        var appleByDay: [String: Double] = [:]
        for point in appleSeries { appleByDay[point.day] = point.value }
        for row in appleDaily {
            if let kg = row.weightKg { appleByDay[row.day] = kg }
        }
        let read = Snapshot(weightRows: weightRows, waistRows: waistRows,
                            appleWeight: appleByDay.keys.sorted().map { (day: $0, value: appleByDay[$0] ?? 0) })
        let changed = !read.isSame(as: snapshot)
        snapshot = read
        if changed, flagEnabled { revision += 1 }
        mirrorIntoProfile()
    }

    /// §8.5: with the flag on, a dated reading that resolves for today is written to the profile when
    /// the profile holds something else. Never with the flag off, never the undated profile value
    /// itself, and never unwound (ruling R27).
    private func mirrorIntoProfile() {
        guard flagEnabled else { return }
        let day = today()
        for kind in [BodyMeasurementKind.weight, .waist] {
            guard let resolved = BodyMeasurementResolver.resolve(kind, asOf: day, candidates: candidates(kind),
                                                                 policy: .unified),
                  resolved.day != nil else { continue }
            let stored = profileValue(kind)
            if stored.isSet, stored.value == resolved.value { continue }
            writeProfile(kind, resolved.value)
        }
    }

    /// Every Lab Book row of `kind` under every device id present in the table, registered or not
    /// (ruling R42, which widens rulings R25 and R29): one call to the app's single Lab Book read
    /// path. Rows equal in content under two ids are listed once, the active id's copy standing for
    /// them; rows at one instant that differ are different readings and are both listed, and the
    /// resolver's same-day rule picks between them. Oldest first. Reads only.
    ///
    /// There is deliberately no device-id list here any more: a list built from the registry hid
    /// the readings entered under a strap that was later forgotten.
    static func labBookRows(_ kind: BodyMeasurementKind, store: WhoopStore,
                            activeDeviceId: String) async -> [LabMarkerRow] {
        await LabBookRows.marker(kind.markerKey, store: store, activeDeviceId: activeDeviceId)
    }

    // MARK: - Reads of the snapshot

    /// What the resolver chooses from for `kind`: the last refresh's rows and the profile value now.
    func candidates(_ kind: BodyMeasurementKind) -> BodyMeasurementCandidates {
        let stored = profileValue(kind)
        switch kind {
        case .weight:
            return BodyMeasurementCandidates(labBook: snapshot.weightRows, appleHealth: snapshot.appleWeight,
                                             profileValue: stored.value, profileIsSet: stored.isSet)
        case .waist:
            return BodyMeasurementCandidates(labBook: snapshot.waistRows, appleHealth: [],
                                             profileValue: stored.value, profileIsSet: stored.isSet)
        }
    }

    /// The policy a Today view's weight resolves under now: one read of the flag, no store read
    /// and no write. A view compares it with the `policy` of the series it holds, and a reading
    /// resolved under another policy is not shown or restored (ruling R38).
    var displayPolicy: BodyMeasurementPolicy { policy(.display) }

    private func policy(_ consumer: BodyMeasurementConsumer) -> BodyMeasurementPolicy {
        BodyMeasurementResolver.policy(flagEnabled: flagEnabled, consumer: consumer)
    }

    /// Every dated reading the consumer's policy admits, ascending, one per day.
    /// `asOf` is forwarded to the resolver unchanged (stage 1 work package 1-11).
    func series(_ kind: BodyMeasurementKind, consumer: BodyMeasurementConsumer,
                asOf: String? = nil) -> [DatedBodyMeasurement] {
        BodyMeasurementResolver.series(kind, candidates: candidates(kind), policy: policy(consumer), asOf: asOf)
    }

    /// The value in force today.
    func current(_ kind: BodyMeasurementKind, consumer: BodyMeasurementConsumer) -> ResolvedBodyMeasurement? {
        resolve(kind, asOf: today(), consumer: consumer)
    }

    /// The value in force as of `day`.
    func resolve(_ kind: BodyMeasurementKind, asOf day: String,
                 consumer: BodyMeasurementConsumer) -> ResolvedBodyMeasurement? {
        BodyMeasurementResolver.resolve(kind, asOf: day, candidates: candidates(kind), policy: policy(consumer))
    }

    // MARK: - Estimates

    /// The weight the calorie and readiness estimates use, in kilograms.
    func estimateWeightKg() -> Double {
        current(.weight, consumer: .estimate)?.value ?? profileValue(.weight).value
    }

    /// The waist the VO₂max estimate uses, in centimetres. With no waist anywhere this is the
    /// profile's own "not set" value (0 unless something else was stored), so a caller's existing
    /// `> 0` test reads exactly as it did against the profile.
    func estimateWaistCm() -> Double {
        current(.waist, consumer: .estimate)?.value ?? profileValue(.waist).value
    }

    // MARK: - Today

    /// The weight points for a Today view, read with the view's own window (ruling R26).
    ///
    /// `days` bounds the read as `Repository.series(days:)` does. `trailingDays`, when given, then
    /// keeps the trailing calendar days ending today, the window classic Today's sparkline draws.
    func displayWeightSeries(days: Int, trailingDays: Int? = nil) async -> BodyWeightSeries {
        // The policy is captured before the read suspends.
        let policy = policy(.display)
        var points: [(day: String, value: Double)]
        if policy == .unified {
            await refresh()
            let from = Repository.localDayKey(Date().addingTimeInterval(-Double(days) * 86_400))
            let upTo = today()
            points = BodyMeasurementResolver.series(.weight, candidates: candidates(.weight), policy: policy)
                .filter { $0.day >= from && $0.day <= upTo }
                .map { (day: $0.day, value: $0.value) }
        } else {
            points = await repository.series(key: "weight", source: "apple-health", days: days)
        }
        if let trailingDays, !points.isEmpty {
            let cutoff = Repository.localDayKey(
                Calendar.current.date(byAdding: .day, value: -(trailingDays - 1), to: Date()) ?? Date())
            points = points.filter { $0.day >= cutoff }
        }
        return BodyWeightSeries(policy: policy, points: points)
    }

    /// The dated reading a Today weight tile shows, nil when only the profile value exists.
    ///
    /// Flag off, this is each view's rule as it was (ruling R26), run through the resolver's
    /// `legacyDisplay` policy, and `isCurrent` changes nothing (ruling R33). `.day`: the Apple
    /// Health daily value of that day, else the newest
    /// series point on or before it. `.latest`: the newest daily row's weight when that row carries
    /// one, else the newest series point. `appleRows` are the Apple Health daily rows the view
    /// already holds for its steps and calories; they are consulted only with the flag off.
    func displayWeight(from series: BodyWeightSeries, asOf: BodyWeightAsOf,
                       appleRows: [AppleDaily]) -> ResolvedBodyMeasurement? {
        let resolved: ResolvedBodyMeasurement?
        switch series.policy {
        case .unified:
            let day: String
            switch asOf {
            case .day(let selected, let isCurrent): day = isCurrent ? max(selected, today()) : selected
            case .latest: day = today()
            }
            resolved = BodyMeasurementResolver.resolve(.weight, asOf: day, candidates: candidates(.weight),
                                                       policy: .unified)
        case .legacyDisplay, .legacyEstimate:
            var apple = series.points
            let day: String
            switch asOf {
            case .day(let selected, _):
                if let daily = appleRows.filter({ $0.day == selected }).compactMap({ $0.weightKg }).max() {
                    apple.append((day: selected, value: daily))
                }
                day = selected
            case .latest:
                if let newest = appleRows.last, let daily = newest.weightKg {
                    apple = [(day: newest.day, value: daily)]
                }
                day = Self.latestDay
            }
            let stored = profileValue(.weight)
            resolved = BodyMeasurementResolver.resolve(
                .weight, asOf: day,
                candidates: BodyMeasurementCandidates(labBook: [], appleHealth: apple,
                                                      profileValue: stored.value, profileIsSet: stored.isSet),
                policy: .legacyDisplay)
        }
        return resolved?.day == nil ? nil : resolved
    }

    /// The weight series, the dated reading and the printed value in one step, on one read of the
    /// flag (ruling R40): the series fixes the policy, and the value is resolved from that series.
    func displayWeight(days: Int, trailingDays: Int? = nil, asOf: BodyWeightAsOf,
                       appleRows: [AppleDaily]) async -> BodyWeightDisplay {
        let series = await displayWeightSeries(days: days, trailingDays: trailingDays)
        let dated = displayWeight(from: series, asOf: asOf, appleRows: appleRows)
        return BodyWeightDisplay(policy: series.policy, value: displayWeightValue(dated),
                                 isDated: dated != nil, sparkline: series.points)
    }

    /// What a weight tile prints: the dated reading it resolved, else the profile value as it is now.
    func displayWeightValue(_ dated: ResolvedBodyMeasurement?) -> ResolvedBodyMeasurement {
        if let dated { return dated }
        let stored = profileValue(.weight)
        let undated = BodyMeasurementCandidates(labBook: [], appleHealth: [],
                                                profileValue: stored.value, profileIsSet: stored.isSet)
        // A weight always resolves: with no dated candidate the resolver returns the profile value.
        return BodyMeasurementResolver.resolve(.weight, asOf: today(), candidates: undated, policy: .legacyEstimate)
            ?? ResolvedBodyMeasurement(kind: .weight, value: stored.value,
                                       source: stored.isSet ? .profile : .profileDefault, day: nil)
    }
}
