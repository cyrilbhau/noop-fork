// API ASSUMED BY THESE TESTS
//
// Shared by every stage 3 app-target test (docs/personal/superapp/specs/stage-3.md). This header is
// the whole contract the stage 3 test files rely on; each file repeats the part it uses. Names and
// signatures marked [spec] are copied from the specification; those marked [assumed] are not
// stated there and are fixed here so the tests can be written ahead of the implementation.
//
// Settings and flag, Strand/Data/IntakeSettings.swift
//
//     final class IntakeSettings {                                                    [spec §9.2.1]
//         static let enabledKey = "noop.intakeEnabled"   (and every key constant of §9.2.1)
//         static let maxSupplements = 4, maxPresets = 6
//         @MainActor static let flag: ObservableDefaultsFlag
//         init(defaults: UserDefaults = .standard, scorecard: CutScorecardSettings? = nil)
//         var isEnabled: Bool { get set }
//         var source: IntakeSourceSetting { get set }
//         var hasChosenSource: Bool { get }                                            [assumed]
//             // true when `intake.source` holds one of the three stored values; tells "no source
//             // chosen yet" (§10.2 setup prompt) from "source None kept" (§10.2 Path C)
//         var healthReadEnabled: Bool { get }
//         var storedTargets: IntakeTargets? { get }
//         var targetsNeedAttention: Bool { get }
//         @discardableResult func setTargets(_ targets: IntakeTargets) -> Bool
//         func targets(on day: String) -> IntakeTargets
//         var proteinFloorGrams: Double? { get }
//         @discardableResult func setProteinFloorGrams(_ grams: Double?) -> Bool
//         var zoneLog: [IntakeZoneSegment] { get set }
//         var admittedHealthSources: Set<String>? { get set }
//         struct KnownSource: Equatable, Codable { let name: String; let lastSeenDay: String }
//         var knownHealthSources: [String: KnownSource] { get }
//         func recordHealthSource(bundleId: String, name: String, day: String)
//         var healthBackfilled: Bool { get set }
//         var supplementQuestions: [String] { get }
//         @discardableResult func addSupplementQuestion(_ question: String) -> Bool
//         func removeSupplementQuestion(_ question: String)
//         var cutoffEnabled: Bool { get set }
//         var cutoffMinuteOfDay: Int { get set }
//         var cutoffTimeSet: Bool { get set }
//         struct Preset: Equatable, Codable { let label: String; let proteinGrams: Double?; let energyKcal: Double? }
//         var quickAddPresets: [Preset] { get set }
//         static func coachVisible(_ entries: [JournalEntry], defaults: UserDefaults = .standard) -> [JournalEntry]
//     }
//
// Stage 1 ruling R45 (stage-1.md §9.2, work package 1-10), on CutScorecardSettings:          [spec]
//
//     static let proteinFloorMaximumGrams: Int            // 100_000
//     static func isWholeGramProteinFloor(_ grams: Double) -> Bool
//     var proteinFloorWholeGrams: Int? { get }
//
// Resolver and provider, Strand/Data/IntakeResolver.swift and IntakeProvider.swift            [spec §9.4]
//
//     enum IntakeSource: String { case appleHealth, quickAdd, nutritionCsv }
//     enum IntakeSourceSetting: String { case none, appleHealth, quickAdd }
//     enum IntakePolicy: Equatable { case legacy, unified(active: IntakeSourceSetting) }
//     struct ResolvedIntakeValue: Equatable { let value: Double; let source: IntakeSource; let readAtEpochSeconds: Int? }
//     struct ResolvedIntakeDay: Equatable { let day: String; let protein: ResolvedIntakeValue?; let energy: ResolvedIntakeValue? }
//     struct IntakeCandidates { var appleHealth, quickAdd, nutritionCsv: [IntakeStoredDay] }
//     enum IntakeResolver { policy(flagEnabled:sourceSetting:), order(_:), series(candidates:policy:),
//                           resolve(day:candidates:policy:) }
//     @MainActor final class IntakeProvider: ObservableObject {
//         init(repository: Repository, settings: IntakeSettings)
//         static func live(repository: Repository) -> IntakeProvider
//         static let healthSourceId = "noop-intake-health", quickAddSourceId = "noop-intake",
//                    csvSourceId = "nutrition-csv"
//         func refresh() async
//         var revision: Int { get }
//         func day(_ day: String) -> ResolvedIntakeDay?
//         func series() -> [ResolvedIntakeDay]
//         func proteinDays() -> [CutScorecardProteinDay]
//         var lastHealthOutcome: IntakeHealthSync.Outcome? { get }
//         var lastHealthAttemptAt: Date? { get }
//     }
//
//     CutScorecardInputBuilder.init(repository:provider:settings:intake:timeZone:)         [spec §9.4]
//
// Write funnels                                                                            [spec §8.2, §9.3]
//
//     @MainActor struct IntakeHealthSync {
//         enum Outcome: Equatable { case disabled, failedRead, preserved, unchanged,
//                                   written(changedDays: [String]), failedWrite }
//         init(repository: Repository, settings: IntakeSettings, now: @escaping () -> Date,
//              zoneIdentifier: @escaping () -> String)
//         func queryWindow(days: Int) -> (start: Date, end: Date, firstDay: String, lastDay: String)
//         func apply(samples: [IntakeSample]?, firstDay: String, lastDay: String) async -> Outcome
//     }
//     struct IntakeEntry: Identifiable, Equatable, Codable { let id: UUID; var loggedAt: Date; let day: String;
//                                                            var proteinGrams: Double?; var energyKcal: Double?;
//                                                            var label: String? }
//     @MainActor final class IntakeQuickAddStore {
//         enum Failure: Error, Equatable { case nothingToSave, invalidAmount, storeUnavailable }
//         init(repository: Repository, settings: IntakeSettings, defaults: UserDefaults = .standard,
//              now: @escaping () -> Date = Date.init,
//              zoneIdentifier: @escaping () -> String = { TimeZone.current.identifier })
//         func entries(day: String) -> [IntakeEntry]
//         @discardableResult func add(proteinGrams: Double?, energyKcal: Double?, label: String?,
//                                     at instant: Date) async throws -> IntakeEntry
//         func update(_ entry: IntakeEntry) async throws
//         func delete(id: UUID, day: String) async throws
//         func rebank(day: String) async throws
//         func restoredTotal(day: String) async -> IntakeStoredDay?                       [assumed]
//             // the stored `noop-intake` total of a day that has no entry list, else nil (§9.3)
//         @discardableResult func replaceRestoredTotal(day: String) async throws -> IntakeEntry   [assumed]
//             // writes one real entry holding the restored amounts and rebanks (§9.3)
//     }
//
// Everything presentational (IntakeClock, IntakePresenterInput, IntakeCard, IntakeScreenModel,
// IntakePresenter, the widget payload) is listed at the top of IntakePresenterTests.swift and
// IntakeWidgetPayloadTests.swift; the supplement tick and the cutoff reminder at the top of their
// own files.
//
// Everything else in this file is used as it exists today.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 3 (protein and intake): the harness the app-target tests share.
//
// Dates are relative to the real clock, one day back (stage 1 ruling R31; stage 3 §13.6):
// `Repository.series` and `Repository.journalEntries` are windowed on the real clock, so a fixed
// 2031 date would fall outside them. The values are the Fixture Person's (stage 1 §13, stage 3 §13.1
// and §13.6). Synthetic values only.

