import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

// Stage 1 (weigh-in and scorecard), ruling R41 of specification §18: ONE NUMBER PER VARIABLE.
// Written before the repair exists, from the ruling and from the surface audit of 11 November 2026.
//
// With `noop.cutScorecardEnabled` on, every surface that shows or uses the CURRENT body weight or
// waist reads `BodyMeasurementResolver` (through `BodyMeasurementProvider`, `unified` policy) and
// nothing else, and every surface that SHOWS it offers a way to correct it. A page that lists one
// source's history is labelled as that source and never calls its figure "latest" or "current".
// With the flag off every surface answers exactly as the base commit 138cc60b did, the mismatch
// between Today (Apple Health) and Settings (profile) included.
//
// The companion source scan is `Tools/test_body_measurement_single_resolver.py` (class
// `OneNumberPerVariableScanTests`): it ties each view file to the member these tests pin. Its
// "newest-as-latest" pattern constrains the labels a weight or waist series can reach, which are the
// ones `BodyMeasurementSourcePage` words below. A string that names one other metric (the steps
// chart's VoiceOver summary, "Steps chart, …, latest … steps") is not a body-series readout and is
// excluded there by name (`NOT_A_BODY_SERIES`).
//
// API ASSUMED BY THESE TESTS (new; everything else is used as it exists today)
//
//     /// A place that shows the current body weight or waist.
//     enum BodyMeasurementSurface: CaseIterable {
//         case liquidTodayWeightTile, classicTodayWeightTile, redesignTodayWeightRow
//         case settingsWeightRow, settingsWaistRow
//         case scorecardCard          // the Your Cards card and the Health tab row
//     }
//
//     /// Where a tap on such a place goes. The view binds to this value and to nothing else.
//     enum BodyMeasurementCorrectionRoute: Equatable {
//         case none                       // no tap target
//         case metricDetail(key: String)  // the catalogue page of one source's series
//         case weighInSheet, weighInHistory, scorecard
//         var offersCorrection: Bool      // true for weighInSheet, weighInHistory and scorecard only
//     }
//
//     enum BodyMeasurementCorrection {
//         /// `.unified`: a route that offers correction, for EVERY surface and whatever the source
//         /// of the value shown. Any other policy: the base commit's route, exactly:
//         /// Liquid and redesign `.metricDetail(key: "weight")`, everything else `.none`.
//         static func route(for surface: BodyMeasurementSurface,
//                           policy: BodyMeasurementPolicy) -> BodyMeasurementCorrectionRoute
//     }
//
//     /// How a page of ONE source's body-measurement series words itself. `key` is the catalogue
//     /// or marker key; only "weight" and "waist" are body measurements. For any other key, and
//     /// for every key under a legacy policy, each function returns the base commit's text.
//     enum BodyMeasurementSourcePage {
//         /// Base: `title`. Unified, body key: names the source (contains `sourceLabel`).
//         static func title(_ title: String, key: String, sourceLabel: String,
//                           policy: BodyMeasurementPolicy) -> String
//         /// The stat that carries the newest point. Base: "Latest". Unified, body key: names the
//         /// source and says neither "latest" nor "current".
//         static func newestLabel(key: String, sourceLabel: String, policy: BodyMeasurementPolicy) -> String
//         /// Base: "Latest reading". Unified, body key: neither "latest" nor "current".
//         static func newestReadingLabel(key: String, policy: BodyMeasurementPolicy) -> String
//         /// The Lab Book marker card's VoiceOver label. Base: "<name>, latest <value>, <n> readings".
//         /// Unified, body key: keeps the name, the value and the count; neither "latest" nor "current".
//         static func labBookAccessibilityLabel(name: String, value: String, readings: Int, key: String,
//                                               policy: BodyMeasurementPolicy) -> String
//     }
//
//     extension AICoachEngine {
//         /// Nil (the default) and any legacy policy: `onDeviceSignalsBlock()` is byte-identical to
//         /// the base commit. Under the unified policy the block carries no `weight` or `waist`
//         /// Lab Book marker of its own; it states `bodyMeasurements.current(.weight / .waist,
//         /// consumer: .display)` once each, in kilograms and centimetres, on a line that contains
//         /// "Weight" / "Waist" and the source name (`CutScorecardPresenter.sourceCaption`), and it
//         /// states them whatever else the Lab Book holds. A weight that is the never-written
//         /// profile default (`profileDefault`) and a waist that resolves to nil are not stated.
//         var bodyMeasurements: BodyMeasurementProvider? { get set }
//     }
//
//     extension WeighInSheetModel {
//         /// `provider` non-nil and unified: the value prefilled and offered in each field
//         /// ("Last: …") is `provider.current(kind, consumer: .display)` when that is a dated
//         /// reading, with its day and its source name (`CutScorecardPresenter.sourceCaption`) in
//         /// the hint. Nil: as today, the newest Lab Book row and no source name.
//         init(weighIns: WeighInStore, provider: BodyMeasurementProvider?, unitSystem: UnitSystem,
//              now: @escaping () -> Date, timeZone: @escaping () -> TimeZone, locale: Locale,
//              editing: WeighInHistoryRow?)
//     }
//
// Behaviour assumed for the two review findings (no new API):
//
//  A. `ScorecardPhaseDraft.startingNewPhase(today:)` takes the opened phase's start day as its floor
//     only when that phase has started (`startDay <= today`). Opened from a phase that has not
//     started, the new draft has no floor and is valid from the start.
//  B. `WeighInSheetModel.save()` and `skipWaist()` on an edit that moves the instant: when the
//     stored partner value that would be carried to the new instant is outside
//     `WeighInStore.weightRangeKg` / `waistRangeCm`, nothing is written, `phase` is `.failed` and
//     `failureMessage` names the field ("weight" or "waist", any letter case).
//
// The readouts of §8.6 and of the audit, as these tests name them. A view's body cannot be
// evaluated here, so each view is pinned at the member it must read; the source scan asserts the
// view reads that member.
//
//     Liquid Today tile, redesign row   provider.displayWeight(days: 91, asOf: .day(selected, isCurrent:), appleRows:)
//     Classic Today tile                provider.displayWeight(days: 91, trailingDays: 90, asOf: .latest, appleRows:)
//     Settings rows                     provider.current(kind, consumer: .display)
//     Calories, fitness age, VO2max,
//     Health readiness, Test Centre     provider.estimateWeightKg() / estimateWaistCm()
//     Scorecard                         CutScorecardInputBuilder, CutScorecardModel.state / .card
//     Weekly reminder                   WeighInReminder.latestWeighInDay(in:today:)
//     Backup export                     BackupSettings.snapshot(from:) over the mirrored profile keys
//     Coach context                     AICoachEngine.onDeviceSignalsBlock()
//
// Dates are relative to the real clock (two days back), because the repository's Apple Health reads
// are windowed on it (ruling R31). The two findings use the fixed 2031 fixture. Synthetic values only.

// MARK: - Shared harness

/// A clock two days behind the real one, fixed for the length of a test.
private struct OneNumberClock {
    let start: Date         // 00:00 UTC of "today"
    init() {
        let seconds = Int(Date().timeIntervalSince1970) - 2 * 86_400
        start = Date(timeIntervalSince1970: Double(seconds - seconds % 86_400))
    }
    /// 20:00 UTC of "today": later than every reading these tests date on it.
    var now: Date { start.addingTimeInterval(20 * 3_600) }
    var today: String { day(0) }
    func day(_ offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start.addingTimeInterval(Double(offset) * 86_400))
    }
    /// 07:00 UTC on `day(offset)`.
    func instant(_ offset: Int) -> Int { Int(start.timeIntervalSince1970) + offset * 86_400 + 7 * 3_600 }
}

private struct OneNumberHarness {
    let store: WhoopStore
    let repo: Repository
    let defaults: UserDefaults
    let provider: BodyMeasurementProvider
    let weighIns: WeighInStore
    let settings: CutScorecardSettings
    let builder: CutScorecardInputBuilder
    let clock: OneNumberClock
    var today: String { clock.today }

    static let deviceId = "my-whoop"
    static let utc = TimeZone(identifier: "UTC")!
    static let british = Locale(identifier: "en_GB")

    // The store of the owner's rule: a Lab Book weight and waist, an OLDER Apple Health weight and
    // a DIFFERENT profile value.
    static let labWeight = 99.2
    static let labWaist = 96.0
    static let appleWeight = 101.5
    static let profileWeight = 80.0
    static let profileWaist = 90.0

