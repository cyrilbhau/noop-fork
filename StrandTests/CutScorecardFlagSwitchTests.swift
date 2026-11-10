import XCTest
import Combine
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard), ruling R40 of specification §18, carried into work package 1-7.
// Written before the implementation exists.
//
// The finding. Until 1-7 adds the switch, nothing can change `noop.cutScorecardEnabled` while Today
// is mounted. Once it can: (a) the Liquid and redesign weight sparkline is not resolved again when
// the policy changes, only the value is; (b) no Today view observes the flag, so a change made
// while Today stays mounted is not picked up until an unrelated body evaluation. The ruling: every
// Today view observes the flag (reading it with a default writes nothing), folds it into its weight
// task identity, and resolves value and sparkline together.
//
// What is pinned here is everything below the view layer:
//  - one observable object holds the flag, follows the key whoever writes it, and never writes it
//    by being read;
//  - one provider call returns the weight value AND the sparkline series, both resolved under one
//    policy that the result records, so a view cannot refresh one without the other;
//  - switching the flag on and then off returns both to the legacy values at once, with no refresh
//    of the repository or the provider in between;
//  - with the flag never switched on, none of this does any work.
// That each of the three Today views holds this object, puts `isEnabled` into its weight task
// identity and renders both parts of the one result is view state, and is left to review and to the
// simulator pass (§12.8).
//
// API ASSUMED BY THESE TESTS (new, in Strand/Data/CutScorecardModel.swift)
//
//     /// The one observable copy of `noop.cutScorecardEnabled`. Today, Settings and the card
//     /// editor observe this object and nothing else reads the key for display.
//     @MainActor final class CutScorecardFlag: ObservableObject {
//         init(defaults: UserDefaults = .standard)
//
//         /// The stored value, false when the key is absent. Follows every write to the key in
//         /// `defaults`, including one made by another object. Publishes only when the value changes.
//         @Published private(set) var isEnabled: Bool
//
//         /// The switch in Settings. Writes the one key.
//         func set(_ enabled: Bool)
//
//         /// `BodyMeasurementResolver.policy(flagEnabled: isEnabled, consumer: .display)`.
//         var displayPolicy: BodyMeasurementPolicy { get }
//     }
//
//     /// What a Today weight tile shows: the value and the sparkline behind it, as one reading.
//     struct BodyWeightDisplay {
//         let policy: BodyMeasurementPolicy                   // the one policy both parts were resolved under
//         let value: ResolvedBodyMeasurement                  // the dated reading, or the profile fallback
//         let isDated: Bool                                   // false when `value` is the profile fallback
//         let sparkline: [(day: String, value: Double)]
//     }
//
//     extension BodyMeasurementProvider {
//         /// `displayWeightSeries`, `displayWeight(from:asOf:appleRows:)` and `displayWeightValue`
//         /// in one step, on one read of the flag.
//         func displayWeight(days: Int, trailingDays: Int? = nil, asOf: BodyWeightAsOf,
//                            appleRows: [AppleDaily]) async -> BodyWeightDisplay
//     }
//
// Dates are relative to the real clock (ruling R31). Synthetic values only.
@MainActor
final class CutScorecardFlagSwitchTests: XCTestCase {

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
    }

    private struct Harness {
        let store: WhoopStore
        let repo: Repository
        let defaults: RecordingDefaults
        let provider: BodyMeasurementProvider
        let flag: CutScorecardFlag
    }

    private let flagKey = "noop.cutScorecardEnabled"
    private let weightKey = "profile.weightKg"
    private let started = Date()
    private var suites: [String] = []
    private var observers: [AnyCancellable] = []

    override func tearDown() {
        observers = []
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func dayKey(_ offset: Int) -> String {
        Repository.localDayKey(Calendar.current.date(byAdding: .day, value: offset, to: started) ?? started)
    }

    private func noon(_ offset: Int) -> Int {
        let day = Calendar.current.date(byAdding: .day, value: offset, to: started) ?? started
        return Int(Calendar.current.startOfDay(for: day).timeIntervalSince1970) + 12 * 3_600
    }

    private func makeDefaults() throws -> RecordingDefaults {
        let name = "CutScorecardFlagSwitchTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: name))
        suites.append(name)
        return defaults
    }

    /// The flag key is never written by the harness: it starts absent.
    private func makeHarness(profileKg: Double? = 80.0) async throws -> Harness {
        let defaults = try makeDefaults()
        if let profileKg { defaults.set(profileKg, forKey: weightKey) }
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let today = dayKey(0)
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        let flag = CutScorecardFlag(defaults: defaults)
        defaults.written = []
        return Harness(store: store, repo: repo, defaults: defaults, provider: provider, flag: flag)
    }

    /// A Lab Book weight of 97.0 kg yesterday, an older Apple Health weight of 101.0 kg six days
    /// back, and a different profile value (80.0 kg).
    private func seedThreeSources(_ h: Harness) async throws {
        let takenAt = noon(-1)
        try await h.store.upsertLabMarkers([
            LabMarkerRow(id: "weight-\(takenAt)-0A1B2C3D", deviceId: "my-whoop", markerKey: "weight",
                         category: "bodyMeasurement", day: dayKey(-1), takenAt: takenAt, value: 97.0,
                         valueText: nil, unit: "kg", source: "manual", note: nil, referenceText: nil),
        ])
        try await h.store.upsertMetricSeries([MetricPoint(day: dayKey(-6), key: "weight", value: 101.0)],
                                             deviceId: "apple-health")
        // The app has always refreshed its repository by the time a Today view loads.
        await h.repo.refresh()
    }

    private func describe(_ points: [(day: String, value: Double)]) -> [String] {
        points.map { "\($0.day)=\($0.value)" }
    }

    private func record(_ flag: CutScorecardFlag) -> () -> [Bool] {
        var seen: [Bool] = []
        flag.$isEnabled.sink { seen.append($0) }.store(in: &observers)
        return { seen }
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 5, file: StaticString = #filePath,
                           line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(what)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Long enough for a notification that would wrongly publish to have arrived.
    private func settle() async { try? await Task.sleep(nanoseconds: 150_000_000) }

    // MARK: - One observable source of truth

    func testReadingTheFlagNeverWritesTheKey() async throws {
        let defaults = try makeDefaults()
        let flag = CutScorecardFlag(defaults: defaults)
        let seen = record(flag)
        XCTAssertFalse(flag.isEnabled, "absent reads as off")
        XCTAssertEqual(flag.displayPolicy, .legacyDisplay)
        _ = CutScorecardFlag(defaults: defaults).isEnabled
        await settle()

        XCTAssertNil(defaults.object(forKey: flagKey), "the key is still absent: a default is not a write")
        XCTAssertEqual(defaults.written, [], "observing the flag writes nothing at all")
        XCTAssertEqual(seen(), [false])
    }

    func testTheFlagStartsFromTheStoredValue() throws {
        let on = try makeDefaults()
        on.set(true, forKey: flagKey)
        on.written = []
        XCTAssertTrue(CutScorecardFlag(defaults: on).isEnabled)
        XCTAssertEqual(CutScorecardFlag(defaults: on).displayPolicy, .unified)
        XCTAssertEqual(on.written, [])

        let off = try makeDefaults()
        off.set(false, forKey: flagKey)
        XCTAssertFalse(CutScorecardFlag(defaults: off).isEnabled)
    }

    /// The Settings switch calls `set`. The value is published at once, exactly once, and only the
    /// one key is written.
    func testSettingTheFlagWritesTheOneKeyAndPublishesOnce() async throws {
        let defaults = try makeDefaults()
        let flag = CutScorecardFlag(defaults: defaults)
        let seen = record(flag)

        flag.set(true)
        XCTAssertTrue(flag.isEnabled, "published before set returns: nothing waits for a later refresh")
        XCTAssertEqual(flag.displayPolicy, .unified)
        XCTAssertEqual(defaults.object(forKey: flagKey) as? Bool, true)
        await settle()
        XCTAssertEqual(seen(), [false, true], "the echo of its own write is not a second change")

        flag.set(true)
        await settle()
        XCTAssertEqual(seen(), [false, true], "setting the same value publishes nothing")

        flag.set(false)
        XCTAssertFalse(flag.isEnabled)
        XCTAssertEqual(defaults.object(forKey: flagKey) as? Bool, false)
        await settle()
        XCTAssertEqual(seen(), [false, true, false])
        XCTAssertEqual(Set(defaults.written), [flagKey], "only the flag's own key is ever written")
    }

    /// The key can be written by something that is not this object (another `CutScorecardFlag`, an
    /// `@AppStorage` toggle, `CutScorecardSettings.isEnabled`). Every observer follows it.
    func testTheFlagFollowsAWriteMadeByAnyone() async throws {
        let defaults = try makeDefaults()
        let today = CutScorecardFlag(defaults: defaults)
        let settings = CutScorecardFlag(defaults: defaults)
        let seenByToday = record(today)

        settings.set(true)
        await waitUntil("Today's copy to follow the Settings switch") { today.isEnabled }
        XCTAssertTrue(settings.isEnabled)

        defaults.set(false, forKey: flagKey)        // a plain write to the key
        await waitUntil("both copies to follow a plain write") { !today.isEnabled && !settings.isEnabled }

        CutScorecardSettings(defaults: defaults).isEnabled = true
        await waitUntil("both copies to follow CutScorecardSettings") { today.isEnabled && settings.isEnabled }

        defaults.removeObject(forKey: flagKey)
        await waitUntil("a removed key to read as off") { !today.isEnabled && !settings.isEnabled }

        await settle()
        XCTAssertEqual(seenByToday(), [false, true, false, true, false], "one publication per change")
    }

    /// An unrelated write to the same defaults is not a change of the flag.
    func testAnUnrelatedDefaultsWriteDoesNotPublish() async throws {
        let defaults = try makeDefaults()
        let flag = CutScorecardFlag(defaults: defaults)
        let seen = record(flag)
        defaults.set(81.5, forKey: weightKey)
        defaults.set("[]", forKey: "today.dashboardCards")
        await settle()
        XCTAssertEqual(seen(), [false])

        // The same observer does follow the flag's own key.
        defaults.set(true, forKey: flagKey)
        await waitUntil("the flag to follow its own key") { flag.isEnabled }
        defaults.set(82.0, forKey: weightKey)
        await settle()
        XCTAssertEqual(seen(), [false, true])
    }

    /// The object the views observe and the provider that resolves for them read the same key, so
    /// a view that keys its task on `flag.isEnabled` resolves under the policy that value means.
    func testTheFlagAndTheProviderAlwaysAgreeOnThePolicy() async throws {
        let h = try await makeHarness()
        XCTAssertEqual(h.flag.displayPolicy, h.provider.displayPolicy)
        XCTAssertEqual(h.flag.displayPolicy, .legacyDisplay)
        for value in [true, false, true, true, false] {
            h.flag.set(value)
            XCTAssertEqual(h.flag.displayPolicy, h.provider.displayPolicy, "after set(\(value))")
            XCTAssertEqual(h.flag.displayPolicy,
                           BodyMeasurementResolver.policy(flagEnabled: value, consumer: .display))
            XCTAssertNotEqual(h.flag.displayPolicy, .legacyEstimate)
        }
    }

    // MARK: - Value and sparkline together

    /// The combined reading is the three existing calls in one step, for each view's own window and
    /// as-of rule (ruling R26): Liquid and the redesign, then classic.
    func testTheCombinedReadingEqualsTheSeparateCalls() async throws {
        let h = try await makeHarness()
        try await seedThreeSources(h)
        let today = dayKey(0)
        let appleRows = await h.repo.appleDailyRows()
        let shapes: [(Int, Int?, BodyWeightAsOf, String)] = [
            (91, nil, .day(today, isCurrent: true), "Liquid and redesign, today"),
            (91, nil, .day(dayKey(-3), isCurrent: false), "Liquid and redesign, a past day"),
            (91, 90, .latest, "classic"),
        ]
        for enabled in [false, true, false] {
            h.flag.set(enabled)
            for (days, trailing, asOf, what) in shapes {
                let label = "\(what), flag \(enabled)"
                let series = await h.provider.displayWeightSeries(days: days, trailingDays: trailing)
                let dated = h.provider.displayWeight(from: series, asOf: asOf, appleRows: appleRows)
                let value = h.provider.displayWeightValue(dated)

                let together = await h.provider.displayWeight(days: days, trailingDays: trailing, asOf: asOf,
                                                              appleRows: appleRows)
                XCTAssertEqual(together.policy, series.policy, label)
                XCTAssertEqual(together.policy, h.flag.displayPolicy, label)
                XCTAssertEqual(describe(together.sparkline), describe(series.points), label)
                XCTAssertEqual(together.value, value, label)
                XCTAssertEqual(together.isDated, dated != nil, label)
            }
        }
    }

    /// Ruling R40 (a) and (b) below the view. Today is mounted with the flag off; the flag goes on;
    /// the flag goes off. Each time the one reading gives the value and the sparkline of that policy,
    /// and after the round trip both are exactly what they were before, with no refresh in between.
    func testSwitchingOnThenOffReturnsTheValueAndTheSparklineToTheLegacyValuesTogether() async throws {
        let h = try await makeHarness()
        try await seedThreeSources(h)
        let today = dayKey(0)
        let asOf = BodyWeightAsOf.day(today, isCurrent: true)

        let before = await h.provider.displayWeight(days: 91, asOf: asOf, appleRows: [])
        XCTAssertEqual(before.policy, .legacyDisplay)
        XCTAssertEqual(before.value.value, 101.0, "legacy: the Apple Health weight")
        XCTAssertEqual(before.value.source, .appleHealth)
        XCTAssertTrue(before.isDated)
        XCTAssertEqual(describe(before.sparkline), ["\(dayKey(-6))=101.0"], "legacy: the Apple Health series")

        h.flag.set(true)
        let on = await h.provider.displayWeight(days: 91, asOf: asOf, appleRows: [])
        XCTAssertEqual(on.policy, .unified)
        XCTAssertEqual(on.value.value, 97.0, "unified: the Lab Book weigh-in")
        XCTAssertEqual(on.value.source, .labBook)
        XCTAssertEqual(describe(on.sparkline), ["\(dayKey(-6))=101.0", "\(dayKey(-1))=97.0"],
                       "unified: the sparkline carries the weigh-in the value shows")

        h.flag.set(false)
        // No repository refresh, no provider refresh, no other change: the switch alone.
        let after = await h.provider.displayWeight(days: 91, asOf: asOf, appleRows: [])
        XCTAssertEqual(after.policy, .legacyDisplay)
        XCTAssertEqual(after.value, before.value, "the value is the legacy value again")
        XCTAssertEqual(describe(after.sparkline), describe(before.sparkline),
                       "and so is the sparkline, in the same reading")
        XCTAssertNotEqual(after.value.source, .labBook)
        XCTAssertFalse(after.sparkline.contains { $0.value == 97.0 },
                       "no Lab Book point is left in the sparkline once the flag is off")

        // The reading taken with the flag on can be told from a current one (ruling R38), so a view
        // that still holds it resolves again instead of restoring it.
        XCTAssertNotEqual(on.policy, h.flag.displayPolicy)
        XCTAssertEqual(after.policy, h.flag.displayPolicy)
    }

    /// The same round trip for the classic tile (90 days, the latest day).
    func testTheClassicTileMakesTheSameRoundTrip() async throws {
        let h = try await makeHarness()
        try await seedThreeSources(h)
        let before = await h.provider.displayWeight(days: 91, trailingDays: 90, asOf: .latest, appleRows: [])
        h.flag.set(true)
        let on = await h.provider.displayWeight(days: 91, trailingDays: 90, asOf: .latest, appleRows: [])
        h.flag.set(false)
        let after = await h.provider.displayWeight(days: 91, trailingDays: 90, asOf: .latest, appleRows: [])

        XCTAssertEqual(on.value.value, 97.0)
        XCTAssertEqual(on.value.source, .labBook)
        XCTAssertTrue(on.sparkline.contains { $0.value == 97.0 })
        XCTAssertEqual(before.policy, .legacyDisplay)
        XCTAssertEqual(after.policy, .legacyDisplay)
        XCTAssertEqual(after.value, before.value)
        XCTAssertEqual(describe(after.sparkline), describe(before.sparkline))
        XCTAssertEqual(before.value.value, 101.0)
    }

    /// A reading never mixes the two policies: a Lab Book value comes with a sparkline that holds
    /// its point, and a legacy value with one that holds no Lab Book point.
    func testAReadingNeverMixesTheTwoPolicies() async throws {
        let h = try await makeHarness()
        try await seedThreeSources(h)
        let asOf = BodyWeightAsOf.day(dayKey(0), isCurrent: true)
        for enabled in [true, false, true, false, false, true] {
            h.flag.set(enabled)
            let reading = await h.provider.displayWeight(days: 91, asOf: asOf, appleRows: [])
            let hasLabPoint = reading.sparkline.contains { $0.day == dayKey(-1) && $0.value == 97.0 }
            XCTAssertEqual(reading.policy == .unified, enabled)
            XCTAssertEqual(reading.value.source == .labBook, enabled, "value, flag \(enabled)")
            XCTAssertEqual(hasLabPoint, enabled, "sparkline, flag \(enabled)")
        }
    }

    /// With no dated reading at all the value is the profile fallback under either policy, and the
    /// sparkline is empty rather than a single invented point.
    func testWithNoDatedReadingTheValueIsTheProfileAndTheSparklineIsEmpty() async throws {
        let h = try await makeHarness()
        for enabled in [false, true, false] {
            h.flag.set(enabled)
            let reading = await h.provider.displayWeight(days: 91, asOf: .day(dayKey(0), isCurrent: true),
                                                         appleRows: [])
            XCTAssertEqual(reading.value.value, 80.0, "flag \(enabled)")
            XCTAssertEqual(reading.value.source, .profile, "flag \(enabled)")
            XCTAssertFalse(reading.isDated, "flag \(enabled)")
            XCTAssertTrue(reading.sparkline.isEmpty, "flag \(enabled)")
        }
    }

    // MARK: - Flag never switched on

    /// Ruling R32: with the flag off none of this does any work. Today mounted, the flag observed,
    /// the weight resolved twice, and a Lab Book row present in the store.
    func testWithTheFlagNeverSwitchedOnNothingExtraHappens() async throws {
        let h = try await makeHarness()
        try await seedThreeSources(h)
        let seen = record(h.flag)
        h.defaults.written = []
        let revision = h.provider.revision

        let first = await h.provider.displayWeight(days: 91, asOf: .day(dayKey(0), isCurrent: true), appleRows: [])
        let second = await h.provider.displayWeight(days: 91, trailingDays: 90, asOf: .latest, appleRows: [])
        await h.repo.refresh()
        await settle()

        XCTAssertEqual(first.policy, .legacyDisplay)
        XCTAssertEqual(second.policy, .legacyDisplay)
        XCTAssertEqual(first.value.value, 101.0)
        XCTAssertNotEqual(first.value.source, .labBook, "a Lab Book row in the store is not read into the display")
        XCTAssertEqual(h.provider.revision, revision, "the provider published nothing")
        XCTAssertEqual(seen(), [false], "the flag published nothing")
        XCTAssertEqual(h.defaults.written, [], "nothing was written: not the flag, not the profile mirror")
        XCTAssertNil(h.defaults.object(forKey: flagKey), "the key is still absent")
        XCTAssertEqual(h.defaults.object(forKey: weightKey) as? Double, 80.0, "the profile weight is untouched")
        XCTAssertFalse(h.flag.isEnabled)
    }
}