/// A clock one day behind the real one, fixed for the length of a test. Everything is UTC.
struct IntakeTestClock {
    let start: Date         // 00:00 UTC of "today"
    init() {
        let seconds = Int(Date().timeIntervalSince1970) - 86_400
        start = Date(timeIntervalSince1970: Double(seconds - seconds % 86_400))
    }
    /// 15:20 UTC of "today", the design round's moment.
    var now: Date { at(0, hour: 15, minute: 20) }
    var today: String { day(0) }
    func day(_ offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start.addingTimeInterval(Double(offset) * 86_400))
    }
    func at(_ offset: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        start.addingTimeInterval(Double(offset * 86_400 + hour * 3_600 + minute * 60 + second))
    }
    func epoch(_ offset: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Int {
        Int(at(offset, hour: hour, minute: minute, second: second).timeIntervalSince1970)
    }
}

/// The defaults suites one test class created, removed in its `tearDown`. No test touches
/// `UserDefaults.standard` (§12).
final class IntakeSuites {
    var names: [String] = []
    func removeAll() {
        for name in names { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        names = []
    }
}

/// A defaults suite that records every key written or removed through it.
final class IntakeRecordingDefaults: UserDefaults {
    var written: [String] = []
    /// Called after each recorded write, with the key.
    var onWrite: ((String) -> Void)?