    /// An empty store. `flag` is `noop.cutScorecardEnabled`.
    @MainActor
    static func empty(flag: Bool, suites: OneNumberSuites) async throws -> OneNumberHarness {
        let name = "OneNumberPerVariableTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.names.append(name)
        if flag { defaults.set(true, forKey: "noop.cutScorecardEnabled") }
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        let clock = OneNumberClock()
        let today = clock.today
        let now = clock.now
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        let weighIns = WeighInStore(repository: repo, provider: provider, timeZone: { utc }, now: { now })
        let settings = CutScorecardSettings(defaults: defaults)
        let builder = CutScorecardInputBuilder(repository: repo, provider: provider, settings: settings,
                                               intake: IntakeProvider(repository: repo, settings: IntakeSettings(defaults: defaults)),
                                               timeZone: { utc })
        return OneNumberHarness(store: store, repo: repo, defaults: defaults, provider: provider,
                                weighIns: weighIns, settings: settings, builder: builder, clock: clock)
    }

    /// The store of the owner's rule, read once by the provider.
    @MainActor
    static func standard(flag: Bool, suites: OneNumberSuites) async throws -> OneNumberHarness {
        let h = try await empty(flag: flag, suites: suites)
        h.defaults.set(profileWeight, forKey: "profile.weightKg")
        h.defaults.set(profileWaist, forKey: "profile.waistCm")
        try await h.apple(-10, appleWeight)
        try await h.store.upsertLabMarkers([h.lab("weight", 0, labWeight), h.lab("waist", 0, labWaist)])
        // A started cut, so that the scorecard draws its curves and its card value.
        h.settings.phases = [CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: h.clock.day(-28),
                                                     targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                                     rateHighPercentPerWeek: 1.20)]
        await h.provider.refresh()
        return h
    }

    /// A Lab Book row at 07:00 UTC on `day(offset)`, under `deviceId` unless told otherwise.
    func lab(_ key: String, _ offset: Int, _ value: Double, unit: String? = nil, deviceId: String = OneNumberHarness.deviceId,
             category: String = "bodyMeasurement") -> LabMarkerRow {
        let takenAt = clock.instant(offset)
        return LabMarkerRow(id: "\(key)-\(takenAt)-0A1B2C3D", deviceId: deviceId, markerKey: key, category: category,
                            day: clock.day(offset), takenAt: takenAt, value: value, valueText: nil,
                            unit: unit ?? (key == "weight" ? "kg" : key == "waist" ? "cm" : "mmol/L"),
                            source: "manual", note: nil, referenceText: nil)
    }

    /// An Apple Health weight as an import writes it: the daily column and the series point.
    func apple(_ offset: Int, _ weightKg: Double) async throws {
        let day = clock.day(offset)
        try await store.upsertAppleDaily([AppleDaily(day: day, steps: nil, activeKcal: nil, basalKcal: nil, vo2max: nil,
                                                     avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: weightKg)],
                                         deviceId: "apple-health")
        try await store.upsertMetricSeries([MetricPoint(day: day, key: "weight", value: weightKg)], deviceId: "apple-health")
    }

    /// The resolver's own answer for today under the unified policy, from the provider's candidates.
    @MainActor
    func resolverCurrent(_ kind: BodyMeasurementKind) -> ResolvedBodyMeasurement? {
        BodyMeasurementResolver.resolve(kind, asOf: today, candidates: provider.candidates(kind), policy: .unified)
    }

    @MainActor
    func scorecardModel() -> CutScorecardModel {
        let now = clock.now
        return CutScorecardModel(repository: repo, provider: provider, settings: settings, unitSystem: { .metric },
                                 now: { now }, timeZone: { OneNumberHarness.utc }, locale: { OneNumberHarness.british })
    }

    @MainActor
    var words: CutScorecardPresenter.Wording { .init(unitSystem: .metric, locale: OneNumberHarness.british) }
}

/// The defaults suites one test class created, removed in its `tearDown`.
private final class OneNumberSuites {
    var names: [String] = []
    func removeAll() {
        for name in names { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        names = []
    }
}

/// True when `text` says "latest" or "current" in any letter case.
private func saysLatestOrCurrent(_ text: String) -> Bool {
    let lowered = text.lowercased()
    return lowered.contains("latest") || lowered.contains("current")
}

// MARK: - 1. Every surface that shows or uses the current value

/// One named test per surface of kind shows-current or uses-current. Flag on: the resolver's value.
/// Flag off: the base commit's rule.
@MainActor
final class OneNumberPerVariableCurrentValueTests: XCTestCase {
    private typealias H = OneNumberHarness
    private let suites = OneNumberSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func on() async throws -> OneNumberHarness {
        let h = try await H.standard(flag: true, suites: suites)
        // The fixture is what the rule describes: the three sources hold three different weights.
        XCTAssertEqual(h.resolverCurrent(.weight),
                       ResolvedBodyMeasurement(kind: .weight, value: H.labWeight, source: .labBook, day: h.today))
        XCTAssertEqual(h.resolverCurrent(.waist),
                       ResolvedBodyMeasurement(kind: .waist, value: H.labWaist, source: .labBook, day: h.today))
        return h
    }

    private func off() async throws -> OneNumberHarness { try await H.standard(flag: false, suites: suites) }

    // The base commit's Today rules, copied from 138cc60b so that the flag-off expectation does not
    // depend on the provider under test.

    /// `LiquidTodayView.swift:3249-3252` and `RedesignTodayView.swift:609-613` at the base commit:
    /// the Apple Health daily value of the selected day, else the newest point of the 91-day series
    /// on or before it, else the profile weight.
    private func baseSelectedDayWeight(_ h: OneNumberHarness, selected: String) async -> Double {
        let appleRows = await h.repo.appleDailyRows()
        let series = await h.repo.series(key: "weight", source: "apple-health", days: 91)
        let stored = h.defaults.object(forKey: "profile.weightKg") as? Double ?? 75
        return appleRows.filter { $0.day == selected }.compactMap { $0.weightKg }.max()
            ?? series.last(where: { $0.day <= selected })?.value
            ?? stored
    }

    /// `TodayView.swift:3934`, `:4136` and `:5212-5216` at the base commit: the newest daily row's
    /// weight, else the newest point of the 90-day sparkline, else the profile weight.
    private func baseLatestWeight(_ h: OneNumberHarness) async -> Double {
        let appleRows = await h.repo.appleDailyRows()
        let series = await h.repo.series(key: "weight", source: "apple-health", days: 91)
        let stored = h.defaults.object(forKey: "profile.weightKg") as? Double ?? 75
        return appleRows.last?.weightKg ?? series.last?.value ?? stored
    }

    private func selectedDayTile(_ h: OneNumberHarness, _ day: String, isCurrent: Bool) async -> BodyWeightDisplay {
        await h.provider.displayWeight(days: 91, asOf: .day(day, isCurrent: isCurrent),
                                       appleRows: await h.repo.appleDailyRows())
    }

    // MARK: Today, three variants

    func testLiquidTodayWeightTileShowsTheResolverValue() async throws {
        let h = try await on()
        let tile = await selectedDayTile(h, h.today, isCurrent: true)
        XCTAssertEqual(tile.value, h.resolverCurrent(.weight))
        XCTAssertEqual(tile.value.value, H.labWeight)
        XCTAssertTrue(tile.isDated)
        XCTAssertEqual(tile.policy, .unified)
        XCTAssertEqual(tile.sparkline.last?.value, H.labWeight, "the sparkline ends on the number the tile prints")
    }

    func testLiquidTodayWeightTileWithTheFlagOffShowsWhatTheBaseCommitShows() async throws {
        let h = try await off()
        let tile = await selectedDayTile(h, h.today, isCurrent: true)
        let base = await baseSelectedDayWeight(h, selected: h.today)
        XCTAssertEqual(base, H.appleWeight, "the base rule on this store is the Apple Health weight")
        XCTAssertEqual(tile.value.value, base)
        XCTAssertEqual(tile.value.source, .appleHealth)
        XCTAssertEqual(tile.sparkline.map(\.value), [H.appleWeight], "the Lab Book weigh-in is not drawn")

        // A selected day before the first Apple Health reading: the profile weight, "from profile".
        let earlier = h.clock.day(-12)
        let past = await selectedDayTile(h, earlier, isCurrent: false)
        let basePast = await baseSelectedDayWeight(h, selected: earlier)
        XCTAssertEqual(basePast, H.profileWeight)
        XCTAssertEqual(past.value.value, basePast)
        XCTAssertFalse(past.isDated)
    }

    func testRedesignTodayWeightRowShowsTheResolverValue() async throws {
        let h = try await on()
        // The redesign row and the Liquid tile read one day model, so one provider call.
        let row = await selectedDayTile(h, h.today, isCurrent: true)
        XCTAssertEqual(row.value, h.resolverCurrent(.weight))
        XCTAssertEqual(h.provider.displayWeightValue(row.isDated ? row.value : nil), h.resolverCurrent(.weight),
                       "the row prints displayWeightValue of the dated reading")

        // A past selected day shows the reading that was current then, from the same list.
        let past = await selectedDayTile(h, h.clock.day(-5), isCurrent: false)
        XCTAssertEqual(past.value, BodyMeasurementResolver.resolve(.weight, asOf: h.clock.day(-5),
                                                                   candidates: h.provider.candidates(.weight),
                                                                   policy: .unified))
        XCTAssertEqual(past.value.value, H.appleWeight)
    }

