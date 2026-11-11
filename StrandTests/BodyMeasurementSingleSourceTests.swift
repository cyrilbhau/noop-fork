import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard), specification §8.5, §8.6 item 2, §12.3, §12.5, fault line F28 and
// ruling R25. Written before the implementation exists, from the specification.
//
// The behavioural half of "no reader bypasses the resolver". The source scan
// (`Tools/test_body_measurement_single_resolver.py`) polices spellings; this file asserts that the
// readouts are the same number and move together.
//
// API ASSUMED BY THESE TESTS
//
//     @MainActor final class BodyMeasurementProvider: ObservableObject {
//         init(repository: Repository, defaults: UserDefaults = .standard,
//              today: @escaping () -> String = { Repository.localDayKey(Date()) })
//         func refresh() async
//         func candidates(_ kind: BodyMeasurementKind) -> BodyMeasurementCandidates
//         func series(_ kind: BodyMeasurementKind, consumer: BodyMeasurementConsumer) -> [DatedBodyMeasurement]
//         func current(_ kind: BodyMeasurementKind, consumer: BodyMeasurementConsumer) -> ResolvedBodyMeasurement?
//         func resolve(_ kind: BodyMeasurementKind, asOf day: String,
//                      consumer: BodyMeasurementConsumer) -> ResolvedBodyMeasurement?
//     }
//
// Behaviour assumed of the provider:
//
//  1. `refresh()` fetches the candidates through `repository.storeHandle()`:
//       - Lab Book rows of `weight` and `waist` under every device id present in `labMarker`,
//         registered or not (ruling R42 and labbook-ownership.md §6.2, superseding the union of
//         R25), read through `LabBookRows.marker`: rows equal in content are one reading with the
//         active id's row standing for it, and rows that differ are both candidates;
//       - Apple Health weight from `appleDaily.weightKg` and from `metricSeries` key `weight` under
//         `apple-health`, merged per day, the daily column winning;
//       - the profile value from `defaults`: key `profile.weightKg` (absent: 75, `profileIsSet`
//         false) and key `profile.waistCm` (absent: 0).
//  2. The flag is `defaults.bool(forKey: "noop.cutScorecardEnabled")`, read at each `refresh()`.
//  3. `candidates`, `series`, `current` and `resolve` are synchronous reads of the snapshot the last
//     `refresh()` took. `current` is `resolve` as of `today()`. The policy is
//     `BodyMeasurementResolver.policy(flagEnabled:consumer:)`.
//  4. The mirror of §8.5 is written inside `refresh()` and nowhere else: only with the flag on, only
//     when today's resolved value came from a dated reading, and only when the stored value differs.
//     It is written to `defaults` under the two profile keys.
//  5. The provider reads no profile object. The app's `ProfileStore` is fixed to
//     `UserDefaults.standard` (`Profile.swift:82`), so it cannot be isolated in a test; how the live
//     `ProfileStore` learns of a mirror write is the implementation's to settle and is not tested here.
//
// The readouts of §8.6, as these tests name them (the call sites are migrated by the implementer and
// cannot be exercised here; the source scan covers them):
//
//     Today tile input          provider.current(.weight, consumer: .display)
//     UserProfile for estimates provider.current(.weight, consumer: .estimate)
//     Health readiness input    provider.current(.weight / .waist, consumer: .estimate)
//     Scorecard                 CutScorecard.evaluate(builder.build(today:)).currentWeightKg
//
// `WeighInStore`, `CutScorecardSettings` and `CutScorecardInputBuilder` are used as assumed at the top
// of `WeighInStoreTests.swift`, `CutScorecardSettingsTests.swift` and `CutScorecardInputBuilderTests.swift`.
//
// Dates: tests that involve Apple Health are dated relative to the real clock (two days back),
// because the repository's Apple Health reads are windowed on the real clock. Tests on Lab Book rows
// alone use the fixed 2031 fixture of specification §13. Synthetic values only.
@MainActor
final class BodyMeasurementSingleSourceTests: XCTestCase {

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

    /// A clock two days behind the real one, fixed for the length of a test.
    private struct Clock {
        let start: Date         // 00:00 UTC of "today"
        init() {
            let seconds = Int(Date().timeIntervalSince1970) - 2 * 86_400
            start = Date(timeIntervalSince1970: Double(seconds - seconds % 86_400))
        }
        /// 20:00 UTC of "today": later than every reading these tests save on it.
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
        func instant(_ offset: Int) -> Date { start.addingTimeInterval(Double(offset) * 86_400 + 7 * 3_600) }
    }

