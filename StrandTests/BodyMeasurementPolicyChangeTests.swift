import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard), ruling R38 of specification §18 (second review). Written from
// the ruling, without reading the provider's implementation.
//
// The finding: a Today view caches the reading it resolved. Switching the scorecard flag off does
// not move the repository's `refreshSeq` or (with the flag off) the provider's `revision`, so a view
// that restores its cached reading keeps showing the unified value, a Lab Book weigh-in, until an
// unrelated refresh. The ruling: a cached reading records the policy it was resolved under, and one
// resolved under another policy than the current one is not restored.
//
// What is pinned here is the half below the view layer: that the provider can say which policy the
// display currently resolves under, that a fetched series says which policy it was fetched under,
// and that a series fetched after the flag went off resolves to the legacy value at once. That the
// three Today views compare the two and resolve again is view state and is left to review, as is
// ruling R37 (the classic tile resolving from the view's live state).
//
// API ASSUMED BY THESE TESTS
//
//  1. `BodyMeasurementProvider` gains
//         var displayPolicy: BodyMeasurementPolicy { get }
//     the policy the display consumer currently resolves under:
//     `BodyMeasurementResolver.policy(flagEnabled:consumer: .display)` on ONE read of
//     `noop.cutScorecardEnabled` from the injected defaults, made at the time of the call. It needs
//     no `refresh()` and writes nothing.
//  2. `BodyWeightSeries` carries
//         let policy: BodyMeasurementPolicy
//     the policy `displayWeightSeries(days:trailingDays:)` fetched it under. It is a stored value: a
//     series fetched with the flag on still says `.unified` after the flag goes off, which is what
//     lets a view see that its cached reading is stale (`series.policy != provider.displayPolicy`).
//  3. The display surface as assumed at the top of `BodyMeasurementDisplayTests.swift`. With the
//     flag off, `displayWeightSeries`, `displayWeight` and `displayWeightValue` follow the base
//     commit's rule and need no `provider.refresh()` or `repository.refresh()` after the switch.
//
// Dates are relative to the real clock (ruling R31): the repository's Apple Health reads are windowed
// on it. Synthetic values only.
@MainActor
final class BodyMeasurementPolicyChangeTests: XCTestCase {

    // MARK: - Harness