    func testRedesignTodayWeightRowWithTheFlagOffShowsWhatTheBaseCommitShows() async throws {
        let h = try await off()
        let row = await selectedDayTile(h, h.today, isCurrent: true)
        let base = await baseSelectedDayWeight(h, selected: h.today)
        XCTAssertEqual(row.value.value, base)
        XCTAssertEqual(row.value.value, H.appleWeight)
        XCTAssertEqual(row.policy, .legacyDisplay)
    }

    func testClassicTodayWeightTileShowsTheResolverValue() async throws {
        let h = try await on()
        let tile = await h.provider.displayWeight(days: 91, trailingDays: 90, asOf: .latest,
                                                  appleRows: await h.repo.appleDailyRows())
        XCTAssertEqual(tile.value, h.resolverCurrent(.weight))
        XCTAssertEqual(tile.value.value, H.labWeight)
        XCTAssertEqual(tile.sparkline.last?.value, H.labWeight)
    }

    func testClassicTodayWeightTileWithTheFlagOffShowsWhatTheBaseCommitShows() async throws {
        let h = try await off()
        let tile = await h.provider.displayWeight(days: 91, trailingDays: 90, asOf: .latest,
                                                  appleRows: await h.repo.appleDailyRows())
        let base = await baseLatestWeight(h)
        XCTAssertEqual(base, H.appleWeight)
        XCTAssertEqual(tile.value.value, base)
        XCTAssertEqual(tile.sparkline.map(\.value), [H.appleWeight])
    }

    // MARK: Profile and Settings

    func testSettingsWeightRowShowsTheResolverValue() async throws {
        let h = try await on()
        let shown = h.provider.current(.weight, consumer: .display)
        XCTAssertEqual(shown, h.resolverCurrent(.weight))
        XCTAssertNotNil(shown?.day, "a dated reading: Settings draws it in place of the stepper")
    }

    func testSettingsWaistRowShowsTheResolverValue() async throws {
        let h = try await on()
        let shown = h.provider.current(.waist, consumer: .display)
        XCTAssertEqual(shown, h.resolverCurrent(.waist))
        XCTAssertEqual(shown?.value, H.labWaist)
        XCTAssertNotNil(shown?.day)
    }

    /// With no dated reading the Settings stepper edits the profile value, and that IS the
    /// resolver's value: an edit there reaches every other surface at the next read.
    func testSettingsStepperValueIsTheResolverValueWhenNoReadingIsDated() async throws {
        let h = try await H.empty(flag: true, suites: suites)
        h.defaults.set(H.profileWeight, forKey: "profile.weightKg")
        h.defaults.set(H.profileWaist, forKey: "profile.waistCm")
        await h.provider.refresh()
        XCTAssertEqual(h.provider.current(.weight, consumer: .display),
                       ResolvedBodyMeasurement(kind: .weight, value: H.profileWeight, source: .profile, day: nil))
        XCTAssertEqual(h.provider.current(.waist, consumer: .display)?.value, H.profileWaist)

        h.defaults.set(81.5, forKey: "profile.weightKg")
        h.defaults.set(89.0, forKey: "profile.waistCm")
        XCTAssertEqual(h.provider.estimateWeightKg(), 81.5, "no refresh is needed: the profile is read at the call")
        XCTAssertEqual(h.provider.estimateWaistCm(), 89.0)
        let tile = await h.provider.displayWeight(days: 91, asOf: .day(h.today, isCurrent: true), appleRows: [])
        XCTAssertEqual(tile.value.value, 81.5)
    }

    /// Base commit `SettingsView.swift:527-556`: the two rows bind the profile value, which no
    /// weigh-in and no Apple Health reading moves while the flag is off.
    func testSettingsRowsWithTheFlagOffShowTheProfileValueOfTheBaseCommit() async throws {
        let h = try await off()
        XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, H.profileWeight)
        XCTAssertEqual(h.defaults.object(forKey: "profile.waistCm") as? Double, H.profileWaist)
        XCTAssertEqual(h.provider.current(.waist, consumer: .display)?.value, H.profileWaist)
        XCTAssertNil(h.provider.current(.waist, consumer: .display)?.day, "no dated waist exists with the flag off")
    }

    // MARK: Estimates

    private func assertEstimateWeight(_ what: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let flagOn = try await on()
        XCTAssertEqual(flagOn.provider.estimateWeightKg(), flagOn.resolverCurrent(.weight)?.value,
                       "\(what), flag on", file: file, line: line)
        XCTAssertEqual(flagOn.provider.estimateWeightKg(), H.labWeight, file: file, line: line)
        // Base commit: `UserProfile(weightKg: profile.weightKg, …)`.
        let flagOff = try await off()
        XCTAssertEqual(flagOff.provider.estimateWeightKg(), H.profileWeight, "\(what), flag off", file: file, line: line)
    }

    /// `IntelligenceEngine.swift:904`: the `UserProfile` of a scoring pass.
    func testScoringPassCalorieEstimateUsesTheResolverWeight() async throws {
        try await assertEstimateWeight("the scoring pass")
        let h = try await on()
        let profile = UserProfile(weightKg: h.provider.estimateWeightKg(), heightCm: 180, age: 40, sex: "male")
        XCTAssertEqual(profile.weightKg, H.labWeight)
    }

    /// `AppModel.swift:1049`: the `UserProfile` of a manually saved workout.
    func testManualWorkoutCalorieEstimateUsesTheResolverWeight() async throws {
        try await assertEstimateWeight("a manual workout")
    }

    /// `IntelligenceEngine.swift:641-642` and `:2622-2623`: the weight and the waist handed to
    /// `fitnessAgeRows` and `vo2MaxProvenance`.
    func testFitnessAgeAndVO2maxEstimateUseTheResolverWeightAndWaist() async throws {
        try await assertEstimateWeight("fitness age and VO2max")
        let flagOn = try await on()
        XCTAssertEqual(flagOn.provider.estimateWaistCm(), flagOn.resolverCurrent(.waist)?.value)
        XCTAssertEqual(flagOn.provider.estimateWaistCm(), H.labWaist)
        let flagOff = try await off()
        XCTAssertEqual(flagOff.provider.estimateWaistCm(), H.profileWaist, "base commit: profile.waistCm")
    }

    /// `HealthView.swift:772-773` and `:811`: "has height and weight", "has waist" and the "Add your
    /// waist" prompt.
    func testHealthReadinessChecklistUsesTheResolverWeightAndWaist() async throws {
        let flagOn = try await on()
        XCTAssertEqual(flagOn.provider.estimateWeightKg() > 0, (flagOn.resolverCurrent(.weight)?.value ?? 0) > 0)
        XCTAssertEqual(flagOn.provider.estimateWaistCm(), H.labWaist)

        // A waist logged as a weigh-in and never set in the profile: readiness has it with the flag
        // on, and with the flag off the base rule (`profile.waistCm > 0`) still says "add your waist".
        for flag in [true, false] {
            let h = try await H.empty(flag: flag, suites: suites)
            try await h.store.upsertLabMarkers([h.lab("waist", 0, H.labWaist)])
            await h.provider.refresh()
            XCTAssertEqual(h.provider.estimateWaistCm() > 0, flag, "flag \(flag)")
            XCTAssertEqual(h.provider.estimateWaistCm(), flag ? H.labWaist : 0, "flag \(flag)")
        }
    }

    /// `TestCentreView.swift:116`: the weight prefilled for the experimental ring's user record.
    func testTestCentreRingWeightPrefillUsesTheResolverWeight() async throws {
        try await assertEstimateWeight("the Test Centre prefill")
        let h = try await on()
        XCTAssertEqual(String(Int(h.provider.estimateWeightKg().rounded())), "99")
    }

    // MARK: Scorecard

    func testScorecardEvaluationInputCarriesTheResolverWeightAndWaist() async throws {
        let h = try await on()
        let result = CutScorecard.evaluate(await h.builder.build(today: h.today))
        XCTAssertEqual(result.currentWeightKg, h.resolverCurrent(.weight)?.value)
        XCTAssertEqual(result.currentWeightDay, h.resolverCurrent(.weight)?.day)
        XCTAssertEqual(result.weeks.last(where: { $0.waistCm != nil })?.waistCm, h.resolverCurrent(.waist)?.value)
    }

    private func presentation(_ h: OneNumberHarness, file: StaticString = #filePath,
                              line: UInt = #line) async throws -> CutScorecardPresentation {
        let model = h.scorecardModel()
        await model.load()
        guard case .loaded(let presentation) = model.state else {
            XCTFail("the scorecard did not load: \(model.state)", file: file, line: line)
            throw XCTSkip("no presentation")
        }
        XCTAssertEqual(model.card, presentation.card, file: file, line: line)
        return presentation
    }