    private struct Harness {
        let store: WhoopStore
        let repo: Repository
        let defaults: RecordingDefaults
        let provider: BodyMeasurementProvider
        let weighIns: WeighInStore
        let settings: CutScorecardSettings
        let builder: CutScorecardInputBuilder
        let today: String
    }

    private var suites: [String] = []
    private let utc = TimeZone(identifier: "UTC")!

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func makeHarness(today: String, now: Date, flag: Bool, deviceId: String = "my-whoop") async throws -> Harness {
        let name = "BodyMeasurementSingleSourceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: name))
        suites.append(name)
        if flag { defaults.set(true, forKey: "noop.cutScorecardEnabled") }
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        let zone = utc
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        let weighIns = WeighInStore(repository: repo, provider: provider, timeZone: { zone }, now: { now })
        let settings = CutScorecardSettings(defaults: defaults)
        let builder = CutScorecardInputBuilder(repository: repo, provider: provider, settings: settings,
                                               intake: IntakeProvider(repository: repo, settings: IntakeSettings(defaults: defaults)),
                                               timeZone: { zone })
        defaults.written = []
        return Harness(store: store, repo: repo, defaults: defaults, provider: provider, weighIns: weighIns,
                       settings: settings, builder: builder, today: today)
    }

    private func appleDaily(_ day: String, weightKg: Double) -> AppleDaily {
        AppleDaily(day: day, steps: nil, activeKcal: nil, basalKcal: nil, vo2max: nil, avgHr: nil,
                   maxHr: nil, walkingHr: nil, weightKg: weightKg)
    }

    private func labRow(_ key: String, deviceId: String, day: String, takenAt: Int, value: Double,
                        suffix: String = "0A1B2C3D") -> LabMarkerRow {
        LabMarkerRow(id: "\(key)-\(takenAt)-\(suffix)", deviceId: deviceId, markerKey: key,
                     category: "bodyMeasurement", day: day, takenAt: takenAt, value: value, valueText: nil,
                     unit: key == "weight" ? "kg" : "cm", source: "manual", note: nil, referenceText: nil)
    }

    /// The four readouts of §8.6 for a weight, in the order of the table at the top of this file.
    private func weightReadouts(_ h: Harness) async -> [Double?] {
        let input = await h.builder.build(today: h.today)
        return [h.provider.current(.weight, consumer: .display)?.value,
                h.provider.current(.weight, consumer: .estimate)?.value,
                h.provider.resolve(.weight, asOf: h.today, consumer: .estimate)?.value,
                CutScorecard.evaluate(input).currentWeightKg]
    }

    /// The same for a waist. The scorecard's "current waist" is the newest weekly point that has one.
    private func waistReadouts(_ h: Harness) async -> [Double?] {
        let input = await h.builder.build(today: h.today)
        let result = CutScorecard.evaluate(input)
        return [h.provider.current(.waist, consumer: .display)?.value,
                h.provider.current(.waist, consumer: .estimate)?.value,
                h.provider.resolve(.waist, asOf: h.today, consumer: .estimate)?.value,
                result.weeks.last(where: { $0.waistCm != nil })?.waistCm]
    }

    private func bodyRowCount(_ store: WhoopStore, _ deviceId: String) async throws -> Int {
        try await store.labMarkers(deviceId: deviceId, category: "bodyMeasurement").count
    }

    // MARK: - §8.6 item 2

