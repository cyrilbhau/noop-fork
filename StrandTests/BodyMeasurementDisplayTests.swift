import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard), rulings R26, R33 and R35 of specification §18. Written from the
// rulings and from the BASE commit's Today views (138cc60b), without reading the provider's
// implementation.
//
// The display path the Today views use, in the order they use it:
//
//     let series = await provider.displayWeightSeries(days: 91)                       // Liquid, redesign
//     let series = await provider.displayWeightSeries(days: 91, trailingDays: 90)     // classic
//     let dated  = provider.displayWeight(from: series, asOf: ..., appleRows: rows)   // rows = repo.appleDailyRows()
//     let shown  = provider.displayWeightValue(dated)                                 // caption "latest" when dated != nil
//
// FLAG OFF: the rules of the base commit, which these tests transcribe and pin (ruling R26).
//
//   Liquid and the redesign (138cc60b LiquidTodayView.swift:3130-3131, :3248-3252, :1613-1618;
//   RedesignTodayView.swift:608-614):
//       weightKg = appleRows.filter { $0.day == selectedDay }.compactMap { $0.weightKg }.max()
//           ?? repo.series(key: "weight", source: "apple-health", days: 91).last(where: { $0.day <= selectedDay })?.value
//       shown    = weightKg ?? profile.weightKg          caption: weightKg != nil ? "latest" : "from profile"
//
//   Classic (138cc60b TodayView.swift:3934, :4133-4140, :4694, :4708, :5165-5176, :5194-5197, :5212-5217):
//       spark    = trailingWindow(repo.series(key: "weight", source: "apple-health", days: 91), days: 90).map(\.value)
//       weightKg = appleDays.last?.weightKg ?? spark.last
//       shown    = weightKg ?? profile.weightKg          caption as above; the tile's sparkline is `spark`
//
//   `profile.weightKg` is the stored `profile.weightKg`, or 75 when it was never set (`Profile.swift:125`).
//   A Lab Book weight is not an input of either rule.
//
// API ASSUMED BY THESE TESTS
//
//  1. `BodyWeightAsOf.day` gains a second associated value (ruling R33):
//         enum BodyWeightAsOf { case day(String, isCurrent: Bool); case latest }
//     Under the unified policy with `isCurrent` true the display resolves as of the LATER of the
//     selected day and the provider's `today()`. With `isCurrent` false, and under the legacy policies
//     always, it resolves as of the selected day.
//  2. The existing surface, unchanged:
//         func displayWeightSeries(days: Int, trailingDays: Int? = nil) async -> BodyWeightSeries
//         func displayWeight(from: BodyWeightSeries, asOf: BodyWeightAsOf, appleRows: [AppleDaily]) -> ResolvedBodyMeasurement?
//         func displayWeightValue(_ dated: ResolvedBodyMeasurement?) -> ResolvedBodyMeasurement
//     With the flag off: `displayWeight` returns nil when the base rule finds no Apple Health weight
//     and otherwise a reading whose `source` is `.appleHealth`; `displayWeightValue(nil)` is the stored
//     profile weight with source `.profile`, or 75 with source `.profileDefault` when it was never set,
//     read at the time of the call; `displayWeightValue(dated)` carries the value of `dated`;
//     `BodyWeightSeries.points` holds the Apple Health `weight` series inside the view's window. With
//     the flag off none of the three needs `provider.refresh()` to have run, and none writes the profile.
//  3. No new helper is assumed for ruling R35. See the note above `testClassicTransientFrames…`.
//
// Dates are relative to the real clock (ruling R31): the repository's Apple Health reads are windowed
// on it. The flag-off cases use the provider's default `today`. Offsets of +1 day are left out because
// the upper bound of the repository's window is not on a local-day boundary. Synthetic values only.
@MainActor
final class BodyMeasurementDisplayTests: XCTestCase {

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
        override func set(_ value: Float, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func set(_ value: Int, forKey defaultName: String) {
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

    /// One store state and the value the base commit shows for it. Day offsets are relative to the
    /// real local day (0 is today).
    private struct StoreState {
        var name: String
        /// Apple Health daily rows. A nil weight is a row that carries steps and no weight.
        var daily: [(offset: Int, weightKg: Double?)] = []
        /// Apple Health `weight` series points.
        var series: [(offset: Int, kg: Double)] = []
        /// Manual Lab Book weights. Not an input of the base rule.
        var labBook: [(offset: Int, kg: Double)] = []
        /// The stored profile weight; nil is "never set".
        var profileKg: Double? = 80.0
        /// The day the wearer is looking at (Liquid and the redesign only).
        var selected: Int = 0
        /// The base commit's result: the kilograms shown, and whether the caption is "latest".
        var expectKg: Double
        var expectLatest: Bool

        var inputs: String {
            "daily \(daily.map { "\($0.offset):\($0.weightKg.map { "\($0)" } ?? "none")" }) "
                + "series \(series.map { "\($0.offset):\($0.kg)" }) labBook \(labBook.map { "\($0.offset):\($0.kg)" }) "
                + "profile \(profileKg.map { "\($0)" } ?? "never set") selected \(selected)"
        }
    }

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
        let startOfDay = Calendar.current.startOfDay(for: day)
        return Int(startOfDay.timeIntervalSince1970) + 12 * 3_600
    }

    /// `today` nil: the provider's own default clock, as in the app.
    private func makeHarness(flag: Bool, profileKg: Double?, today: String? = nil) async throws -> Harness {
        let name = "BodyMeasurementDisplayTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: name))
        suites.append(name)
        if flag { defaults.set(true, forKey: "noop.cutScorecardEnabled") }
        if let profileKg { defaults.set(profileKg, forKey: weightKey) }
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let provider: BodyMeasurementProvider
        if let today {
            provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        } else {
            provider = BodyMeasurementProvider(repository: repo, defaults: defaults)
        }
        defaults.written = []
        return Harness(store: store, repo: repo, defaults: defaults, provider: provider)
    }

    private func appleDaily(_ day: String, weightKg: Double?) -> AppleDaily {
        AppleDaily(day: day, steps: weightKg == nil ? 4_200 : nil, activeKcal: nil, basalKcal: nil, vo2max: nil,
                   avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: weightKg)
    }

    private func labWeight(_ offset: Int, _ kg: Double) -> LabMarkerRow {
        let takenAt = noon(offset)
        return LabMarkerRow(id: "weight-\(takenAt)-0A1B2C3D", deviceId: "my-whoop", markerKey: "weight",
                            category: "bodyMeasurement", day: dayKey(offset), takenAt: takenAt, value: kg,
                            valueText: nil, unit: "kg", source: "manual", note: nil, referenceText: nil)
    }

    private func seed(_ h: Harness, _ state: StoreState) async throws {
        if !state.daily.isEmpty {
            try await h.store.upsertAppleDaily(state.daily.map { appleDaily(dayKey($0.offset), weightKg: $0.weightKg) },
                                               deviceId: "apple-health")
        }
        if !state.series.isEmpty {
            try await h.store.upsertMetricSeries(
                state.series.map { MetricPoint(day: dayKey($0.offset), key: "weight", value: $0.kg) },
                deviceId: "apple-health")
        }
        if !state.labBook.isEmpty {
            try await h.store.upsertLabMarkers(state.labBook.map { labWeight($0.offset, $0.kg) })
        }
        // The app has always refreshed its repository by the time a Today view loads.
        await h.repo.refresh()
        h.defaults.written = []
    }

    private func describe(_ points: [(day: String, value: Double)]) -> [String] {
        points.map { "\($0.day)=\($0.value)" }
    }

    // MARK: - The base commit's rules, transcribed

    private func baseProfileKg(_ h: Harness) -> Double {
        h.defaults.object(forKey: weightKey) as? Double ?? 75
    }

    /// 138cc60b `LiquidTodayView.swift:3248-3252` with `weightTile` at `:1613-1618`, on the
    /// repository reads that commit made.
    private func baseSelectedDay(_ h: Harness, selected: String) async -> (kg: Double, latest: Bool) {
        let appleRows = await h.repo.appleDailyRows()
        let weightSeries = await h.repo.series(key: "weight", source: "apple-health", days: 91)
        let weightKg = appleRows.filter { $0.day == selected }.compactMap { $0.weightKg }.max()
            ?? weightSeries.last(where: { $0.day <= selected })?.value
        if let kg = weightKg { return (kg, true) }
        return (baseProfileKg(h), false)
    }

    /// 138cc60b `TodayView.swift`: `sparkValues("weight", source: "apple-health", window: 90)` at
    /// `:5165-5176` with `trailingWindow` at `:5194-5197`.
    private func baseClassicSpark(_ h: Harness) async -> [(day: String, value: Double)] {
        let all = await h.repo.series(key: "weight", source: "apple-health", days: 90 + 1)
        guard !all.isEmpty else { return [] }
        let cutoffKey = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -(90 - 1), to: Date()) ?? Date())
        return all.filter { $0.day >= cutoffKey }
    }

    /// 138cc60b `TodayView.swift`: `weightTile(aLatest?.weightKg)` at `:3934`, `:4133-4140` and
    /// `:5212-5217`, for the given loaded state.
    private func baseClassic(_ h: Harness, appleDays: [AppleDaily], spark: [Double]) -> (kg: Double, latest: Bool) {
        if let kg = appleDays.last?.weightKg ?? spark.last { return (kg, true) }
        return (baseProfileKg(h), false)
    }

    /// One readout against the base result.
    private func assertShown(_ dated: ResolvedBodyMeasurement?, _ shown: ResolvedBodyMeasurement,
                             kg: Double, latest: Bool, profileIsSet: Bool, _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(shown.value, kg,
                       "\(what): the base rule shows \(kg) kg, the provider returned \(shown.value) kg (source \(shown.source))",
                       file: file, line: line)
        XCTAssertEqual(dated != nil, latest,
                       "\(what): the base caption is \(latest ? "\"latest\"" : "\"from profile\""), the provider returned \(String(describing: dated))",
                       file: file, line: line)
        XCTAssertEqual(shown.kind, .weight, what, file: file, line: line)
        if latest {
            XCTAssertEqual(dated?.value, kg, "\(what): the dated reading", file: file, line: line)
            XCTAssertEqual(dated?.source, .appleHealth, "\(what): with the flag off only Apple Health is dated",
                           file: file, line: line)
        } else {
            XCTAssertEqual(shown, ResolvedBodyMeasurement(kind: .weight, value: kg,
                                                          source: profileIsSet ? .profile : .profileDefault, day: nil),
                           "\(what): the profile fallback", file: file, line: line)
        }
    }

    // MARK: - Flag off: Liquid and the redesign

    private var selectedDayStates: [StoreState] {
        [
            StoreState(name: "empty store", expectKg: 80.0, expectLatest: false),
            StoreState(name: "empty store, profile never set", profileKg: nil, expectKg: 75.0, expectLatest: false),
            StoreState(name: "daily weight on the selected day", daily: [(0, 99.5)], expectKg: 99.5, expectLatest: true),
            StoreState(name: "daily weight on the selected day beats the series",
                       daily: [(0, 99.5)], series: [(-2, 101.0), (0, 98.0)], expectKg: 99.5, expectLatest: true),
            StoreState(name: "no daily weight: the newest series point on or before the day",
                       series: [(-10, 101.0), (-3, 100.2)], expectKg: 100.2, expectLatest: true),
            StoreState(name: "series point on the selected day itself", series: [(-4, 100.4), (0, 99.9)],
                       expectKg: 99.9, expectLatest: true),
            StoreState(name: "daily weight on another day is not used", daily: [(-3, 101.0)],
                       expectKg: 80.0, expectLatest: false),
            StoreState(name: "daily weight on another day is not used, an older series point is",
                       daily: [(-3, 101.0)], series: [(-6, 100.6)], expectKg: 100.6, expectLatest: true),
            StoreState(name: "selected-day row without a weight falls to the series",
                       daily: [(0, nil)], series: [(-1, 100.1)], expectKg: 100.1, expectLatest: true),
            StoreState(name: "selected-day row without a weight and no series", daily: [(-2, 100.3), (0, nil)],
                       expectKg: 80.0, expectLatest: false),
            StoreState(name: "past day selected: its own daily weight", daily: [(-5, 100.9), (0, 99.0)],
                       selected: -5, expectKg: 100.9, expectLatest: true),
            StoreState(name: "past day selected: a series point after it is skipped",
                       series: [(-8, 100.5), (-2, 99.0)], selected: -5, expectKg: 100.5, expectLatest: true),
            StoreState(name: "past day selected: only later readings exist",
                       daily: [(0, 98.5)], series: [(-2, 99.0)], selected: -5, expectKg: 80.0, expectLatest: false),
            StoreState(name: "series point older than the 91-day window", series: [(-120, 103.0)],
                       expectKg: 80.0, expectLatest: false),
            StoreState(name: "series point older than the window, profile never set", series: [(-120, 103.0)],
                       profileKg: nil, expectKg: 75.0, expectLatest: false),
            StoreState(name: "series point 60 days back is inside the window", series: [(-60, 100.7)],
                       expectKg: 100.7, expectLatest: true),
            StoreState(name: "Lab Book weight beside a series point", series: [(-10, 101.0), (-3, 100.2)],
                       labBook: [(0, 97.0)], expectKg: 100.2, expectLatest: true),
            StoreState(name: "Lab Book weight beside a daily weight", daily: [(0, 99.5)], labBook: [(0, 97.0), (-7, 98.0)],
                       expectKg: 99.5, expectLatest: true),
            StoreState(name: "Lab Book weight only", labBook: [(0, 97.0)], expectKg: 80.0, expectLatest: false),
            StoreState(name: "Lab Book weight only, profile never set", labBook: [(0, 97.0)], profileKg: nil,
                       expectKg: 75.0, expectLatest: false),
        ]
    }

    /// Ruling R26 for Liquid and the redesign, over twenty store states: the selected day's daily
    /// Apple Health weight, else the newest Apple Health series point on or before the selected day
    /// within 91 days, else the profile value. `isCurrent` changes nothing under a legacy policy
    /// (ruling R33), a Lab Book weight changes nothing, and nothing is written.
    func testFlagOffSelectedDayDisplayMatchesTheBaseCommit() async throws {
        XCTAssertGreaterThanOrEqual(selectedDayStates.count, 10)
        for state in selectedDayStates {
            let h = try await makeHarness(flag: false, profileKg: state.profileKg)
            try await seed(h, state)
            let selected = dayKey(state.selected)
            let what = "[\(state.name)] \(state.inputs)"

            let base = await baseSelectedDay(h, selected: selected)
            XCTAssertEqual(base.kg, state.expectKg, "\(what): the transcribed base rule disagrees with the table")
            XCTAssertEqual(base.latest, state.expectLatest, "\(what): the transcribed base rule disagrees with the table")

            let appleRows = await h.repo.appleDailyRows()
            let series = await h.provider.displayWeightSeries(days: 91)
            let window = await h.repo.series(key: "weight", source: "apple-health", days: 91)
            XCTAssertEqual(describe(series.points), describe(window), "\(what): the series is the view's 91-day window")
            for isCurrent in [false, true] {
                let dated = h.provider.displayWeight(from: series, asOf: .day(selected, isCurrent: isCurrent),
                                                     appleRows: appleRows)
                let shown = h.provider.displayWeightValue(dated)
                assertShown(dated, shown, kg: state.expectKg, latest: state.expectLatest,
                            profileIsSet: state.profileKg != nil, "\(what) isCurrent \(isCurrent)")
            }
            XCTAssertFalse(h.defaults.wroteProfile(), "\(what): the display path wrote the profile: \(h.defaults.written)")
        }
    }

    // MARK: - Flag off: classic

    private var latestStates: [StoreState] {
        [
            StoreState(name: "empty store", expectKg: 80.0, expectLatest: false),
            StoreState(name: "empty store, profile never set", profileKg: nil, expectKg: 75.0, expectLatest: false),
            StoreState(name: "newest daily row has a weight", daily: [(-6, 100.8), (0, 99.5)],
                       expectKg: 99.5, expectLatest: true),
            StoreState(name: "newest daily row is three days old", daily: [(-3, 101.0)], expectKg: 101.0, expectLatest: true),
            StoreState(name: "newest daily row is a hundred days old", daily: [(-100, 102.0)],
                       expectKg: 102.0, expectLatest: true),
            StoreState(name: "newest daily row has no weight, an older row has, no series",
                       daily: [(-5, 101.0), (0, nil)], expectKg: 80.0, expectLatest: false),
            StoreState(name: "newest daily row has no weight, an older row has, profile never set",
                       daily: [(-5, 101.0), (0, nil)], profileKg: nil, expectKg: 75.0, expectLatest: false),
            StoreState(name: "newest daily row has no weight: the last series point",
                       daily: [(-5, 101.0), (0, nil)], series: [(-9, 100.9), (-2, 100.3)], expectKg: 100.3, expectLatest: true),
            StoreState(name: "series only", series: [(-10, 101.0), (-3, 100.2)], expectKg: 100.2, expectLatest: true),
            StoreState(name: "series point older than the trailing 90 days", series: [(-110, 103.0)],
                       expectKg: 80.0, expectLatest: false),
            StoreState(name: "series point 60 days back is inside the window", series: [(-60, 100.7)],
                       expectKg: 100.7, expectLatest: true),
            StoreState(name: "an old and a recent series point", series: [(-110, 103.0), (-20, 100.4)],
                       expectKg: 100.4, expectLatest: true),
            StoreState(name: "newest daily weight beats a newer series point", daily: [(-4, 100.8)], series: [(-1, 99.9)],
                       expectKg: 100.8, expectLatest: true),
            StoreState(name: "Lab Book weight beside a series point", series: [(-10, 101.0), (-3, 100.2)],
                       labBook: [(0, 97.0)], expectKg: 100.2, expectLatest: true),
            StoreState(name: "Lab Book weight beside a daily weight", daily: [(-1, 99.5)], labBook: [(0, 97.0), (-7, 98.0)],
                       expectKg: 99.5, expectLatest: true),
            StoreState(name: "Lab Book weight only", labBook: [(0, 97.0)], expectKg: 80.0, expectLatest: false),
            StoreState(name: "Lab Book weight only, profile never set", labBook: [(0, 97.0)], profileKg: nil,
                       expectKg: 75.0, expectLatest: false),
        ]
    }

    /// Ruling R26 for classic Today, over seventeen store states: the newest daily row's weight if
    /// that row has one, else the last point of the trailing-90-day series window, else the profile
    /// value. The tile's sparkline is that same window.
    func testFlagOffLatestDisplayMatchesTheBaseCommit() async throws {
        XCTAssertGreaterThanOrEqual(latestStates.count, 10)
        for state in latestStates {
            let h = try await makeHarness(flag: false, profileKg: state.profileKg)
            try await seed(h, state)
            let what = "[\(state.name)] \(state.inputs)"

            let appleDays = await h.repo.appleDailyRows()
            let spark = await baseClassicSpark(h)
            let base = baseClassic(h, appleDays: appleDays, spark: spark.map(\.value))
            XCTAssertEqual(base.kg, state.expectKg, "\(what): the transcribed base rule disagrees with the table")
            XCTAssertEqual(base.latest, state.expectLatest, "\(what): the transcribed base rule disagrees with the table")

            let series = await h.provider.displayWeightSeries(days: 91, trailingDays: 90)
            XCTAssertEqual(describe(series.points), describe(spark),
                           "\(what): the sparkline source is the trailing 90 days of the 91-day read")
            let dated = h.provider.displayWeight(from: series, asOf: .latest, appleRows: appleDays)
            let shown = h.provider.displayWeightValue(dated)
            assertShown(dated, shown, kg: state.expectKg, latest: state.expectLatest,
                        profileIsSet: state.profileKg != nil, what)
            XCTAssertFalse(h.defaults.wroteProfile(), "\(what): the display path wrote the profile: \(h.defaults.written)")
        }
    }

    // MARK: - Ruling R35: transient frames in classic Today

    // What can and cannot be pinned below the view layer.
    //
    // The base tile is a render-time expression of three inputs: `appleDays`, `sparks["weight"]` and
    // `profile.weightKg`. During one history-wide load the base view assigns `sparks["weight"]`
    // (`TodayView.swift:4708`) before `appleDays` (`:4750`), and on a reload each of them is stale
    // until its own assignment. Ruling R35 requires the tile to be resolved at each of those points.
    //
    // WHERE the view calls the provider is view code and cannot be reached from a unit test. What
    // can be pinned here, with the existing API and no extracted helper, is that the provider's
    // display functions ARE that render-time expression for every combination of fresh and stale
    // inputs a load passes through. A view that calls them at each assignment then matches the base
    // frame by frame. The call sites themselves are left to review.

    /// Every frame of a first load and of a reload, in the order the base view assigns its state.
    func testClassicTransientFramesResolveAsTheBaseRenderTimeExpression() async throws {
        let h = try await makeHarness(flag: false, profileKg: 80.0)
        await h.repo.refresh()

        func frame(_ series: BodyWeightSeries, _ appleDays: [AppleDaily], kg: Double, latest: Bool, _ what: String,
                   line: UInt = #line) {
            let base = baseClassic(h, appleDays: appleDays, spark: series.points.map(\.value))
            XCTAssertEqual(base.kg, kg, "\(what): the transcribed base rule disagrees with the expectation", line: line)
            XCTAssertEqual(base.latest, latest, "\(what): the transcribed base rule disagrees", line: line)
            let dated = h.provider.displayWeight(from: series, asOf: .latest, appleRows: appleDays)
            assertShown(dated, h.provider.displayWeightValue(dated), kg: kg, latest: latest, profileIsSet: true,
                        what, line: line)
        }

        // Before anything has loaded: no series, no rows.
        let emptySeries = await h.provider.displayWeightSeries(days: 91, trailingDays: 90)
        let noRows: [AppleDaily] = []
        frame(emptySeries, noRows, kg: 80.0, latest: false, "nothing loaded yet")

        // The profile is read at render time: a profile edit shows without any load.
        h.defaults.set(82.0, forKey: weightKey)
        frame(emptySeries, noRows, kg: 82.0, latest: false, "nothing loaded yet, profile edited")
        h.defaults.set(80.0, forKey: weightKey)

        // First load. The store holds a series point and a newer daily weight.
        try await h.store.upsertMetricSeries([MetricPoint(day: dayKey(-3), key: "weight", value: 100.2)],
                                             deviceId: "apple-health")
        try await h.store.upsertAppleDaily([appleDaily(dayKey(-1), weightKg: 99.5)], deviceId: "apple-health")
        let firstSeries = await h.provider.displayWeightSeries(days: 91, trailingDays: 90)
        let firstRows = await h.repo.appleDailyRows()
        frame(firstSeries, noRows, kg: 100.2, latest: true, "first load: the sparkline is assigned, the rows are not yet")
        frame(firstSeries, firstRows, kg: 99.5, latest: true, "first load: both assigned")

        // Reload. A newer series point arrives, and a newer daily row that carries no weight.
        try await h.store.upsertMetricSeries([MetricPoint(day: dayKey(-1), key: "weight", value: 99.0)],
                                             deviceId: "apple-health")
        try await h.store.upsertAppleDaily([appleDaily(dayKey(0), weightKg: nil)], deviceId: "apple-health")
        let secondSeries = await h.provider.displayWeightSeries(days: 91, trailingDays: 90)
        let secondRows = await h.repo.appleDailyRows()
        XCTAssertEqual(secondRows.last?.day, dayKey(0))
        XCTAssertNil(secondRows.last?.weightKg)
        frame(secondSeries, firstRows, kg: 99.5, latest: true, "reload: new sparkline, the rows of the previous load")
        frame(secondSeries, secondRows, kg: 99.0, latest: true, "reload: both assigned, the newest row has no weight")

        // Second reload. The series is as it was; the newest daily row gains a weight.
        try await h.store.upsertAppleDaily([appleDaily(dayKey(0), weightKg: 98.6)], deviceId: "apple-health")
        let thirdRows = await h.repo.appleDailyRows()
        frame(secondSeries, thirdRows, kg: 98.6, latest: true, "second reload: the newest row now has a weight")
        frame(emptySeries, secondRows, kg: 80.0, latest: false, "an empty sparkline with rows whose newest has no weight")
    }

    // MARK: - Ruling R33: the selected logical day against the calendar day

    /// Between midnight and 04:00 Liquid and the redesign select the previous (logical) day while
    /// the calendar day, which the estimates and the mirror use, has moved on. A weigh-in saved in
    /// those hours is dated on the calendar day and must show at once.
    func testUnifiedCurrentDayResolvesAsOfTheLaterOfTheSelectedDayAndToday() async throws {
        let today = dayKey(-2)          // D: the calendar day
        let logical = dayKey(-3)        // D-1: the day Liquid still selects before 04:00
        let h = try await makeHarness(flag: true, profileKg: 80.0, today: today)
        try await h.store.upsertLabMarkers([labWeight(-5, 100.0), labWeight(-2, 99.2)])
        await h.repo.refresh()
        await h.provider.refresh()
        let appleRows = await h.repo.appleDailyRows()
        let series = await h.provider.displayWeightSeries(days: 91)

        let current = h.provider.displayWeight(from: series, asOf: .day(logical, isCurrent: true), appleRows: appleRows)
        XCTAssertEqual(current, ResolvedBodyMeasurement(kind: .weight, value: 99.2, source: .labBook, day: today),
                       "the current day shows the reading saved on the calendar day")
        XCTAssertEqual(h.provider.displayWeightValue(current).value, 99.2)
        XCTAssertEqual(current, h.provider.current(.weight, consumer: .display),
                       "the tile and the provider's own current value are one reading")

        let past = h.provider.displayWeight(from: series, asOf: .day(logical, isCurrent: false), appleRows: appleRows)
        XCTAssertEqual(past, ResolvedBodyMeasurement(kind: .weight, value: 100.0, source: .labBook, day: dayKey(-5)),
                       "a day that is not the current one resolves as of that day")

        // When the selected day already is the calendar day, the flag makes no difference.
        let sameDay = h.provider.displayWeight(from: series, asOf: .day(today, isCurrent: true), appleRows: appleRows)
        let sameDayPast = h.provider.displayWeight(from: series, asOf: .day(today, isCurrent: false), appleRows: appleRows)
        XCTAssertEqual(sameDay, current)
        XCTAssertEqual(sameDayPast, current)
    }

    /// `isCurrent` reaches forward to today and no further: with no reading on the calendar day the
    /// current day shows what an ordinary past-day resolution shows.
    func testUnifiedCurrentDayWithoutAReadingOnTheCalendarDayIsUnchanged() async throws {
        let today = dayKey(-2)
        let logical = dayKey(-3)
        let h = try await makeHarness(flag: true, profileKg: 80.0, today: today)
        try await h.store.upsertLabMarkers([labWeight(-5, 100.0)])
        await h.repo.refresh()
        await h.provider.refresh()
        let appleRows = await h.repo.appleDailyRows()
        let series = await h.provider.displayWeightSeries(days: 91)

        let expected = ResolvedBodyMeasurement(kind: .weight, value: 100.0, source: .labBook, day: dayKey(-5))
        XCTAssertEqual(h.provider.displayWeight(from: series, asOf: .day(logical, isCurrent: true), appleRows: appleRows),
                       expected)
        XCTAssertEqual(h.provider.displayWeight(from: series, asOf: .day(logical, isCurrent: false), appleRows: appleRows),
                       expected)
    }

    /// The legacy policies are untouched by ruling R33. With the flag off and an Apple Health weight
    /// on the calendar day, the logical day still shows the reading as of the logical day, whatever
    /// `isCurrent` says, and the Lab Book weight on the calendar day is not shown at all.
    func testLegacyDisplayIgnoresIsCurrent() async throws {
        let today = dayKey(-2)
        let logical = dayKey(-3)
        let h = try await makeHarness(flag: false, profileKg: 80.0, today: today)
        try await h.store.upsertAppleDaily([appleDaily(today, weightKg: 101.5)], deviceId: "apple-health")
        try await h.store.upsertMetricSeries([MetricPoint(day: dayKey(-6), key: "weight", value: 102.0)],
                                             deviceId: "apple-health")
        try await h.store.upsertLabMarkers([labWeight(-2, 99.2)])
        await h.repo.refresh()
        let appleRows = await h.repo.appleDailyRows()
        let series = await h.provider.displayWeightSeries(days: 91)

        let base = await baseSelectedDay(h, selected: logical)
        XCTAssertEqual(base.kg, 102.0, "the base rule, for reference")
        for isCurrent in [false, true] {
            let dated = h.provider.displayWeight(from: series, asOf: .day(logical, isCurrent: isCurrent),
                                                 appleRows: appleRows)
            assertShown(dated, h.provider.displayWeightValue(dated), kg: 102.0, latest: true, profileIsSet: true,
                        "logical day, isCurrent \(isCurrent)")
        }
        // The calendar day itself shows its own daily weight, as it always did.
        let onToday = h.provider.displayWeight(from: series, asOf: .day(today, isCurrent: true), appleRows: appleRows)
        assertShown(onToday, h.provider.displayWeightValue(onToday), kg: 101.5, latest: true, profileIsSet: true,
                    "calendar day")
        XCTAssertFalse(h.defaults.wroteProfile())
    }
}