    func testScorecardScreenWeightHeadlineIsTheResolverWeight() async throws {
        let h = try await on()
        let shown = try await presentation(h)
        let current = try XCTUnwrap(h.resolverCurrent(.weight))
        XCTAssertEqual(shown.weight?.value, h.words.weightNumber(current.value))
        XCTAssertEqual(shown.weight?.value, "99.2")
        XCTAssertEqual(shown.weight?.unit, "kg")
    }

    func testScorecardScreenWaistHeadlineIsTheResolverWaist() async throws {
        let h = try await on()
        let shown = try await presentation(h)
        let current = try XCTUnwrap(h.resolverCurrent(.waist))
        XCTAssertEqual(shown.waist?.value, h.words.lengthNumber(current.value))
        XCTAssertEqual(shown.waist?.value, "96.0")
    }

    /// The Your Cards card and the Health tab row draw `CutScorecardModel.card`.
    func testScorecardCardShowsTheResolverWeight() async throws {
        let h = try await on()
        let shown = try await presentation(h)
        XCTAssertEqual(shown.card.value, h.words.weightNumber(H.labWeight))
        XCTAssertTrue(shown.card.opensScorecard, "the card is its own correction route")
    }

    /// The scorecard has no second answer when the current value is an Apple Health reading.
    func testScorecardShowsTheAppleHealthWeightWhenItIsTheNewestReading() async throws {
        let h = try await H.empty(flag: true, suites: suites)
        h.defaults.set(H.profileWeight, forKey: "profile.weightKg")
        try await h.store.upsertLabMarkers([h.lab("weight", -7, 100.4)])
        try await h.apple(-2, 98.6)
        h.settings.phases = [CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: h.clock.day(-28),
                                                     targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                                     rateHighPercentPerWeek: 1.20)]
        await h.provider.refresh()
        XCTAssertEqual(h.resolverCurrent(.weight),
                       ResolvedBodyMeasurement(kind: .weight, value: 98.6, source: .appleHealth, day: h.clock.day(-2)))

        let tile = await selectedDayTile(h, h.today, isCurrent: true)
        let classic = await h.provider.displayWeight(days: 91, trailingDays: 90, asOf: .latest,
                                                     appleRows: await h.repo.appleDailyRows())
        let shown = try await presentation(h)
        XCTAssertEqual([tile.value.value, classic.value.value, h.provider.estimateWeightKg(),
                        h.provider.current(.weight, consumer: .display)?.value ?? 0,
                        h.defaults.double(forKey: "profile.weightKg")],
                       [98.6, 98.6, 98.6, 98.6, 98.6], "Today, the estimates, Settings and the mirror")
        XCTAssertEqual(shown.weight?.value, "98.6")
        XCTAssertEqual(shown.card.value, "98.6")
    }

    // MARK: Reminder, mirror, backup

    func testWeeklyReminderReadsTheDayOfTheResolverWeight() async throws {
        let h = try await on()
        XCTAssertEqual(WeighInReminder.latestWeighInDay(in: h.provider, today: h.today), h.resolverCurrent(.weight)?.day)
        XCTAssertEqual(WeighInReminder.latestWeighInDay(in: h.provider, today: h.today), h.today)
    }

    func testProfileMirrorHoldsTheResolverValues() async throws {
        let flagOn = try await on()
        XCTAssertEqual(flagOn.defaults.object(forKey: "profile.weightKg") as? Double, flagOn.resolverCurrent(.weight)?.value)
        XCTAssertEqual(flagOn.defaults.object(forKey: "profile.waistCm") as? Double, flagOn.resolverCurrent(.waist)?.value)
        let flagOff = try await off()
        XCTAssertEqual(flagOff.defaults.object(forKey: "profile.weightKg") as? Double, H.profileWeight)
        XCTAssertEqual(flagOff.defaults.object(forKey: "profile.waistCm") as? Double, H.profileWaist)
    }

    /// The `.noopbak` settings entry is the only export that carries a body weight or waist.
    func testBackupExportCarriesTheResolverValues() async throws {
        let flagOn = try await on()
        let exported = BackupSettings.snapshot(from: flagOn.defaults)
        XCTAssertEqual(exported["profile.weightKg"] as? Double, flagOn.resolverCurrent(.weight)?.value)
        XCTAssertEqual(exported["profile.waistCm"] as? Double, flagOn.resolverCurrent(.waist)?.value)

        let flagOff = try await off()
        let base = BackupSettings.snapshot(from: flagOff.defaults)
        XCTAssertEqual(base["profile.weightKg"] as? Double, H.profileWeight, "base commit: the stored profile value")
        XCTAssertEqual(base["profile.waistCm"] as? Double, H.profileWaist)
    }

    // MARK: The rule as a whole

    func testEverySurfaceShowsOneWeightAndOneWaistWithTheFlagOn() async throws {
        let h = try await on()
        let liquid = await selectedDayTile(h, h.today, isCurrent: true)
        let classic = await h.provider.displayWeight(days: 91, trailingDays: 90, asOf: .latest,
                                                     appleRows: await h.repo.appleDailyRows())
        let result = CutScorecard.evaluate(await h.builder.build(today: h.today))
        let shown = try await presentation(h)
        let exported = BackupSettings.snapshot(from: h.defaults)

        let weights: [String: Double?] = [
            "Liquid and redesign Today": liquid.value.value,
            "classic Today": classic.value.value,
            "Settings": h.provider.current(.weight, consumer: .display)?.value,
            "estimates": h.provider.estimateWeightKg(),
            "scorecard": result.currentWeightKg,
            "profile mirror": h.defaults.object(forKey: "profile.weightKg") as? Double,
            "backup": exported["profile.weightKg"] as? Double,
        ]
        for (surface, value) in weights { XCTAssertEqual(value, H.labWeight, surface) }
        XCTAssertEqual(shown.weight?.value, "99.2")
        XCTAssertEqual(shown.card.value, "99.2")

        let waists: [String: Double?] = [
            "Settings": h.provider.current(.waist, consumer: .display)?.value,
            "estimates": h.provider.estimateWaistCm(),
            "scorecard": result.weeks.last(where: { $0.waistCm != nil })?.waistCm,
            "profile mirror": h.defaults.object(forKey: "profile.waistCm") as? Double,
            "backup": exported["profile.waistCm"] as? Double,
        ]
        for (surface, value) in waists { XCTAssertEqual(value, H.labWaist, surface) }
        XCTAssertEqual(shown.waist?.value, "96.0")
    }

    /// The default state keeps the base commit's two numbers: Today shows the Apple Health weight
    /// and Settings and the estimates the profile one. The Lab Book weigh-in changes neither.
    func testTheFlagOffStateKeepsTheBaseCommitMismatch() async throws {
        let h = try await off()
        let liquid = await selectedDayTile(h, h.today, isCurrent: true)
        let classic = await h.provider.displayWeight(days: 91, trailingDays: 90, asOf: .latest,
                                                     appleRows: await h.repo.appleDailyRows())
        XCTAssertEqual(liquid.value.value, H.appleWeight)
        XCTAssertEqual(classic.value.value, H.appleWeight)
        XCTAssertEqual(h.provider.estimateWeightKg(), H.profileWeight)
        XCTAssertEqual(h.provider.estimateWaistCm(), H.profileWaist)
        XCTAssertNotEqual(liquid.value.value, h.provider.estimateWeightKg(), "the mismatch of the base commit stays")
        XCTAssertTrue(h.provider.series(.waist, consumer: .display).isEmpty)
    }
}

// MARK: - 2. The Coach context

/// `AICoachEngine.onDeviceSignalsBlock()` is the only text handed to the AI provider that carries a
/// body weight or a waist (`AICoach.swift:1265-1286`); Siri reaches it through `AskCoachIntent`.
@MainActor
final class OneNumberPerVariableCoachContextTests: XCTestCase {
    private typealias H = OneNumberHarness
    private let suites = OneNumberSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private static let labBookHeader =
        "LAB BOOK (the user's own logged health numbers — not medical advice; do not interpret as clinical findings):"

    private func engine(_ h: OneNumberHarness, attached: Bool = true) -> AICoachEngine {
        let engine = AICoachEngine(repo: h.repo)
        if attached { engine.bodyMeasurements = h.provider }
        return engine
    }