    private func record(_ key: String) {
        written.append(key)
        onWrite?(key)
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        super.set(value, forKey: defaultName); record(defaultName)
    }
    override func set(_ value: Bool, forKey defaultName: String) {
        super.set(value, forKey: defaultName); record(defaultName)
    }
    override func set(_ value: Int, forKey defaultName: String) {
        super.set(value, forKey: defaultName); record(defaultName)
    }
    override func set(_ value: Double, forKey defaultName: String) {
        super.set(value, forKey: defaultName); record(defaultName)
    }
    override func set(_ value: Float, forKey defaultName: String) {
        super.set(value, forKey: defaultName); record(defaultName)
    }
    override func set(_ url: URL?, forKey defaultName: String) {
        super.set(url, forKey: defaultName); record(defaultName)
    }
    override func removeObject(forKey defaultName: String) {
        super.removeObject(forKey: defaultName); record(defaultName)
    }

    /// Every key this suite holds, with its value, for before-and-after comparisons.
    func snapshot(prefixes: [String] = ["noop.intake", "intake.", "cutScorecard.", "journal."]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in dictionaryRepresentation() where prefixes.contains(where: { key.hasPrefix($0) }) {
            out[key] = "\(value)"
        }
        return out
    }
}

/// The Fixture Person's stage 3 settings (§13.1).
enum IntakeFixture {
    static let floorGrams = 100.0
    static let energyLow = 2_400.0
    static let energyHigh = 2_600.0
    static let hardFloor = 2_100.0
    static let cutoffMinute = 1_200
    static let supplementName = "Fixture supplement"
    static let supplementQuestion = "Did you take Fixture supplement?"
    static let otherQuestion = "Did you drink any alcohol?"
    static let foodApp = (name: "Fixture Food", bundleId: "app.fixture.food")
    static let otherApp = (name: "Fixture Other", bundleId: "app.fixture.other")
    static let preset = (label: "Fixture shake", protein: 30.0, energy: 150.0)
    /// Stage 1 §13.2's week, oldest first: the seven days before today (§13.6).
    static let weekProtein: [Double] = [120, 120, 120, 80, 120, 120, 120]

    static var targets: IntakeTargets {
        IntakeTargets(proteinFloorGrams: nil, energyLowKcal: energyLow, energyHighKcal: energyHigh,
                      energyHardFloorKcal: hardFloor)
    }

    static let healthId = "noop-intake-health"
    static let quickAddId = "noop-intake"
    static let csvId = "nutrition-csv"
    static let appleHealthId = "apple-health"
    static let strapId = "my-whoop"
    static let intakeKeys = ["protein_g", "calories_in", "intake_read_at"]
}

/// One row of `metricSeries`, for exact before-and-after comparisons.
struct IntakeRow: Hashable, CustomStringConvertible {
    let deviceId: String
    let day: String
    let key: String
    let value: Double
    var description: String { "\(deviceId) \(day) \(key)=\(value)" }
}

@MainActor
struct IntakeHarness {
    let store: WhoopStore
    let repo: Repository
    let defaults: IntakeRecordingDefaults
    let settings: IntakeSettings
    let scorecard: CutScorecardSettings
    let provider: IntakeProvider
    let clock: IntakeTestClock

    nonisolated static let utc = TimeZone(identifier: "UTC")!
    nonisolated static let zone = "Etc/UTC"

    var today: String { clock.today }