    /// Records which keys were written, so "never written" can be told from "written with the same value".
    private final class RecordingDefaults: UserDefaults {
        var written: [String] = []
        override func set(_ value: Any?, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func set(_ value: Double, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func set(_ value: Bool, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func removeObject(forKey defaultName: String) {
            written.append(defaultName)
            super.removeObject(forKey: defaultName)
        }
        func wroteProfile() -> Bool { written.contains { $0 == "profile.weightKg" || $0 == "profile.waistCm" } }
    }

    private struct Harness {
        let store: WhoopStore
        let repo: Repository
        let defaults: RecordingDefaults
        let provider: BodyMeasurementProvider
    }

    private let flagKey = "noop.cutScorecardEnabled"
    private let weightKey = "profile.weightKg"
    private let started = Date()
    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    /// The local day `offset` days from the real today, as the repository keys days.
    private func dayKey(_ offset: Int) -> String {
        Repository.localDayKey(Calendar.current.date(byAdding: .day, value: offset, to: started) ?? started)
    }

    /// Local noon on `dayKey(offset)`, epoch seconds.
    private func noon(_ offset: Int) -> Int {
        let day = Calendar.current.date(byAdding: .day, value: offset, to: started) ?? started
        return Int(Calendar.current.startOfDay(for: day).timeIntervalSince1970) + 12 * 3_600
    }

    /// `flag` nil: the key was never written.
    private func makeHarness(flag: Bool?, profileKg: Double? = 80.0) async throws -> Harness {
        let name = "BodyMeasurementPolicyChangeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: name))
        suites.append(name)
        if let flag { defaults.set(flag, forKey: flagKey) }
        if let profileKg { defaults.set(profileKg, forKey: weightKey) }
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let today = dayKey(0)
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        defaults.written = []
        return Harness(store: store, repo: repo, defaults: defaults, provider: provider)
    }

    private func labWeight(_ offset: Int, _ kg: Double) -> LabMarkerRow {
        let takenAt = noon(offset)
        return LabMarkerRow(id: "weight-\(takenAt)-0A1B2C3D", deviceId: "my-whoop", markerKey: "weight",
                            category: "bodyMeasurement", day: dayKey(offset), takenAt: takenAt, value: kg,
                            valueText: nil, unit: "kg", source: "manual", note: nil, referenceText: nil)
    }

    /// A Lab Book weight of 97.0 kg yesterday, an OLDER Apple Health weight of 101.0 kg six days
    /// back, and a DIFFERENT profile value (80.0 kg, set by `makeHarness`).
    private func seedThreeSources(_ h: Harness) async throws {
        try await h.store.upsertLabMarkers([labWeight(-1, 97.0)])
        try await h.store.upsertMetricSeries([MetricPoint(day: dayKey(-6), key: "weight", value: 101.0)],
                                             deviceId: "apple-health")
        // The app has always refreshed its repository by the time a Today view loads.
        await h.repo.refresh()
        await h.provider.refresh()
    }

    private func describe(_ points: [(day: String, value: Double)]) -> [String] {
        points.map { "\($0.day)=\($0.value)" }
    }

    // MARK: - displayPolicy

    /// The flag is read at the time of the call: the same provider answers differently as the flag
    /// changes in its defaults, with no refresh in between and nothing written.
    func testDisplayPolicyFollowsTheFlagAtCallTime() async throws {
        let h = try await makeHarness(flag: nil)
        XCTAssertEqual(h.provider.displayPolicy, .legacyDisplay, "the flag was never set: off")

        h.defaults.set(true, forKey: flagKey)
        XCTAssertEqual(h.provider.displayPolicy, .unified, "switched on, same provider, no refresh")

        h.defaults.set(false, forKey: flagKey)
        XCTAssertEqual(h.provider.displayPolicy, .legacyDisplay, "switched off again")

        h.defaults.set(true, forKey: flagKey)
        XCTAssertEqual(h.provider.displayPolicy, .unified)

        h.defaults.removeObject(forKey: flagKey)
        XCTAssertEqual(h.provider.displayPolicy, .legacyDisplay, "the key removed: off")

        XCTAssertEqual(h.defaults.written.filter { $0 != flagKey }, [],
                       "reading the policy writes nothing: only this test's own flag writes are recorded")
        XCTAssertFalse(h.defaults.wroteProfile())
    }

    /// The property is the resolver's own mapping for the display consumer, never the estimate one.
    func testDisplayPolicyIsTheResolversPolicyForTheDisplayConsumer() async throws {
        for flag in [false, true] {
            let h = try await makeHarness(flag: flag)
            XCTAssertEqual(h.provider.displayPolicy,
                           BodyMeasurementResolver.policy(flagEnabled: flag, consumer: .display), "flag \(flag)")
            XCTAssertNotEqual(h.provider.displayPolicy, .legacyEstimate, "flag \(flag)")
        }
        // A provider created with the flag on does not remember it.
        let h = try await makeHarness(flag: true)
        await h.provider.refresh()
        XCTAssertEqual(h.provider.displayPolicy, .unified)
        h.defaults.set(false, forKey: flagKey)
        XCTAssertEqual(h.provider.displayPolicy, .legacyDisplay,
                       "the policy is not a snapshot taken at init or at the last refresh")
    }

    // MARK: - The series records its policy

    /// A series fetched with the flag on records `unified`; one fetched after the flag went off
    /// records `legacyDisplay`. The earlier series keeps what it recorded, so it can be told apart
    /// from the current policy.
    func testASeriesRecordsThePolicyItWasFetchedUnder() async throws {
        let h = try await makeHarness(flag: true)
        try await seedThreeSources(h)

        let fetchedOn = await h.provider.displayWeightSeries(days: 91)
        let fetchedOnClassic = await h.provider.displayWeightSeries(days: 91, trailingDays: 90)
        XCTAssertEqual(fetchedOn.policy, .unified)
        XCTAssertEqual(fetchedOnClassic.policy, .unified)
        XCTAssertEqual(fetchedOn.policy, h.provider.displayPolicy, "fresh: the cached reading may be restored")

        h.defaults.set(false, forKey: flagKey)
        // No refresh of the provider or of the repository: the switch alone.
        let fetchedOff = await h.provider.displayWeightSeries(days: 91)
        let fetchedOffClassic = await h.provider.displayWeightSeries(days: 91, trailingDays: 90)
        XCTAssertEqual(fetchedOff.policy, .legacyDisplay)
        XCTAssertEqual(fetchedOffClassic.policy, .legacyDisplay)
        XCTAssertEqual(fetchedOff.policy, h.provider.displayPolicy)

        XCTAssertEqual(fetchedOn.policy, .unified, "a series is a value: it keeps the policy it was fetched under")
        XCTAssertNotEqual(fetchedOn.policy, h.provider.displayPolicy,
                          "stale: a reading resolved from this series must not be restored (ruling R38)")

        h.defaults.set(true, forKey: flagKey)
        let fetchedOnAgain = await h.provider.displayWeightSeries(days: 91)
        XCTAssertEqual(fetchedOnAgain.policy, .unified)
        XCTAssertNotEqual(fetchedOff.policy, h.provider.displayPolicy, "and the other way round")
    }

    /// With the flag off from the start, and with an empty store, the series still records its policy.
    func testASeriesFetchedWithTheFlagOffRecordsLegacyDisplayEvenWhenEmpty() async throws {
        let h = try await makeHarness(flag: false)
        let empty = await h.provider.displayWeightSeries(days: 91)
        XCTAssertEqual(empty.policy, .legacyDisplay)
        XCTAssertTrue(empty.points.isEmpty)

        h.defaults.set(true, forKey: flagKey)
        let emptyOn = await h.provider.displayWeightSeries(days: 91, trailingDays: 90)
        XCTAssertEqual(emptyOn.policy, .unified)
    }

    // MARK: - After the flag went off

    /// A store that holds a Lab Book weight, an older Apple Health weight and a different profile
    /// value. With the flag on the tile shows the Lab Book weigh-in. The flag goes off, and the
    /// series fetched next resolves to the Apple Health weight, or to the profile value where the
    /// base rule finds no Apple Health weight, and never to the Lab Book reading: at once, with no
    /// refresh of the provider or of the repository in between.
    func testResolvingTheLegacySeriesAfterTheFlagWentOffNeverReturnsALabBookReading() async throws {
        let h = try await makeHarness(flag: true)
        try await seedThreeSources(h)
        let today = dayKey(0)
        let appleRows = await h.repo.appleDailyRows()

        // Flag on, for reference: the Lab Book weigh-in is what the tile shows.
        let unifiedSeries = await h.provider.displayWeightSeries(days: 91)
        let unified = h.provider.displayWeight(from: unifiedSeries, asOf: .day(today, isCurrent: true),
                                               appleRows: appleRows)
        XCTAssertEqual(unified?.value, 97.0, "the unified display, for reference")
        XCTAssertEqual(unified?.source, .labBook)

        h.defaults.set(false, forKey: flagKey)
        h.defaults.written = []

        let legacySeries = await h.provider.displayWeightSeries(days: 91)
        XCTAssertEqual(legacySeries.policy, .legacyDisplay)
        XCTAssertEqual(describe(legacySeries.points), ["\(dayKey(-6))=101.0"],
                       "the legacy series is the Apple Health series; the Lab Book weight is not a point of it")

        // Liquid and the redesign: today, the Lab Book reading's own day, and the Apple Health day.
        for (offset, isCurrent) in [(0, true), (0, false), (-1, false), (-1, true), (-6, false)] {
            let what = "selected day \(offset), isCurrent \(isCurrent)"
            let dated = h.provider.displayWeight(from: legacySeries, asOf: .day(dayKey(offset), isCurrent: isCurrent),
                                                 appleRows: appleRows)
            XCTAssertEqual(dated?.value, 101.0, "\(what): the Apple Health weight")
            XCTAssertEqual(dated?.source, .appleHealth, what)
            XCTAssertNotEqual(dated?.source, .labBook, what)
            let shown = h.provider.displayWeightValue(dated)
            XCTAssertEqual(shown.value, 101.0, what)
            XCTAssertNotEqual(shown.source, .labBook, what)
            XCTAssertNotEqual(shown.value, 97.0, "\(what): the Lab Book weigh-in is still shown")
        }

        // A day before the Apple Health weight: the base rule finds nothing dated, so the caption is
        // "from profile" and the value is the stored profile weight as it stands at the call. (While
        // the flag was on the mirror of §8.5 may have set that to the last weigh-in; it is the
        // profile value all the same, and is not offered as a dated Lab Book reading.)
        let before = h.provider.displayWeight(from: legacySeries, asOf: .day(dayKey(-8), isCurrent: false),
                                              appleRows: appleRows)
        XCTAssertNil(before, "nothing dated on or before that day under the legacy rule")
        let profileKg = try XCTUnwrap(h.defaults.object(forKey: weightKey) as? Double)
        XCTAssertEqual(h.provider.displayWeightValue(before),
                       ResolvedBodyMeasurement(kind: .weight, value: profileKg, source: .profile, day: nil),
                       "the profile fallback")

        // Classic: the latest reading of the trailing window.
        let classicSeries = await h.provider.displayWeightSeries(days: 91, trailingDays: 90)
        XCTAssertEqual(classicSeries.policy, .legacyDisplay)
        let latest = h.provider.displayWeight(from: classicSeries, asOf: .latest, appleRows: appleRows)
        XCTAssertEqual(latest?.value, 101.0, "classic: the Apple Health weight")
        XCTAssertEqual(latest?.source, .appleHealth)
        XCTAssertEqual(h.provider.displayWeightValue(latest).value, 101.0)

        XCTAssertFalse(h.defaults.wroteProfile(), "with the flag off the display path writes nothing")
    }

    /// The same store with the profile left exactly as the owner set it (the flag was never on, so
    /// nothing was mirrored): the profile fallback is that different value, 80.0, not the weigh-in.
    func testWithTheFlagNeverOnTheProfileFallbackIsTheStoredProfileValue() async throws {
        let h = try await makeHarness(flag: false)
        try await seedThreeSources(h)
        let appleRows = await h.repo.appleDailyRows()

        let series = await h.provider.displayWeightSeries(days: 91)
        XCTAssertEqual(series.policy, .legacyDisplay)
        let dated = h.provider.displayWeight(from: series, asOf: .day(dayKey(0), isCurrent: true), appleRows: appleRows)
        XCTAssertEqual(dated?.value, 101.0)
        XCTAssertEqual(dated?.source, .appleHealth)
        let before = h.provider.displayWeight(from: series, asOf: .day(dayKey(-8), isCurrent: false),
                                              appleRows: appleRows)
        XCTAssertNil(before)
        XCTAssertEqual(h.provider.displayWeightValue(before),
                       ResolvedBodyMeasurement(kind: .weight, value: 80.0, source: .profile, day: nil))
        XCTAssertEqual(h.defaults.object(forKey: weightKey) as? Double, 80.0)
        XCTAssertFalse(h.defaults.wroteProfile())
    }
}