    /// Every number in `text` that is followed by one of `units`.
    private func figures(_ text: String, units: [String]) throws -> [Double] {
        let pattern = "(?<![\\w.])(\\d+(?:[.,]\\d+)?)\\s?(?:\(units.joined(separator: "|")))\\b"
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Double(text[$0].replacingOccurrences(of: ",", with: ".")) }
        }
    }

    private func weights(_ text: String) throws -> [Double] { try figures(text, units: ["kg", "lbs", "lb", "st"]) }
    private func waists(_ text: String) throws -> [Double] { try figures(text, units: ["cm", "inches", "inch", "in"]) }

    private func line(_ text: String, containing word: String) -> String? {
        text.split(separator: "\n").map(String.init).first { $0.contains(word) }
    }

    /// The Lab Book roll-up of the base commit (`AICoach.swift:1268-1286` at 138cc60b, unchanged
    /// since) for rows stored under the active strap id. The fixtures hold at most one marker per
    /// category, so the dictionary order of the base code cannot change the text.
    private func baseBlock(_ rows: [LabMarkerRow]) -> String {
        var summaries: [String] = []
        for category in LabMarkerCategory.allCases {
            let inCategory = rows.filter { $0.category == category.rawValue }
            precondition(Set(inCategory.map(\.markerKey)).count <= 1, "one marker per category in these fixtures")
            guard let latest = inCategory.sorted(by: { $0.takenAt < $1.takenAt }).last else { continue }
            let name = MarkerCatalog.definition(for: latest.markerKey)?.displayName ?? latest.markerKey
            let value = latest.value.map { "\(LabBookFormat.value($0, key: latest.markerKey)) \(latest.unit)" }
                ?? latest.valueText ?? "—"
            summaries.append("\(name) \(value)")
        }
        guard !summaries.isEmpty else { return "" }
        return ["", Self.labBookHeader, "  " + summaries.prefix(8).joined(separator: ", ")].joined(separator: "\n")
    }

    // MARK: Flag on

    /// The owner's store plus what the base line gets wrong: an older Lab Book weight, a
    /// future-dated row (the base code's "newest"), and a marker that is not a body measurement.
    func testCoachContextStatesTheResolverWeightAndWaistAndNoOtherFigure() async throws {
        let h = try await H.standard(flag: true, suites: suites)
        try await h.store.upsertLabMarkers([
            h.lab("weight", -7, 100.4), h.lab("weight", 1, 60.5),
            h.lab("waist", -7, 97.5), h.lab("waist", 1, 70.5),
            h.lab("zz-custom-marker", -3, 3.1, category: "bloodPanel"),
        ])
        await h.provider.refresh()
        XCTAssertEqual(h.resolverCurrent(.weight)?.value, H.labWeight)
        XCTAssertEqual(h.resolverCurrent(.waist)?.value, H.labWaist)

        let text = await engine(h).onDeviceSignalsBlock()
        XCTAssertEqual(try weights(text), [H.labWeight], "the resolver's weight and no other, in:\n\(text)")
        XCTAssertEqual(try waists(text), [H.labWaist], "the resolver's waist and no other, in:\n\(text)")
        XCTAssertTrue(line(text, containing: "99.2")?.contains("Weight") ?? false, text)
        XCTAssertTrue(line(text, containing: "96")?.contains("Waist") ?? false, text)
        XCTAssertTrue(line(text, containing: "99.2")?.contains("Lab Book") ?? false, "the source is named: \(text)")
        XCTAssertTrue(text.contains("3.1 mmol/L"), "the other Lab Book markers are still sent: \(text)")
        for stale in ["100.4", "60.5", "97.5", "70.5", "101.5", "80"] {
            XCTAssertFalse(text.contains(stale), "\(stale) is not the current value: \(text)")
        }
    }

    /// The same number as Today, Settings and the scorecard: read from the provider at the call.
    func testCoachContextEqualsTheOtherSurfacesAndFollowsADelete() async throws {
        let h = try await H.standard(flag: true, suites: suites)
        let coach = engine(h)
        let before = await coach.onDeviceSignalsBlock()
        XCTAssertEqual(try weights(before), [h.provider.estimateWeightKg()])

        // The Lab Book weigh-in is deleted: every surface falls back to the Apple Health weight.
        let stored = await h.weighIns.readings(.weight)
        let row = try XCTUnwrap(stored.first)
        try await h.weighIns.delete(row)
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.value, H.appleWeight)
        let after = await coach.onDeviceSignalsBlock()
        XCTAssertEqual(try weights(after), [H.appleWeight], after)
        XCTAssertTrue(line(after, containing: "101.5")?.contains("Apple Health") ?? false, after)
    }

    /// A newer Apple Health weight is the current value: the Coach says that one, as Today does.
    func testCoachContextStatesANewerAppleHealthWeight() async throws {
        let h = try await H.empty(flag: true, suites: suites)
        h.defaults.set(H.profileWeight, forKey: "profile.weightKg")
        try await h.store.upsertLabMarkers([h.lab("weight", -7, 100.4)])
        try await h.apple(-2, 98.6)
        await h.provider.refresh()

        let text = await engine(h).onDeviceSignalsBlock()
        XCTAssertEqual(try weights(text), [98.6], text)
        XCTAssertTrue(line(text, containing: "98.6")?.contains("Apple Health") ?? false, text)
        XCTAssertEqual(try waists(text), [], "no waist was ever set: \(text)")
    }

    /// No Lab Book row at all: the app shows the profile weight, so the Coach is told it.
    func testCoachContextStatesTheProfileWeightWhenNoReadingIsDated() async throws {
        let h = try await H.empty(flag: true, suites: suites)
        h.defaults.set(H.profileWeight, forKey: "profile.weightKg")
        h.defaults.set(H.profileWaist, forKey: "profile.waistCm")
        await h.provider.refresh()

        let text = await engine(h).onDeviceSignalsBlock()
        XCTAssertEqual(try weights(text), [H.profileWeight], text)
        XCTAssertEqual(try waists(text), [H.profileWaist], text)
    }

    /// A profile that was never written is not the owner's weight: the default of 75 is not sent.
    func testCoachContextDoesNotStateTheUnsetProfileDefault() async throws {
        let h = try await H.empty(flag: true, suites: suites)
        await h.provider.refresh()
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.source, .profileDefault)
        let text = await engine(h).onDeviceSignalsBlock()
        XCTAssertEqual(try weights(text), [], text)
        XCTAssertEqual(try waists(text), [], text)
    }

    /// Ruling R25: a weigh-in stored under an earlier strap id is the current value everywhere.
    /// The base line reads the active id only and would send nothing.
    func testCoachContextStatesAWeighInStoredUnderAnEarlierStrapId() async throws {
        let h = try await H.empty(flag: true, suites: suites)
        try DeviceRegistryStore(dbQueue: h.store.registryWriter).add(
            PairedDevice(id: "whoop-old", brand: "WHOOP", model: "4.0", sourceKind: .liveBLE, capabilities: [.hr],
                         status: .archived, addedAt: 1, lastSeenAt: 1))
        try await h.store.upsertLabMarkers([h.lab("weight", -3, 98.4, deviceId: "whoop-old"),
                                            h.lab("waist", -3, 95.5, deviceId: "whoop-old")])
        await h.provider.refresh()
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.value, 98.4)

        let text = await engine(h).onDeviceSignalsBlock()
        XCTAssertEqual(try weights(text), [98.4], text)
        XCTAssertEqual(try waists(text), [95.5], text)
    }

    /// The base roll-up keeps eight summaries of an unordered dictionary, so whether the weight
    /// was sent depended on hashing. The current values are stated whatever else is stored.
    func testCoachContextStatesWeightAndWaistHoweverManyOtherMarkersAreStored() async throws {
        let h = try await H.standard(flag: true, suites: suites)
        let others = (0..<12).map { h.lab("zz-marker-\($0)", -3, 3.0 + Double($0) / 10, category: "bodyMeasurement") }
        try await h.store.upsertLabMarkers(others)
        await h.provider.refresh()

        for _ in 0..<3 {
            let text = await engine(h).onDeviceSignalsBlock()
            XCTAssertEqual(try weights(text), [H.labWeight], text)
            XCTAssertEqual(try waists(text), [H.labWaist], text)
        }
    }

    // MARK: Flag off

    /// Byte for byte the base commit's block, with the provider attached and the flag off: the raw
    /// newest Lab Book row under the active id, in its own unit, future-dated or not.
    func testCoachContextWithTheFlagOffIsByteIdenticalToTheBaseCommit() async throws {
        let h = try await H.empty(flag: false, suites: suites)
        h.defaults.set(H.profileWeight, forKey: "profile.weightKg")
        try await h.apple(-10, H.appleWeight)
        let rows = [h.lab("weight", 0, H.labWeight), h.lab("weight", 1, 133.4, unit: "lb"),
                    h.lab("zz-custom-marker", -3, 3.1, category: "bloodPanel")]
        try await h.store.upsertLabMarkers(rows)
        await h.provider.refresh()

        let expected = "\n" + Self.labBookHeader + "\n  zz-custom-marker 3.1 mmol/L, Weight 133.4 lb"
        XCTAssertEqual(baseBlock(rows), expected, "the base rule, spelled out")
        let attached = await engine(h).onDeviceSignalsBlock()
        XCTAssertEqual(attached, expected)
        let detached = await engine(h, attached: false).onDeviceSignalsBlock()
        XCTAssertEqual(detached, expected, "an engine with no provider is the base engine")
    }

    func testCoachContextWithTheFlagOffKeepsTheBaseWaistLineAndSendsNoProfileOrAppleWeight() async throws {
        let h = try await H.empty(flag: false, suites: suites)
        h.defaults.set(H.profileWeight, forKey: "profile.weightKg")
        h.defaults.set(H.profileWaist, forKey: "profile.waistCm")
        try await h.apple(-10, H.appleWeight)
        await h.provider.refresh()
        let empty = await engine(h).onDeviceSignalsBlock()
        XCTAssertEqual(empty, "", "base commit: with no Lab Book row nothing is sent")

        let rows = [h.lab("waist", -7, 97.5), h.lab("waist", 0, H.labWaist)]
        try await h.store.upsertLabMarkers(rows)
        await h.provider.refresh()
        let text = await engine(h).onDeviceSignalsBlock()
        XCTAssertEqual(text, baseBlock(rows))
        XCTAssertEqual(text, "\n" + Self.labBookHeader + "\n  Waist circumference 96.0 cm")
    }
}