    /// A Lab Book weight, an OLDER Apple Health weight and a DIFFERENT profile value: every reader
    /// reports the Lab Book number, and the scorecard's current weight is that number too.
    func testTodayEstimateReadinessAndScorecardShareOneWeight() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: true)
        h.defaults.set(80.0, forKey: "profile.weightKg")
        try await h.store.upsertAppleDaily([appleDaily(clock.day(-10), weightKg: 101.5)], deviceId: "apple-health")
        try await h.store.upsertMetricSeries([MetricPoint(day: clock.day(-12), key: "weight", value: 102.0)],
                                             deviceId: "apple-health")
        try await h.weighIns.save(weight: 99.2, waist: nil, unitSystem: .metric, takenAt: clock.instant(0))

        let readouts = await weightReadouts(h)
        XCTAssertEqual(readouts, [99.2, 99.2, 99.2, 99.2],
                       "Today, the estimates, the readiness input and the scorecard must be one number")
        XCTAssertEqual(h.provider.current(.weight, consumer: .display),
                       ResolvedBodyMeasurement(kind: .weight, value: 99.2, source: .labBook, day: clock.today))
        XCTAssertEqual(h.provider.current(.weight, consumer: .display), h.provider.current(.weight, consumer: .estimate),
                       "with the flag on the two consumers share a policy and so a value, a source and a day")
    }

    func testTodayEstimateReadinessAndScorecardShareOneWaist() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: true)
        h.defaults.set(80.0, forKey: "profile.weightKg")
        h.defaults.set(90.0, forKey: "profile.waistCm")
        try await h.weighIns.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: clock.instant(0))

        let readouts = await waistReadouts(h)
        XCTAssertEqual(readouts, [96.0, 96.0, 96.0, 96.0])
        XCTAssertEqual(h.provider.current(.waist, consumer: .estimate),
                       ResolvedBodyMeasurement(kind: .waist, value: 96.0, source: .labBook, day: clock.today))
    }

    /// Deleting the Lab Book reading moves every reader at once: to the older Apple Health weight,
    /// and to the earlier waist reading.
    func testAllReadersMoveTogetherWhenTheLabBookReadingIsDeleted() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: true)
        h.defaults.set(80.0, forKey: "profile.weightKg")
        h.defaults.set(90.0, forKey: "profile.waistCm")
        try await h.store.upsertAppleDaily([appleDaily(clock.day(-10), weightKg: 101.5)], deviceId: "apple-health")
        try await h.weighIns.save(weight: 100.0, waist: 97.0, unitSystem: .metric, takenAt: clock.instant(-7))
        let latest = try await h.weighIns.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: clock.instant(0))
        XCTAssertEqual(latest.map(\.markerKey), ["weight", "waist"])

        let weightBefore = await weightReadouts(h)
        let waistBefore = await waistReadouts(h)
        XCTAssertEqual(weightBefore, [99.2, 99.2, 99.2, 99.2])
        XCTAssertEqual(waistBefore, [96.0, 96.0, 96.0, 96.0])

        // Delete the newest weight: the reading of a week earlier takes over everywhere.
        try await h.weighIns.delete(latest[0])
        let weightAfterOne = await weightReadouts(h)
        XCTAssertEqual(weightAfterOne, [100.0, 100.0, 100.0, 100.0])

        // Delete that one too: the older Apple Health weight takes over everywhere, not the profile.
        let remaining = await h.weighIns.readings(.weight)
        XCTAssertEqual(remaining.count, 1)
        try await h.weighIns.delete(try XCTUnwrap(remaining.first))
        let weightAfterTwo = await weightReadouts(h)
        XCTAssertEqual(weightAfterTwo, [101.5, 101.5, 101.5, 101.5])
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.source, .appleHealth)

        // Delete the newest waist: the earlier waist reading takes over everywhere.
        try await h.weighIns.delete(latest[1])
        let waistAfter = await waistReadouts(h)
        XCTAssertEqual(waistAfter, [97.0, 97.0, 97.0, 97.0])
    }

    /// The Today view of a past day (Liquid and the redesign resolve for the SELECTED day) sees the
    /// reading that was current then, from the same list.
    func testResolvingAsOfAnEarlierDayIgnoresLaterReadings() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: true)
        h.defaults.set(80.0, forKey: "profile.weightKg")
        try await h.weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: clock.instant(-7))
        try await h.weighIns.save(weight: 99.2, waist: nil, unitSystem: .metric, takenAt: clock.instant(0))

        XCTAssertEqual(h.provider.resolve(.weight, asOf: clock.day(-8), consumer: .display)?.source, .profile)
        XCTAssertEqual(h.provider.resolve(.weight, asOf: clock.day(-7), consumer: .display)?.value, 100.0)
        XCTAssertEqual(h.provider.resolve(.weight, asOf: clock.day(-1), consumer: .display)?.value, 100.0)
        XCTAssertEqual(h.provider.resolve(.weight, asOf: clock.today, consumer: .display)?.value, 99.2)
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.value, 99.2)
    }

    /// §8.2 table: the Apple Health daily column and the Apple Health series are one source, merged
    /// per day with the daily column winning.
    func testAppleHealthDailyColumnWinsOverTheSeriesOnTheSameDay() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: true)
        try await h.store.upsertAppleDaily([appleDaily(clock.day(-5), weightKg: 100.0)], deviceId: "apple-health")
        try await h.store.upsertMetricSeries([MetricPoint(day: clock.day(-5), key: "weight", value: 99.0),
                                              MetricPoint(day: clock.day(-8), key: "weight", value: 101.0)],
                                             deviceId: "apple-health")
        await h.provider.refresh()

        let apple = h.provider.candidates(.weight).appleHealth.sorted { $0.day < $1.day }
        XCTAssertEqual(apple.map(\.day), [clock.day(-8), clock.day(-5)], "one value per day")
        XCTAssertEqual(apple.map(\.value), [101.0, 100.0], "the daily column wins its day")
        XCTAssertTrue(h.provider.candidates(.waist).appleHealth.isEmpty, "there is no Apple Health waist")
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.value, 100.0)
    }

    // MARK: - §8.5 the profile mirror

    /// With the flag on, after every write the two profile keys hold what the resolver returns for today.
    func testProfileMirrorEqualsResolverAfterSaveEditAndDelete() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: true)
        h.defaults.set(80.0, forKey: "profile.weightKg")
        h.defaults.set(90.0, forKey: "profile.waistCm")

        func assertMirror(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
            let weight = h.provider.current(.weight, consumer: .estimate)
            let waist = h.provider.current(.waist, consumer: .estimate)
            XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, weight?.value,
                           "weight mirror after \(step)", file: file, line: line)
            XCTAssertEqual(h.defaults.object(forKey: "profile.waistCm") as? Double, waist?.value,
                           "waist mirror after \(step)", file: file, line: line)
        }

        // Save.
        let earlier = try await h.weighIns.save(weight: 100.0, waist: 97.0, unitSystem: .metric, takenAt: clock.instant(-7))
        assertMirror("the first save")
        XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, 100.0)
        XCTAssertEqual(h.defaults.object(forKey: "profile.waistCm") as? Double, 97.0)

        let latest = try await h.weighIns.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: clock.instant(0))
        assertMirror("the second save")
        XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, 99.2)

        // Save in pounds and inches: the mirror holds kilograms and centimetres.
        let imperial = try await h.weighIns.save(weight: 218.0, waist: 37.5, unitSystem: .imperial,
                                                 takenAt: clock.instant(0).addingTimeInterval(600))
        assertMirror("an imperial save")
        XCTAssertEqual(try XCTUnwrap(h.defaults.object(forKey: "profile.weightKg") as? Double),
                       218.0 / UnitFormatter.poundsPerKilogram, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(h.defaults.object(forKey: "profile.waistCm") as? Double),
                       37.5 * UnitFormatter.centimetersPerInch, accuracy: 1e-9)
        try await h.weighIns.delete(imperial[0])
        try await h.weighIns.delete(imperial[1])
        assertMirror("deleting the imperial pair")
        XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, 99.2)

        // Edit the value.
        let edited = try await h.weighIns.edit(latest[0], value: 98.8, unitSystem: .metric, takenAt: clock.instant(0))
        assertMirror("a value edit")
        XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, 98.8)

        // Edit the date so that it is no longer the newest reading.
        let moved = try await h.weighIns.edit(edited, value: 98.8, unitSystem: .metric, takenAt: clock.instant(-14))
        assertMirror("a date edit")
        XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, 100.0,
                       "the reading of a week ago is the newest again")

        // Delete, down to no dated reading at all.
        try await h.weighIns.delete(earlier[0])
        assertMirror("a delete")
        XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, 98.8)
        try await h.weighIns.delete(moved)
        try await h.weighIns.delete(latest[1])
        try await h.weighIns.delete(earlier[1])
        assertMirror("deleting every reading")
        XCTAssertNil(h.provider.current(.weight, consumer: .estimate)?.day, "no dated reading is left")
    }

    /// Fault line F28, the flag-off equivalence of §12.5 at the provider: a Lab Book weigh-in in the
    /// store changes no reader and writes no profile value while the flag is off.
    func testMirrorIsNotWrittenWhileTheFlagIsOff() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: false)
        h.defaults.set(80.0, forKey: "profile.weightKg")
        h.defaults.set(90.0, forKey: "profile.waistCm")
        h.defaults.written = []
        let taken = Int(clock.instant(0).timeIntervalSince1970)
        try await h.store.upsertLabMarkers([labRow("weight", deviceId: "my-whoop", day: clock.today, takenAt: taken, value: 99.2),
                                            labRow("waist", deviceId: "my-whoop", day: clock.today, takenAt: taken, value: 96.0)])

        await h.provider.refresh()
        await h.provider.refresh()

        XCTAssertFalse(h.defaults.wroteProfile(), "the profile keys were written with the flag off: \(h.defaults.written)")
        XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, 80.0)
        XCTAssertEqual(h.defaults.object(forKey: "profile.waistCm") as? Double, 90.0)
        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate),
                       ResolvedBodyMeasurement(kind: .weight, value: 80.0, source: .profile, day: nil))
        XCTAssertEqual(h.provider.current(.weight, consumer: .display),
                       ResolvedBodyMeasurement(kind: .weight, value: 80.0, source: .profile, day: nil))
        XCTAssertEqual(h.provider.current(.waist, consumer: .estimate)?.value, 90.0)
    }

    /// The same with a profile that was never written: nothing appears under the keys, and the
    /// estimates keep the default of 75 they use today.
    func testAnUnsetProfileStaysUnsetWhileTheFlagIsOff() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: false)
        let taken = Int(clock.instant(0).timeIntervalSince1970)
        try await h.store.upsertLabMarkers([labRow("weight", deviceId: "my-whoop", day: clock.today, takenAt: taken, value: 99.2),
                                            labRow("waist", deviceId: "my-whoop", day: clock.today, takenAt: taken, value: 96.0)])
        await h.provider.refresh()

        XCTAssertNil(h.defaults.object(forKey: "profile.weightKg"))
        XCTAssertNil(h.defaults.object(forKey: "profile.waistCm"))
        XCTAssertFalse(h.defaults.wroteProfile())
        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate),
                       ResolvedBodyMeasurement(kind: .weight, value: 75.0, source: .profileDefault, day: nil))
        XCTAssertNil(h.provider.current(.waist, consumer: .estimate))
    }

    /// §12.5 at the provider, against today's behaviour: with the flag off the display value is the
    /// Apple Health one (else the profile) and the estimate value is the profile one, identically with
    /// and without a Lab Book weigh-in in the store.
    func testLabBookWeighInChangesNothingWhileTheFlagIsOff() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: false)
        h.defaults.set(80.0, forKey: "profile.weightKg")
        h.defaults.set(90.0, forKey: "profile.waistCm")
        h.defaults.written = []
        try await h.store.upsertAppleDaily([appleDaily(clock.day(-10), weightKg: 101.5)], deviceId: "apple-health")
        await h.provider.refresh()

        let displayBefore = h.provider.current(.weight, consumer: .display)
        let estimateBefore = h.provider.current(.weight, consumer: .estimate)
        let waistBefore = h.provider.current(.waist, consumer: .estimate)
        let seriesBefore = h.provider.series(.weight, consumer: .display)
        XCTAssertEqual(displayBefore, ResolvedBodyMeasurement(kind: .weight, value: 101.5, source: .appleHealth, day: clock.day(-10)),
                       "Today shows the Apple Health weight, as it does now")
        XCTAssertEqual(estimateBefore, ResolvedBodyMeasurement(kind: .weight, value: 80.0, source: .profile, day: nil),
                       "the estimates use the profile weight, as they do now")
        XCTAssertEqual(waistBefore?.value, 90.0)

        let taken = Int(clock.instant(0).timeIntervalSince1970)
        try await h.store.upsertLabMarkers([labRow("weight", deviceId: "my-whoop", day: clock.today, takenAt: taken, value: 99.2),
                                            labRow("waist", deviceId: "my-whoop", day: clock.today, takenAt: taken, value: 96.0)])
        await h.provider.refresh()

        XCTAssertEqual(h.provider.current(.weight, consumer: .display), displayBefore)
        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate), estimateBefore)
        XCTAssertEqual(h.provider.current(.waist, consumer: .estimate), waistBefore)
        XCTAssertEqual(h.provider.current(.waist, consumer: .display), waistBefore)
        XCTAssertEqual(h.provider.series(.weight, consumer: .display), seriesBefore)
        XCTAssertTrue(h.provider.series(.weight, consumer: .estimate).isEmpty)
        XCTAssertTrue(h.provider.series(.waist, consumer: .display).isEmpty)
        XCTAssertFalse(h.defaults.wroteProfile())
    }

    /// "If it differs": a refresh that resolves the value the profile already holds writes nothing.
    func testMirrorIsNotRewrittenWhenItAlreadyEqualsTheResolver() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: true)
        try await h.weighIns.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: clock.instant(0))
        XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, 99.2)

        h.defaults.written = []
        await h.provider.refresh()
        await h.provider.refresh()
        XCTAssertFalse(h.defaults.wroteProfile(), "an unchanged value was written again: \(h.defaults.written)")
    }

    /// With the flag on and no dated reading the resolved value IS the profile value. There is
    /// nothing to mirror, and an unset profile must not be turned into a written 75.
    func testMirrorIsNotWrittenWhenTheResolvedValueIsTheProfileItself() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: true)
        await h.provider.refresh()
        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate)?.source, .profileDefault)
        XCTAssertNil(h.defaults.object(forKey: "profile.weightKg"), "the default of 75 must not be written as the owner's weight")
        XCTAssertNil(h.defaults.object(forKey: "profile.waistCm"))
        XCTAssertFalse(h.defaults.wroteProfile())

        h.defaults.set(80.0, forKey: "profile.weightKg")
        h.defaults.written = []
        await h.provider.refresh()
        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate),
                       ResolvedBodyMeasurement(kind: .weight, value: 80.0, source: .profile, day: nil))
        XCTAssertFalse(h.defaults.wroteProfile())
    }

    /// A reading dated after today is not today's value and is not mirrored.
    func testAReadingDatedAfterTodayIsNotMirrored() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: true)
        h.defaults.set(80.0, forKey: "profile.weightKg")
        h.defaults.written = []
        let taken = Int(clock.instant(1).timeIntervalSince1970)
        try await h.store.upsertLabMarkers([labRow("weight", deviceId: "my-whoop", day: clock.day(1), takenAt: taken, value: 60.0)])
        await h.provider.refresh()

        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate)?.value, 80.0)
        XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, 80.0)
        XCTAssertFalse(h.defaults.wroteProfile())
    }

    /// §8.5: "If the flag is switched off, the legacy policies fall back to a profile value that is
    /// the last weigh-in, not a stale figure."
    func testSwitchingTheFlagOffFallsBackToTheMirroredWeighIn() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: true)
        h.defaults.set(80.0, forKey: "profile.weightKg")
        try await h.weighIns.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: clock.instant(0))

        h.defaults.set(false, forKey: "noop.cutScorecardEnabled")
        h.defaults.written = []
        await h.provider.refresh()

        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate),
                       ResolvedBodyMeasurement(kind: .weight, value: 99.2, source: .profile, day: nil))
        XCTAssertEqual(h.provider.current(.waist, consumer: .estimate),
                       ResolvedBodyMeasurement(kind: .waist, value: 96.0, source: .profile, day: nil))
        XCTAssertFalse(h.defaults.wroteProfile(), "switching the flag off writes nothing")
    }

    /// §8.5: "The mirror has one writer." A `WeighInStore` with no provider writes the Lab Book rows
    /// and no profile value, in the injected defaults or in the standard ones.
    ///
    /// No provider exists while the store writes. Under ruling R32 a flag-on provider follows every
    /// completed refresh of its repository and mirrors, so one kept alive on this repository (as the
    /// shared harness keeps one) would write the profile during the store's own refresh and the
    /// test could not tell the two writers apart.
    func testWeighInStoreByItselfNeverWritesTheProfile() async throws {
        let clock = Clock()
        let name = "BodyMeasurementSingleSourceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: name))
        suites.append(name)
        defaults.set(true, forKey: "noop.cutScorecardEnabled")
        defaults.set(80.0, forKey: "profile.weightKg")
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        defaults.written = []
        let standardWeight = UserDefaults.standard.object(forKey: "profile.weightKg") as? Double
        let standardWaist = UserDefaults.standard.object(forKey: "profile.waistCm") as? Double
        let now = clock.now
        let zone = utc
        let alone = WeighInStore(repository: repo, provider: nil, timeZone: { zone }, now: { now })

        let rows = try await alone.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: clock.instant(0))
        try await alone.edit(rows[0], value: 98.8, unitSystem: .metric, takenAt: clock.instant(0))
        try await alone.delete(rows[1])

        XCTAssertFalse(defaults.wroteProfile(), "the write funnel wrote the profile itself: \(defaults.written)")
        XCTAssertEqual(defaults.object(forKey: "profile.weightKg") as? Double, 80.0)
        XCTAssertNil(defaults.object(forKey: "profile.waistCm"))
        XCTAssertEqual(UserDefaults.standard.object(forKey: "profile.weightKg") as? Double, standardWeight,
                       "the app's real profile was touched")
        XCTAssertEqual(UserDefaults.standard.object(forKey: "profile.waistCm") as? Double, standardWaist)

        // The provider, once there is one and it refreshes, is the one that mirrors.
        let today = clock.today
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        await provider.refresh()
        XCTAssertEqual(defaults.object(forKey: "profile.weightKg") as? Double, 98.8)
    }

    /// The provider under test never touches the standard defaults either.
    func testTheProviderWritesOnlyTheInjectedDefaults() async throws {
        let clock = Clock()
        let standardWeight = UserDefaults.standard.object(forKey: "profile.weightKg") as? Double
        let standardWaist = UserDefaults.standard.object(forKey: "profile.waistCm") as? Double
        let h = try await makeHarness(today: clock.today, now: clock.now, flag: true)
        try await h.weighIns.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: clock.instant(0))
        XCTAssertEqual(h.defaults.object(forKey: "profile.weightKg") as? Double, 99.2)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "profile.weightKg") as? Double, standardWeight)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "profile.waistCm") as? Double, standardWaist)
    }

    // MARK: - Ruling R25

    // Wednesdays at 07:00 UTC, as specification §13.1.
    private let week1 = 1_925_622_000   // 2031-01-08
    private let week2 = 1_926_226_800   // 2031-01-15
    private let week3 = 1_926_831_600   // 2031-01-22

    private func register(_ store: WhoopStore, _ id: String, brand: String = "WHOOP", status: DeviceStatus) throws {
        try DeviceRegistryStore(dbQueue: store.registryWriter).add(
            PairedDevice(id: id, brand: brand, model: "4.0", sourceKind: .liveBLE, capabilities: [.hr],
                         status: status, addedAt: 1, lastSeenAt: 1))
    }

    /// The owner's decision: re-point the active id and every earlier reading is still returned, by
    /// the series the weekly points are built from, by the resolver, and so by the scorecard. Nothing
    /// is moved: the row count under each id is the same before and after.
    func testReadingsUnderEarlierStrapIdsStillFeedTheSeriesResolverAndWeeklyPoints() async throws {
        let now = Date(timeIntervalSince1970: Double(week3 + 3_600))
        let h = try await makeHarness(today: "2031-01-22", now: now, flag: true)
        try register(h.store, "whoop-old", status: .archived)
        try register(h.store, "whoop-new", status: .active)

        // Week 1 under the canonical id, week 2 under a re-added strap, week 3 under the next one,
        // each written by the weigh-in flow while that id was the active one.
        try await h.weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric,
                                  takenAt: Date(timeIntervalSince1970: Double(week1)))
        h.repo.adoptActiveDeviceId("whoop-old")
        try await h.weighIns.save(weight: 99.2, waist: 99.5, unitSystem: .metric,
                                  takenAt: Date(timeIntervalSince1970: Double(week2)))
        h.repo.adoptActiveDeviceId("whoop-new")
        try await h.weighIns.save(weight: 98.4, waist: 99.0, unitSystem: .metric,
                                  takenAt: Date(timeIntervalSince1970: Double(week3)))

        let ids = ["my-whoop", "whoop-old", "whoop-new"]
        for id in ids {
            let count = try await bodyRowCount(h.store, id)
            XCTAssertEqual(count, 2, "each id holds the weight and the waist written while it was active: \(id)")
        }

        await h.provider.refresh()
        let weights = h.provider.series(.weight, consumer: .display)
        XCTAssertEqual(weights.map(\.day), ["2031-01-08", "2031-01-15", "2031-01-22"])
        XCTAssertEqual(weights.map(\.value), [100.0, 99.2, 98.4])
        XCTAssertEqual(h.provider.series(.waist, consumer: .display).map(\.value), [100.0, 99.5, 99.0])
        XCTAssertEqual(h.provider.candidates(.weight).labBook.map(\.deviceId).sorted(), ids.sorted(),
                       "each candidate still carries the id it is stored under")

        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate)?.value, 98.4)
        XCTAssertEqual(h.provider.resolve(.weight, asOf: "2031-01-21", consumer: .display)?.value, 99.2,
                       "a reading under an earlier id resolves like any other")
        XCTAssertEqual(h.provider.resolve(.weight, asOf: "2031-01-14", consumer: .display)?.value, 100.0)
        XCTAssertEqual(h.provider.resolve(.waist, asOf: "2031-01-14", consumer: .estimate)?.value, 100.0)

        let result = CutScorecard.evaluate(await h.builder.build(today: "2031-01-22"))
        XCTAssertEqual(result.weeks.map(\.weekStart), ["2031-01-06", "2031-01-13", "2031-01-20"])
        XCTAssertEqual(result.weeks.map(\.weightKg), [100.0, 99.2, 98.4])
        XCTAssertEqual(result.weeks.map(\.waistCm), [100.0, 99.5, 99.0])
        XCTAssertEqual(result.currentWeightKg, 98.4)

        for id in ids {
            let count = try await bodyRowCount(h.store, id)
            XCTAssertEqual(count, 2, "reading across ids moved or removed a row under \(id)")
        }
        let weightOld = try await h.store.labMarkers(deviceId: "whoop-old", markerKey: "weight")
        XCTAssertEqual(weightOld.map(\.takenAt), [week2], "nothing was re-keyed to the active id")
    }

    /// The same reading under two ids (same marker, instant, source and value) is one reading, and
    /// the active id's copy is the one used. Both rows stay in the database. Superseded by ruling R42
    /// and labbook-ownership.md §7.1 where this test held two DIFFERENT values at one instant: those
    /// are two readings, both reach the resolver, and its same-day rule (the greatest instant, then
    /// the greatest id) chooses between them.
    func testDuplicateAcrossStrapIdsIsCountedOnceWithTheActiveCopy() async throws {
        let now = Date(timeIntervalSince1970: Double(week3 + 3_600))
        let h = try await makeHarness(today: "2031-01-22", now: now, flag: true, deviceId: "whoop-new")
        try register(h.store, "whoop-new", status: .active)
        try await h.store.upsertLabMarkers([
            labRow("weight", deviceId: "my-whoop", day: "2031-01-08", takenAt: week1, value: 100.0, suffix: "CCCCCCCC"),
            labRow("weight", deviceId: "whoop-new", day: "2031-01-08", takenAt: week1, value: 100.0, suffix: "AAAAAAAA"),
            // Not a duplicate: another instant under the canonical id.
            labRow("weight", deviceId: "my-whoop", day: "2031-01-15", takenAt: week2, value: 99.2),
        ])
        await h.provider.refresh()

        let series = h.provider.series(.weight, consumer: .display)
        XCTAssertEqual(series.map(\.value), [100.0, 99.2])
        XCTAssertEqual(series.first?.rowId, "weight-\(week1)-AAAAAAAA", "the active id's copy stands, though its id sorts lower")
        XCTAssertEqual(h.provider.candidates(.weight).labBook.count, 2, "the duplicate is collapsed before the resolver sees it")
        XCTAssertEqual(h.provider.resolve(.weight, asOf: "2031-01-08", consumer: .estimate)?.value, 100.0)

        let canonical = try await bodyRowCount(h.store, "my-whoop")
        let active = try await bodyRowCount(h.store, "whoop-new")
        XCTAssertEqual(canonical, 2, "the copy that is not listed is not deleted")
        XCTAssertEqual(active, 1)

        // The data this test held before ruling R42: different values at one instant under two ids.
        let h2 = try await makeHarness(today: "2031-01-22", now: now, flag: true, deviceId: "whoop-new")
        try register(h2.store, "whoop-new", status: .active)
        try await h2.store.upsertLabMarkers([
            labRow("weight", deviceId: "my-whoop", day: "2031-01-08", takenAt: week1, value: 100.4, suffix: "CCCCCCCC"),
            labRow("weight", deviceId: "whoop-new", day: "2031-01-08", takenAt: week1, value: 100.0, suffix: "AAAAAAAA"),
            labRow("weight", deviceId: "my-whoop", day: "2031-01-15", takenAt: week2, value: 99.2),
        ])
        await h2.provider.refresh()

        XCTAssertEqual(h2.provider.candidates(.weight).labBook.count, 3, "neither reading is hidden from the resolver")
        let series2 = h2.provider.series(.weight, consumer: .display)
        XCTAssertEqual(series2.map(\.value), [100.4, 99.2], "one point per day: the same instant, then the greatest id")
        XCTAssertEqual(series2.first?.rowId, "weight-\(week1)-CCCCCCCC")
        XCTAssertEqual(h2.provider.resolve(.weight, asOf: "2031-01-08", consumer: .estimate)?.value, 100.4)
        let listed = await h2.weighIns.readings(.weight)
        XCTAssertEqual(listed.map(\.value), [100.0, 100.4, 99.2], "the history lists both readings of 2031-01-08")
    }

    /// Two readouts of one fact: the rows the history list is built from and the rows the resolver is
    /// fed are the same rows, across ids.
    func testProviderAndWeighInStoreListTheSameLabBookRows() async throws {
        let now = Date(timeIntervalSince1970: Double(week3 + 3_600))
        let h = try await makeHarness(today: "2031-01-22", now: now, flag: true, deviceId: "whoop-new")
        try register(h.store, "whoop-old", status: .archived)
        try register(h.store, "whoop-new", status: .active)
        try await h.store.upsertLabMarkers([
            labRow("weight", deviceId: "my-whoop", day: "2031-01-08", takenAt: week1, value: 100.0),
            labRow("weight", deviceId: "whoop-old", day: "2031-01-15", takenAt: week2, value: 99.2),
            labRow("weight", deviceId: "whoop-new", day: "2031-01-22", takenAt: week3, value: 98.4),
            labRow("weight", deviceId: "whoop-new", day: "2031-01-08", takenAt: week1, value: 100.1, suffix: "DDDDDDDD"),
            labRow("waist", deviceId: "whoop-old", day: "2031-01-15", takenAt: week2, value: 99.5),
        ])
        await h.provider.refresh()

        // Ruling R42 and labbook-ownership.md §7.1: the two weights of 2031-01-08 differ in value, so
        // they are two readings and both are listed and fed (four weights; before R42, three).
        for (kind, expected) in [(BodyMeasurementKind.weight, 4), (BodyMeasurementKind.waist, 1)] {
            let listed = await h.weighIns.readings(kind)
            let fed = h.provider.candidates(kind).labBook
            XCTAssertEqual(listed.count, expected)
            XCTAssertEqual(listed.map(\.id).sorted(), fed.map(\.id).sorted())
            XCTAssertEqual(listed.sorted { $0.id < $1.id }, fed.sorted { $0.id < $1.id })
        }
    }
}