    /// An empty store and a fresh defaults suite. `flag` is `noop.intakeEnabled`; `source` nil leaves
    /// `intake.source` absent; `floor` is written through the scorecard rules; `zoneLog` true stores
    /// the UTC zone log, so day keys are UTC days.
    static func make(flag: Bool = true, source: IntakeSourceSetting? = .appleHealth,
                     floor: Double? = IntakeFixture.floorGrams, zoneLog: Bool = true,
                     suites: IntakeSuites) async throws -> IntakeHarness {
        let name = "IntakeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(IntakeRecordingDefaults(suiteName: name))
        suites.names.append(name)
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: IntakeFixture.strapId)
        repo.setStoreForTesting(store)
        let scorecard = CutScorecardSettings(defaults: defaults)
        if let floor {
            var parameters = CutScorecardParameters.generic
            parameters.proteinFloorGrams = floor
            scorecard.parameters = parameters
        }
        if flag { defaults.set(true, forKey: "noop.intakeEnabled") }
        if let source { defaults.set(source.rawValue, forKey: "intake.source") }
        if zoneLog { defaults.set(#"[{"from":0,"tz":"Etc/UTC"}]"#, forKey: "intake.zoneLog") }
        let settings = IntakeSettings(defaults: defaults, scorecard: scorecard)
        let provider = IntakeProvider(repository: repo, settings: settings)
        defaults.written = []
        return IntakeHarness(store: store, repo: repo, defaults: defaults, settings: settings, scorecard: scorecard,
                             provider: provider, clock: IntakeTestClock())
    }

    // MARK: Seeds

    /// One day's stored totals under `deviceId`, as the funnels write them.
    func seed(_ deviceId: String, day: String, protein: Double? = nil, energy: Double? = nil,
              readAt: Int? = nil) async throws {
        var points: [MetricPoint] = []
        if let protein { points.append(MetricPoint(day: day, key: "protein_g", value: protein)) }
        if let energy { points.append(MetricPoint(day: day, key: "calories_in", value: energy)) }
        if let readAt { points.append(MetricPoint(day: day, key: "intake_read_at", value: Double(readAt))) }
        _ = try await store.upsertMetricSeries(points, deviceId: deviceId)
    }

    /// Rows that belong to nobody in stage 3: steps and weight under Apple Health, a strap score, a
    /// CSV carbohydrate figure, and a CSV protein figure ten days back.
    func seedUnrelated() async throws {
        _ = try await store.upsertMetricSeries([MetricPoint(day: clock.day(-1), key: "steps", value: 9_120),
                                                MetricPoint(day: clock.day(-1), key: "weight", value: 97.1)],
                                               deviceId: IntakeFixture.appleHealthId)
        _ = try await store.upsertMetricSeries([MetricPoint(day: clock.day(-1), key: "recovery", value: 67)],
                                               deviceId: IntakeFixture.strapId)
        _ = try await store.upsertMetricSeries([MetricPoint(day: clock.day(-10), key: "carbs_g", value: 210),
                                                MetricPoint(day: clock.day(-10), key: "protein_g", value: 60)],
                                               deviceId: IntakeFixture.csvId)
    }

    // MARK: Reads

    /// Every `metricSeries` row under the given ids, whatever its key or day.
    func rows(_ deviceIds: [String] = [IntakeFixture.healthId, IntakeFixture.quickAddId, IntakeFixture.csvId,
                                       IntakeFixture.appleHealthId, IntakeFixture.strapId]) async throws -> Set<IntakeRow> {
        var out: Set<IntakeRow> = []
        for id in deviceIds {
            for key in try await store.metricKeys(deviceId: id) {
                for point in try await store.metricSeries(deviceId: id, key: key, from: "0000-01-01", to: "9999-12-31") {
                    out.insert(IntakeRow(deviceId: id, day: point.day, key: point.key, value: point.value))
                }
            }
        }
        return out
    }

    /// The stored value of one `(deviceId, day, key)`, or nil.
    func value(_ deviceId: String, _ day: String, _ key: String) async throws -> Double? {
        try await store.metricSeries(deviceId: deviceId, key: key, from: day, to: day).first?.value
    }

    /// Rows per device id.
    static func counts(_ rows: Set<IntakeRow>) -> [String: Int] {
        Dictionary(grouping: rows, by: \.deviceId).mapValues(\.count)
    }

    // MARK: Funnels

    func healthSync(now: Date? = nil, zone: String = IntakeHarness.zone) -> IntakeHealthSync {
        let fixed = now ?? clock.now
        return IntakeHealthSync(repository: repo, settings: settings, now: { fixed }, zoneIdentifier: { zone })
    }

    func quickAdd(now: (() -> Date)? = nil, zone: (() -> String)? = nil) -> IntakeQuickAddStore {
        let fixed = clock.now
        return IntakeQuickAddStore(repository: repo, settings: settings, defaults: defaults,
                                   now: now ?? { fixed }, zoneIdentifier: zone ?? { IntakeHarness.zone })
    }

    func sample(_ id: String, _ nutrient: IntakeNutrient, _ instant: Int, _ amount: Double,
                source: String = IntakeFixture.foodApp.bundleId) -> IntakeSample {
        IntakeSample(id: id, nutrient: nutrient, startEpochSeconds: instant, amount: amount, sourceId: source)
    }
}

/// Asserts that `after` equals `before` except for the rows listed as changed, and reports the
/// difference row by row.
func assertOnlyRowsChanged(before: Set<IntakeRow>, after: Set<IntakeRow>, allowed: (IntakeRow) -> Bool,
                           _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    let removed = before.subtracting(after).filter { !allowed($0) }
    let added = after.subtracting(before).filter { !allowed($0) }
    XCTAssertTrue(removed.isEmpty && added.isEmpty,
                  "\(message) unexpected change: removed \(removed.sorted { $0.description < $1.description }), "
                  + "added \(added.sorted { $0.description < $1.description })", file: file, line: line)
}