// MARK: - 3. Pages that list one source's history

@MainActor
final class OneNumberPerVariableSourceHistoryTests: XCTestCase {
    private typealias H = OneNumberHarness
    private let suites = OneNumberSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func weightDescriptor() throws -> MetricDescriptor {
        let all = MetricCatalog.all.filter { $0.key == "weight" }
        XCTAssertEqual(all.map(\.source), ["apple-health"], "the catalogue holds one weight series, Apple Health's")
        return try XCTUnwrap(all.first)
    }

    /// The metric page pushed from Explore and All metrics (`MetricExplorerView.swift:1322`, `:1593`,
    /// `:1648`, `:1670`, `:2395`, `:2408`).
    func testWeightMetricPageNamesAppleHealthAndNeverCallsItsFigureLatest() throws {
        let metric = try weightDescriptor()
        let source = metric.sourceLabel
        XCTAssertEqual(source, "Apple Health")

        let title = BodyMeasurementSourcePage.title(metric.title, key: metric.key, sourceLabel: source, policy: .unified)
        XCTAssertTrue(title.contains(metric.title), title)
        XCTAssertTrue(title.contains(source), "the page title names its source: \(title)")
        XCTAssertFalse(saysLatestOrCurrent(title), title)

        let stat = BodyMeasurementSourcePage.newestLabel(key: metric.key, sourceLabel: source, policy: .unified)
        XCTAssertTrue(stat.contains(source), "the stat that holds the newest point names its source: \(stat)")
        XCTAssertFalse(saysLatestOrCurrent(stat), stat)

        let caption = BodyMeasurementSourcePage.newestReadingLabel(key: metric.key, policy: .unified)
        XCTAssertFalse(caption.isEmpty)
        XCTAssertFalse(saysLatestOrCurrent(caption), caption)
    }

    func testWeightMetricPageWithTheFlagOffIsWordedAsAtTheBaseCommit() throws {
        let metric = try weightDescriptor()
        for policy in [BodyMeasurementPolicy.legacyDisplay, .legacyEstimate] {
            XCTAssertEqual(BodyMeasurementSourcePage.title(metric.title, key: metric.key,
                                                           sourceLabel: metric.sourceLabel, policy: policy), "Weight")
            XCTAssertEqual(BodyMeasurementSourcePage.newestLabel(key: metric.key, sourceLabel: metric.sourceLabel,
                                                                 policy: policy), "Latest")
            XCTAssertEqual(BodyMeasurementSourcePage.newestReadingLabel(key: metric.key, policy: policy), "Latest reading")
        }
    }

    /// The rule is about body weight and waist. Every other metric page keeps its wording in both states.
    func testOtherMetricPagesKeepTheirWordingInBothStates() {
        for policy in [BodyMeasurementPolicy.unified, .legacyDisplay] {
            for key in ["hrv", "steps", "bmi", "body_fat", "lean_mass", "weightlifting", "ldl"] {
                XCTAssertEqual(BodyMeasurementSourcePage.title("HRV", key: key, sourceLabel: "Whoop", policy: policy), "HRV", key)
                XCTAssertEqual(BodyMeasurementSourcePage.newestLabel(key: key, sourceLabel: "Whoop", policy: policy),
                               "Latest", key)
                XCTAssertEqual(BodyMeasurementSourcePage.newestReadingLabel(key: key, policy: policy), "Latest reading", key)
                XCTAssertEqual(BodyMeasurementSourcePage.labBookAccessibilityLabel(name: "LDL", value: "3.1 mmol/L",
                                                                                   readings: 4, key: key, policy: policy),
                               "LDL, latest 3.1 mmol/L, 4 readings", key)
            }
        }
    }

    /// The Compare screen and the Apple Health page name a body series through the same helper.
    func testAChartedWaistSeriesIsNamedByItsSourceToo() {
        let title = BodyMeasurementSourcePage.title("Waist circumference", key: "waist", sourceLabel: "Lab Book",
                                                    policy: .unified)
        XCTAssertTrue(title.contains("Lab Book"), title)
        XCTAssertFalse(saysLatestOrCurrent(BodyMeasurementSourcePage.newestReadingLabel(key: "waist", policy: .unified)))
    }

    /// The Lab Book marker cards (`LabBookView.swift:407`): the VoiceOver label said "latest".
    func testLabBookWeightAndWaistCardsNeverSayLatest() {
        for (key, name, value) in [("weight", "Weight", "99.2 kg"), ("waist", "Waist circumference", "96.0 cm")] {
            let label = BodyMeasurementSourcePage.labBookAccessibilityLabel(name: name, value: value, readings: 3,
                                                                            key: key, policy: .unified)
            XCTAssertTrue(label.contains(name), label)
            XCTAssertTrue(label.contains(value), label)
            XCTAssertTrue(label.contains("3"), "the reading count stays: \(label)")
            XCTAssertFalse(saysLatestOrCurrent(label), label)

            XCTAssertEqual(BodyMeasurementSourcePage.labBookAccessibilityLabel(name: name, value: value, readings: 3,
                                                                               key: key, policy: .legacyDisplay),
                           "\(name), latest \(value), 3 readings", "flag off: the base commit's label")
        }
    }

    /// The weigh-in history: every row is dated and carries its source, and nothing on the screen
    /// says "latest" or "current".
    func testWeighInHistoryRowsNameTheirSourceAndNeverSayLatest() async throws {
        let h = try await H.standard(flag: true, suites: suites)
        let weightRows = await h.weighIns.readings(.weight)
        let waistRows = await h.weighIns.readings(.waist)
        let history = CutScorecardPresenter.history(weights: weightRows, waists: waistRows,
                                                    appleHealth: h.provider.candidates(.weight).appleHealth,
                                                    unitSystem: .metric, locale: H.british)
        XCTAssertEqual(history.rows.map(\.source), [.labBook, .appleHealth])
        for row in history.rows {
            XCTAssertTrue(row.caption.contains(CutScorecardPresenter.sourceCaption(row.source)),
                          "row of \(row.day) is captioned \(row.caption)")
            XCTAssertFalse(row.dateText.isEmpty)
        }
        let apple = try XCTUnwrap(history.rows.last)
        XCTAssertFalse(apple.canEdit, "an Apple Health reading is listed, not edited")
        XCTAssertFalse(apple.canDelete)
        // The legend's "the latest one" is about which reading stands for its week, not about a figure.
        for text in ScorecardScreenFixture.strings(in: history.rows) {
            XCTAssertFalse(saysLatestOrCurrent(text), text)
        }
    }

    /// The scorecard curve names the source of the weight it prints, so an Apple Health value is
    /// not passed off as a weigh-in.
    func testScorecardWeightHeadlineNamesTheSourceOfItsValue() async throws {
        let h = try await H.empty(flag: true, suites: suites)
        try await h.apple(-2, 98.6)
        h.settings.phases = [CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: h.clock.day(-28),
                                                     targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                                     rateHighPercentPerWeek: 1.20)]
        await h.provider.refresh()
        let model = h.scorecardModel()
        await model.load()
        guard case .loaded(let shown) = model.state else { return XCTFail("the scorecard did not load") }
        XCTAssertEqual(shown.weight?.value, "98.6")
        XCTAssertTrue(shown.weight?.provenance.contains("Apple Health") ?? false, shown.weight?.provenance ?? "nil")
    }
}

// MARK: - 4. Every surface that shows the current value offers a way to correct it

@MainActor
final class OneNumberPerVariableCorrectionRouteTests: XCTestCase {
    private func route(_ surface: BodyMeasurementSurface, _ policy: BodyMeasurementPolicy) -> BodyMeasurementCorrectionRoute {
        BodyMeasurementCorrection.route(for: surface, policy: policy)
    }

    private func assertOffersCorrection(_ surface: BodyMeasurementSurface, file: StaticString = #filePath, line: UInt = #line) {
        let shown = route(surface, .unified)
        XCTAssertTrue(shown.offersCorrection, "\(surface) routes to \(shown) with the flag on", file: file, line: line)
        XCTAssertTrue([.weighInSheet, .weighInHistory, .scorecard].contains(shown), file: file, line: line)
    }

    func testOnlyTheWeighInSheetTheHistoryAndTheScorecardOfferCorrection() {
        XCTAssertTrue(BodyMeasurementCorrectionRoute.weighInSheet.offersCorrection)
        XCTAssertTrue(BodyMeasurementCorrectionRoute.weighInHistory.offersCorrection)
        XCTAssertTrue(BodyMeasurementCorrectionRoute.scorecard.offersCorrection, "it hosts Log weigh-in and History")
        XCTAssertFalse(BodyMeasurementCorrectionRoute.none.offersCorrection)
        XCTAssertFalse(BodyMeasurementCorrectionRoute.metricDetail(key: "weight").offersCorrection,
                       "the Apple Health series page has no weigh-in sheet and no history")
    }

    /// `LiquidTodayView.swift:1378-1383`: the tile always pushed the Apple Health series page.
    func testLiquidTodayWeightTileOffersCorrection() {
        assertOffersCorrection(.liquidTodayWeightTile)
        XCTAssertEqual(route(.liquidTodayWeightTile, .legacyDisplay), .metricDetail(key: "weight"),
                       "flag off: the base commit's push to the catalogue page")
    }

    /// `TodayView.swift:4170`: the tile had no tap target at all.
    func testClassicTodayWeightTileOffersCorrection() {
        assertOffersCorrection(.classicTodayWeightTile)
        XCTAssertEqual(route(.classicTodayWeightTile, .legacyDisplay), BodyMeasurementCorrectionRoute.none,
                       "flag off: the base commit's bare tile")
    }

    /// `RedesignTodayView.swift:634-640`: the row opened the scorecard only for a Lab Book reading.
    /// The route takes no source: an Apple Health or profile value is corrected the same way.
    func testRedesignTodayWeightRowOffersCorrectionWhateverTheSourceOfItsValue() {
        assertOffersCorrection(.redesignTodayWeightRow)
        XCTAssertEqual(route(.redesignTodayWeightRow, .legacyDisplay), .metricDetail(key: "weight"))
    }

    /// `SettingsView.swift:582`: "Log weigh-in" was drawn only once a dated reading existed, so the
    /// first-run state offered the profile stepper and no way into the weigh-in sheet.
    func testSettingsWeightRowOffersCorrection() {
        assertOffersCorrection(.settingsWeightRow)
        XCTAssertEqual(route(.settingsWeightRow, .legacyDisplay), BodyMeasurementCorrectionRoute.none,
                       "flag off: the stepper is the editor, as at the base commit")
    }

    func testSettingsWaistRowOffersCorrection() {
        assertOffersCorrection(.settingsWaistRow)
        XCTAssertEqual(route(.settingsWaistRow, .legacyDisplay), BodyMeasurementCorrectionRoute.none)
    }

    func testScorecardCardOpensTheScorecard() {
        XCTAssertEqual(route(.scorecardCard, .unified), .scorecard)
        XCTAssertEqual(route(.scorecardCard, .legacyDisplay), BodyMeasurementCorrectionRoute.none,
                       "flag off: the card does not exist")
    }

    func testEverySurfaceOffersCorrectionWithTheFlagOnAndNoneDoesWithItOff() {
        XCTAssertEqual(BodyMeasurementSurface.allCases.count, 6, "a new surface needs its own test above")
        for surface in BodyMeasurementSurface.allCases {
            XCTAssertTrue(route(surface, .unified).offersCorrection, "\(surface)")
            for policy in [BodyMeasurementPolicy.legacyDisplay, .legacyEstimate] {
                XCTAssertFalse(route(surface, policy).offersCorrection,
                               "\(surface): the weigh-in screens do not exist with the flag off")
            }
        }
    }
}

// MARK: - The weigh-in sheet: the value it offers, and finding B

@MainActor
final class OneNumberPerVariableWeighInSheetTests: XCTestCase {
    private typealias H = OneNumberHarness
    private typealias Fixture = ScorecardScreenFixture
    private let suites = OneNumberSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func sheet(_ h: OneNumberHarness) -> WeighInSheetModel {
        let now = h.clock.now
        return WeighInSheetModel(weighIns: h.weighIns, provider: h.provider, unitSystem: .metric, now: { now },
                                 timeZone: { H.utc }, locale: H.british, editing: nil)
    }

    // MARK: The offered "last" value is the resolver's

    /// Every correction path opens this sheet. It offered the newest Lab Book row, a second
    /// derivation of "the last weight" that ignored a newer Apple Health reading.
    func testWeighInSheetOffersTheResolverWeightWhenAppleHealthIsNewer() async throws {
        let h = try await H.empty(flag: true, suites: suites)
        try await h.store.upsertLabMarkers([h.lab("weight", -7, 100.4)])
        try await h.apple(-2, 98.6)
        await h.provider.refresh()
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.value, 98.6)

        let model = sheet(h)
        await model.prepare()
        XCTAssertTrue(model.weightHint.contains("98.6 kg"), model.weightHint)
        XCTAssertTrue(model.weightHint.contains("Apple Health"), "the offer names its source: \(model.weightHint)")
        XCTAssertFalse(model.weightHint.contains("100.4"), model.weightHint)
        XCTAssertEqual(model.weightText, "98.6", "the field is prefilled with the offered value")
    }

    func testWeighInSheetOffersTheLabBookWeightWhenItIsTheResolverValue() async throws {
        let h = try await H.standard(flag: true, suites: suites)
        let model = sheet(h)
        await model.prepare()
        XCTAssertTrue(model.weightHint.contains("99.2 kg"), model.weightHint)
        XCTAssertTrue(model.weightHint.contains("Lab Book"), model.weightHint)
        XCTAssertFalse(model.weightHint.contains("101.5"), model.weightHint)
        XCTAssertTrue(model.waistHint.contains("96.0 cm"), model.waistHint)
        XCTAssertTrue(model.waistHint.contains("Lab Book"), model.waistHint)
        XCTAssertEqual(model.weightText, "99.2")
        XCTAssertEqual(model.waistText, "96.0")
    }

    /// A row dated after today is no surface's current value, so it is not offered here either.
    func testWeighInSheetDoesNotOfferAFutureDatedReading() async throws {
        let h = try await H.empty(flag: true, suites: suites)
        try await h.store.upsertLabMarkers([h.lab("weight", -7, 100.4), h.lab("weight", 1, 60.5),
                                            h.lab("waist", -7, 97.5), h.lab("waist", 1, 70.5)])
        await h.provider.refresh()
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.value, 100.4)

        let model = sheet(h)
        await model.prepare()
        XCTAssertTrue(model.weightHint.contains("100.4 kg"), model.weightHint)
        XCTAssertFalse(model.weightHint.contains("60.5"), model.weightHint)
        XCTAssertTrue(model.waistHint.contains("97.5 cm"), model.waistHint)
        XCTAssertFalse(model.waistHint.contains("70.5"), model.waistHint)
        XCTAssertEqual(model.weightText, "100.4")
        XCTAssertEqual(model.waistText, "97.5")
    }

    // MARK: Finding B

    private struct FixedHarness {
        let store: WhoopStore
        let weighIns: WeighInStore
        let now: Date
    }

    private func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        Fixture.date(day).addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }

    private func marker(_ key: String, _ value: Double) -> LabMarkerRow {
        let takenAt = Int(at("2031-01-29", 7).timeIntervalSince1970)
        return LabMarkerRow(id: "\(key)-\(takenAt)-manu", deviceId: H.deviceId, markerKey: key,
                            category: "bodyMeasurement", day: "2031-01-29", takenAt: takenAt, value: value,
                            valueText: nil, unit: key == "weight" ? "kg" : "cm", source: "manual",
                            note: nil, referenceText: nil)
    }

    /// One reading on Wed 29 Jan 2031 at 07:00, seen from Wed 5 Feb, as the Lab Book editor could
    /// have written it: no range applies there.
    private func oneReading(weight: Double, waist: Double) async throws -> (FixedHarness, WeighInHistoryRow) {
        let name = "OneNumberPerVariableTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.names.append(name)
        defaults.set(true, forKey: "noop.cutScorecardEnabled")
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: H.deviceId)
        repo.setStoreForTesting(store)
        let now = at("2031-02-05", 7, 2)
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { "2031-02-05" })
        let weighIns = WeighInStore(repository: repo, provider: provider, timeZone: { H.utc }, now: { now })
        try await store.upsertLabMarkers([marker("weight", weight), marker("waist", waist)])
        await provider.refresh()
        let harness = FixedHarness(store: store, weighIns: weighIns, now: now)
        let history = CutScorecardPresenter.history(weights: try await rows(harness, "weight"),
                                                    waists: try await rows(harness, "waist"),
                                                    appleHealth: [], unitSystem: .metric, locale: H.british)
        let row = try XCTUnwrap(history.rows.first { $0.day == "2031-01-29" })
        XCTAssertNotNil(row.weightRow)
        XCTAssertNotNil(row.waistRow, "the out-of-range partner is part of the reading that is edited")
        return (harness, row)
    }

    private func rows(_ h: FixedHarness, _ key: String) async throws -> [LabMarkerRow] {
        try await h.store.labMarkers(deviceId: H.deviceId, markerKey: key)
            .sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
    }

    private func editSheet(_ h: FixedHarness, _ row: WeighInHistoryRow) -> WeighInSheetModel {
        let now = h.now
        return WeighInSheetModel(weighIns: h.weighIns, unitSystem: .metric, now: { now }, timeZone: { H.utc },
                                 locale: H.british, editing: row)
    }

    /// Nothing moved and nothing changed: the weight and the waist are the rows they were.
    private func assertNothingWasWritten(_ h: FixedHarness, weight: Double, waist: Double,
                                         file: StaticString = #filePath, line: UInt = #line) async throws {
        let original = Int(at("2031-01-29", 7).timeIntervalSince1970)
        let weights = try await rows(h, "weight")
        let waists = try await rows(h, "waist")
        XCTAssertEqual(weights.map(\.takenAt), [original], "the weight moved although the pair cannot", file: file, line: line)
        XCTAssertEqual(waists.map(\.takenAt), [original], file: file, line: line)
        XCTAssertEqual(weights.map(\.value), [weight], file: file, line: line)
        XCTAssertEqual(waists.map(\.value), [waist], file: file, line: line)
        XCTAssertEqual(weights.map(\.takenAt), waists.map(\.takenAt),
                       "the pair is split across two instants", file: file, line: line)
    }

    private func assertRefused(_ sheet: WeighInSheetModel, naming field: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(sheet.phase, .failed, file: file, line: line)
        let message = sheet.failureMessage ?? ""
        XCTAssertTrue(message.lowercased().contains(field), "the message must name the \(field): \"\(message)\"",
                      file: file, line: line)
    }

    /// The date is moved and the weight retyped; the waist, 230 cm from the Lab Book editor, is
    /// left alone and would be carried to the new instant, where the store refuses it.
    func testFindingBADateEditIsRefusedBeforeAnyWriteWhenTheCarriedWaistIsOutOfRange() async throws {
        let (h, row) = try await oneReading(weight: 97.4, waist: 230.0)
        XCTAssertFalse(WeighInStore.waistRangeCm.contains(230.0))
        let sheet = editSheet(h, row)
        await sheet.prepare()
        sheet.takenAt = at("2031-01-29", 6, 30)
        sheet.weightText = "97.0"
        sheet.advance()
        await sheet.save()

        try await assertNothingWasWritten(h, weight: 97.4, waist: 230.0)
        assertRefused(sheet, naming: "waist")
    }

    /// The same through Skip, which keeps a stored waist as it is and still has to move it.
    func testFindingBSkipOnADateEditIsRefusedBeforeAnyWriteWhenTheCarriedWaistIsOutOfRange() async throws {
        let (h, row) = try await oneReading(weight: 97.4, waist: 230.0)
        let sheet = editSheet(h, row)
        await sheet.prepare()
        sheet.takenAt = at("2031-01-29", 6, 30)
        sheet.advance()
        await sheet.skipWaist()

        try await assertNothingWasWritten(h, weight: 97.4, waist: 230.0)
        assertRefused(sheet, naming: "waist")
    }

    /// The mirror image: the waist is retyped and the stored weight, 280 kg, would be carried.
    func testFindingBADateEditIsRefusedBeforeAnyWriteWhenTheCarriedWeightIsOutOfRange() async throws {
        let (h, row) = try await oneReading(weight: 280.0, waist: 98.5)
        XCTAssertFalse(WeighInStore.weightRangeKg.contains(280.0))
        let sheet = editSheet(h, row)
        await sheet.prepare()
        sheet.takenAt = at("2031-01-29", 6, 30)
        sheet.advance()
        sheet.waistText = "98.0"
        await sheet.save()

        try await assertNothingWasWritten(h, weight: 280.0, waist: 98.5)
        assertRefused(sheet, naming: "weight")
    }

    /// The refusal is about a value that would be CARRIED. With the instant unchanged the waist
    /// row is not rewritten, so a weight correction still saves and the waist stays as stored.
    func testFindingBAnEditThatKeepsTheInstantDoesNotCarryThePartnerAndStillSaves() async throws {
        let (h, row) = try await oneReading(weight: 97.4, waist: 230.0)
        let sheet = editSheet(h, row)
        await sheet.prepare()
        sheet.weightText = "97.0"
        sheet.advance()
        await sheet.skipWaist()

        XCTAssertEqual(sheet.phase, .saved)
        let original = Int(at("2031-01-29", 7).timeIntervalSince1970)
        let weights = try await rows(h, "weight")
        let waists = try await rows(h, "waist")
        XCTAssertEqual(weights.map(\.value), [97.0])
        XCTAssertEqual(waists.map(\.value), [230.0], "the stored waist is not touched")
        XCTAssertEqual(weights.map(\.takenAt), [original])
        XCTAssertEqual(waists.map(\.takenAt), [original])
    }
}

// MARK: - Finding A: "Start a new phase" from a phase that has not started

@MainActor
final class OneNumberPerVariablePhaseDraftTests: XCTestCase {
    private let suites = OneNumberSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    /// One stored phase, "Later cut", starting 2031-03-03.
    private func settingsWithOnePhase() throws -> CutScorecardSettings {
        let name = "OneNumberPerVariableTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.names.append(name)
        let settings = CutScorecardSettings(defaults: defaults)
        settings.phases = [CutScorecardStoredPhase(kind: .cut, name: "Later cut", startDay: "2031-03-03",
                                                   targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                                   rateHighPercentPerWeek: 1.20)]
        return settings
    }

    /// The sheet opened on 6 January shows the stored phase that starts in March. "Start a new
    /// phase" proposes today; the March phase is not a floor for it, because it has not started.
    func testFindingAStartingANewPhaseFromAPhaseThatHasNotStartedIsValidFromTheStart() throws {
        let settings = try settingsWithOnePhase()
        let opened = ScorecardPhaseDraft.current(settings: settings, today: "2031-01-06")
        XCTAssertEqual(opened.name, "Later cut", "with no active phase the sheet opens the next stored one")
        XCTAssertFalse(opened.isNewPhase)

        var next = opened.startingNewPhase(today: "2031-01-06")
        XCTAssertTrue(next.isNewPhase)
        XCTAssertEqual(next.startDay, "2031-01-06")
        XCTAssertFalse(next.invalidFields.contains(.startDay), "the draft is invalid before the owner typed anything")
        XCTAssertNil(next.earliestStartDay, "a phase that has not started is not a floor")

        next.name = "Bridge cut"
        XCTAssertEqual(next.invalidFields, [])
        XCTAssertNil(next.validationMessage)
        XCTAssertTrue(next.canSave)
        XCTAssertTrue(next.save(to: settings))
        XCTAssertEqual(settings.phases.map(\.startDay), ["2031-01-06", "2031-03-03"])
        XCTAssertEqual(settings.activePhase(on: "2031-01-06")?.name, "Bridge cut")
        XCTAssertEqual(settings.activePhase(on: "2031-03-03")?.name, "Later cut", "the March phase still takes over in March")
    }

    /// With no floor the new phase can also be backdated, as a first phase can.
    func testFindingAANewPhaseAheadOfAnUnstartedOneCanBeBackdated() throws {
        let settings = try settingsWithOnePhase()
        var next = ScorecardPhaseDraft.current(settings: settings, today: "2031-01-06")
            .startingNewPhase(today: "2031-01-06")
        next.name = "Bridge cut"
        next.startDay = "2030-12-02"
        XCTAssertEqual(next.invalidFields, [])
        XCTAssertTrue(next.save(to: settings))
        XCTAssertEqual(settings.phases.map(\.name), ["Bridge cut", "Later cut"])
    }

    /// The floor still applies once the opened phase has started, the day it starts included.
    func testFindingATheFloorStillAppliesFromTheDayTheOpenedPhaseStarts() throws {
        for today in ["2031-03-03", "2031-06-05"] {
            let settings = try settingsWithOnePhase()
            var next = ScorecardPhaseDraft.current(settings: settings, today: today).startingNewPhase(today: today)
            next.name = "Second cut"
            XCTAssertEqual(next.earliestStartDay, "2031-03-03", today)
            XCTAssertEqual(next.invalidFields, [], today)

            next.startDay = "2031-02-01"
            XCTAssertEqual(next.invalidFields, [.startDay], today)
            XCTAssertFalse(next.save(to: settings), today)
            XCTAssertEqual(settings.phases.map(\.name), ["Later cut"], "nothing is written")
        }
    }
}
