import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard), specification §6.3, §7.1 item 7, §7.5 item 2, §8.1, §8.6 item 2
// and §12.3. Written before the implementation exists, from the specification.
//
// API ASSUMED BY THESE TESTS
//
//     @MainActor struct CutScorecardInputBuilder {
//         init(repository: Repository, provider: BodyMeasurementProvider, settings: CutScorecardSettings,
//              timeZone: @escaping () -> TimeZone = { TimeZone.current })
//         /// Everything `CutScorecard.evaluate` reads, for `today`.
//         func build(today: String) async -> CutScorecardInput
//     }
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `weights` and `waists` are `provider.series(kind, consumer: .display)`, one reading per element:
//     the element's `day` and `value`, and its `takenAt` when it has one. (What `takenAt` an Apple
//     Health element receives is not asserted.) The builder does not read Lab Book or Apple Health
//     by itself. It uses the provider's current snapshot, which every `WeighInStore` write refreshes.
//  2. `lifts` come from the lift sessions stored under `repository.deviceId` (in-app) and under
//     `PersonalLiftingImport.deviceId` (imported), as `LiftLogView.swift:391-392` lists them. A set
//     becomes an observation when it is not a warm-up, was performed (`LiftMetrics.isPerformed`),
//     and has a weight above zero. The observation's `day` is the local day of the SESSION's
//     `startTs` in `timeZone()`. Either one observation per set or one per exercise per day is
//     accepted: the tests compare the heaviest weight per exercise per day, which is all the pure
//     function reads.
//  3. `proteinDays` are the `protein_g` series under `nutrition-csv`, one entry per stored day.
//  4. `phase` is `settings.evaluationPhase(on: today)`, `parameters` is `settings.parameters`, and
//     `today` is passed through unchanged.
//  5. Whether the builder windows its store reads on `today` or on the real clock is not asserted.
//     Every row in these tests is dated within the two weeks before a `today` that is two days
//     behind the real clock, so either choice passes.
//
// `BodyMeasurementProvider`, `WeighInStore` and `CutScorecardSettings` are used as assumed at the top
// of `BodyMeasurementSingleSourceTests.swift`, `WeighInStoreTests.swift` and
// `CutScorecardSettingsTests.swift`.
//
// Synthetic values only: the "Fixture Person" of specification §13.
@MainActor
final class CutScorecardInputBuilderTests: XCTestCase {

    // MARK: - Harness

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
        /// `hour`:`minute` UTC on `day(offset)`, as epoch seconds.
        func epoch(_ offset: Int, hour: Int = 7, minute: Int = 0) -> Int {
            Int(start.timeIntervalSince1970) + offset * 86_400 + hour * 3_600 + minute * 60
        }
        func instant(_ offset: Int) -> Date { Date(timeIntervalSince1970: Double(epoch(offset))) }
    }

    private struct Harness {
        let store: WhoopStore
        let repo: Repository
        let defaults: UserDefaults
        let provider: BodyMeasurementProvider
        let weighIns: WeighInStore
        let settings: CutScorecardSettings
        let builder: CutScorecardInputBuilder
    }

    private var suites: [String] = []
    private let utc = TimeZone(identifier: "UTC")!

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func makeHarness(_ clock: Clock, zone: TimeZone? = nil) async throws -> Harness {
        let name = "CutScorecardInputBuilderTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        defaults.set(true, forKey: "noop.cutScorecardEnabled")
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let today = clock.today
        let now = clock.now
        let utcZone = utc
        let builderZone = zone ?? utc
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        let weighIns = WeighInStore(repository: repo, provider: provider, timeZone: { utcZone }, now: { now })
        let settings = CutScorecardSettings(defaults: defaults)
        let builder = CutScorecardInputBuilder(repository: repo, provider: provider, settings: settings,
                                               intake: IntakeProvider(repository: repo, settings: IntakeSettings(defaults: defaults)),
                                               timeZone: { builderZone })
        return Harness(store: store, repo: repo, defaults: defaults, provider: provider, weighIns: weighIns,
                       settings: settings, builder: builder)
    }

    /// One session with its sets, stored through the existing lift store calls.
    private func addSession(_ store: WhoopStore, deviceId: String, startTs: Int,
                            sets: [(exercise: String, weightKg: Double?, reps: Int?, isWarmup: Bool)]) async throws {
        let id = deviceId == PersonalLiftingImport.deviceId ? "lift-import:\(startTs)" : "session-\(startTs)"
        try await store.upsertLiftSessions([LiftSessionRow(id: id, deviceId: deviceId, startTs: startTs,
                                                           endTs: startTs + 3_600, sport: "Strength Training",
                                                           programId: nil, programName: "Fixture session",
                                                           sessionRpe: nil, note: nil)])
        let rows = sets.enumerated().map { index, set in
            LiftSetRow(id: "\(id):\(index)", deviceId: deviceId, sessionId: id, ord: index, exercise: set.exercise,
                       primaryMuscle: nil, setIndex: index + 1, weightKg: set.weightKg, reps: set.reps, rpe: nil,
                       isWarmup: set.isWarmup, startTs: nil, endTs: nil, restSec: nil, note: nil)
        }
        try await store.upsertLiftSets(rows)
    }

    /// The heaviest weight per day and exercise: what §7.5 item 2 reads from the observations.
    private func heaviest(_ lifts: [CutScorecardLiftObservation]) -> [String: Double] {
        var out: [String: Double] = [:]
        for lift in lifts {
            let key = "\(lift.day) \(lift.exercise)"
            out[key] = max(out[key] ?? -Double.infinity, lift.weightKg)
        }
        return out
    }

    // MARK: - Weights and waists

    /// The weekly points are built from the SAME series the resolver reads (§8.1): Lab Book and
    /// Apple Health readings, one per day, in kilograms and centimetres.
    func testWeightsComeFromTheResolverSeries() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        try await h.store.upsertAppleDaily([AppleDaily(day: clock.day(-10), steps: nil, activeKcal: nil, basalKcal: nil,
                                                       vo2max: nil, avgHr: nil, maxHr: nil, walkingHr: nil,
                                                       weightKg: 101.5)], deviceId: "apple-health")
        try await h.weighIns.save(weight: 100.0, waist: 97.0, unitSystem: .metric, takenAt: clock.instant(-7))
        // Entered in pounds and inches: the function receives kilograms and centimetres.
        try await h.weighIns.save(weight: 218.0, waist: 37.5, unitSystem: .imperial, takenAt: clock.instant(0))

        let input = await h.builder.build(today: clock.today)

        let weightSeries = h.provider.series(.weight, consumer: .display)
        let waistSeries = h.provider.series(.waist, consumer: .display)
        XCTAssertEqual(weightSeries.count, 3)
        XCTAssertEqual(waistSeries.count, 2)

        let weights = input.weights.sorted { $0.day < $1.day }
        XCTAssertEqual(weights.map(\.day), weightSeries.map(\.day))
        XCTAssertEqual(weights.map(\.value), weightSeries.map(\.value), "the very values the resolver holds, unrounded")
        XCTAssertEqual(weights.map(\.day), [clock.day(-10), clock.day(-7), clock.today])
        XCTAssertEqual(weights[0].value, 101.5, "the Apple Health reading is a point like any other")
        XCTAssertEqual(weights[1].value, 100.0)
        XCTAssertEqual(weights[2].value, 218.0 / UnitFormatter.poundsPerKilogram, accuracy: 1e-9)
        XCTAssertEqual(weights[1].takenAt, clock.epoch(-7), "a Lab Book reading keeps its instant")
        XCTAssertEqual(weights[2].takenAt, clock.epoch(0))

        let waists = input.waists.sorted { $0.day < $1.day }
        XCTAssertEqual(waists.map(\.day), waistSeries.map(\.day))
        XCTAssertEqual(waists.map(\.value), waistSeries.map(\.value))
        XCTAssertEqual(waists[0].value, 97.0)
        XCTAssertEqual(waists[1].value, 37.5 * UnitFormatter.centimetersPerInch, accuracy: 1e-9)
        XCTAssertEqual(waists.map(\.takenAt), [clock.epoch(-7), clock.epoch(0)])
    }

    /// The single-source assertion of §8.6 item 2 for the builder: for the same data and the same
    /// day, `CutScorecardResult.currentWeightKg` IS the resolver's current weight — after a save,
    /// after an edit and after a delete.
    func testScorecardCurrentWeightEqualsTheResolverForTheSameDataAndDay() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        h.defaults.set(80.0, forKey: "profile.weightKg")

        func assertAgreement(_ step: String, file: StaticString = #filePath, line: UInt = #line) async {
            let result = CutScorecard.evaluate(await h.builder.build(today: clock.today))
            let resolved = h.provider.current(.weight, consumer: .display)
            if resolved?.day != nil {
                XCTAssertEqual(result.currentWeightKg, resolved?.value, "after \(step)", file: file, line: line)
                XCTAssertEqual(result.currentWeightDay, resolved?.day, "after \(step)", file: file, line: line)
            } else {
                XCTAssertNil(result.currentWeightKg,
                             "after \(step): the undated profile value is not a weigh-in and never a scorecard point",
                             file: file, line: line)
            }
            // As of an earlier day the two agree as well.
            let earlier = clock.day(-3)
            let earlierResult = CutScorecard.evaluate(await h.builder.build(today: earlier))
            let earlierResolved = h.provider.resolve(.weight, asOf: earlier, consumer: .display)
            XCTAssertEqual(earlierResult.currentWeightKg, earlierResolved?.day == nil ? nil : earlierResolved?.value,
                           "as of \(earlier) after \(step)", file: file, line: line)
        }

        await assertAgreement("nothing stored")

        let first = try await h.weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: clock.instant(-7))
        await assertAgreement("the first save")
        let second = try await h.weighIns.save(weight: 99.2, waist: nil, unitSystem: .metric, takenAt: clock.instant(0))
        await assertAgreement("the second save")
        let firstResult = CutScorecard.evaluate(await h.builder.build(today: clock.today))
        XCTAssertEqual(firstResult.currentWeightKg, 99.2)

        // A second reading on the same day: the later one is the day's reading for both.
        let sameDay = try await h.weighIns.save(weight: 99.0, waist: nil, unitSystem: .metric,
                                                takenAt: clock.instant(0).addingTimeInterval(1_800))
        await assertAgreement("a second reading on the same day")
        let sameDayResult = CutScorecard.evaluate(await h.builder.build(today: clock.today))
        XCTAssertEqual(sameDayResult.currentWeightKg, 99.0)

        try await h.weighIns.edit(sameDay[0], value: 98.7, unitSystem: .metric,
                                  takenAt: clock.instant(0).addingTimeInterval(1_800))
        await assertAgreement("a value edit")

        try await h.weighIns.delete(sameDay[0])
        await assertAgreement("deleting the later reading")
        try await h.weighIns.delete(second[0])
        await assertAgreement("deleting the newest reading")
        let afterDelete = CutScorecard.evaluate(await h.builder.build(today: clock.today))
        XCTAssertEqual(afterDelete.currentWeightKg, 100.0, "the scorecard moved back with the resolver")

        try await h.weighIns.delete(first[0])
        await assertAgreement("deleting every reading")
    }

    /// The nutrition CSV's own `weight` series (unit unrecorded) is not a weigh-in.
    func testNutritionCsvWeightNeverFeedsTheWeights() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        try await h.store.upsertMetricSeries([MetricPoint(day: clock.day(-1), key: "weight", value: 215.0),
                                              MetricPoint(day: clock.day(-1), key: "protein_g", value: 120.0)],
                                             deviceId: "nutrition-csv")
        await h.provider.refresh()

        let input = await h.builder.build(today: clock.today)
        XCTAssertTrue(input.weights.isEmpty)
        XCTAssertEqual(input.proteinDays, [CutScorecardProteinDay(day: clock.day(-1), grams: 120.0)])
        XCTAssertNil(CutScorecard.evaluate(input).currentWeightKg)
    }

    // MARK: - Lifts

    func testWarmUpAndUnperformedSetsAreExcluded() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        try await addSession(h.store, deviceId: "my-whoop", startTs: clock.epoch(-2, hour: 18), sets: [
            (exercise: "Fixture Press", weightKg: 40.0, reps: 10, isWarmup: true),
            (exercise: "Fixture Press", weightKg: 60.0, reps: 5, isWarmup: false),
            // Heavier than the working set, and not performed: a set the owner discarded to zero.
            (exercise: "Fixture Press", weightKg: 62.5, reps: 0, isWarmup: false),
            // Heavier still, and a warm-up by the owner's own mark.
            (exercise: "Fixture Press", weightKg: 70.0, reps: 1, isWarmup: true),
            // Done, the rep count not typed: it counts (LiftMetrics.isPerformed).
            (exercise: "Fixture Row", weightKg: 50.0, reps: nil, isWarmup: false),
            // An exercise with nothing but a warm-up and an unperformed set contributes nothing.
            (exercise: "Fixture Curl", weightKg: 20.0, reps: 12, isWarmup: true),
            (exercise: "Fixture Curl", weightKg: 22.5, reps: 0, isWarmup: false),
        ])

        let input = await h.builder.build(today: clock.today)

        XCTAssertEqual(heaviest(input.lifts), ["\(clock.day(-2)) Fixture Press": 60.0,
                                               "\(clock.day(-2)) Fixture Row": 50.0])
        XCTAssertFalse(input.lifts.contains { $0.exercise == "Fixture Curl" })
        XCTAssertFalse(input.lifts.contains { $0.weightKg == 40.0 || $0.weightKg == 62.5 || $0.weightKg == 70.0 })
    }

    /// A set with no weight, or a bodyweight set stored as zero, has no load to compare. It is left
    /// out by the builder, not passed on to be counted as a rejected reading.
    func testSetsWithoutAUsableWeightAreExcluded() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        try await addSession(h.store, deviceId: "my-whoop", startTs: clock.epoch(-2, hour: 18), sets: [
            (exercise: "Fixture Pull-up", weightKg: nil, reps: 8, isWarmup: false),
            (exercise: "Fixture Dip", weightKg: 0, reps: 10, isWarmup: false),
            (exercise: "Fixture Press", weightKg: 60.0, reps: 5, isWarmup: false),
        ])

        let input = await h.builder.build(today: clock.today)

        XCTAssertEqual(heaviest(input.lifts), ["\(clock.day(-2)) Fixture Press": 60.0])
        let rejections = CutScorecard.evaluate(input).rejections
        XCTAssertEqual(rejections.nonPositive, 0, "the builder must not hand the function a load of zero")
        XCTAssertEqual(rejections.nonFinite, 0)
    }

    func testImportedAndInAppSessionsBothFeedLifts() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        // In-app, under the active strap id.
        try await addSession(h.store, deviceId: "my-whoop", startTs: clock.epoch(-2, hour: 18), sets: [
            (exercise: "Fixture Press", weightKg: 62.5, reps: 5, isWarmup: false),
        ])
        // Imported (pasted text or CSV), under the `lifting` id.
        try await addSession(h.store, deviceId: PersonalLiftingImport.deviceId, startTs: clock.epoch(-9, hour: 18), sets: [
            (exercise: "Fixture Press", weightKg: 60.0, reps: 5, isWarmup: false),
            (exercise: "Fixture Row", weightKg: 50.0, reps: 8, isWarmup: false),
        ])
        try await addSession(h.store, deviceId: PersonalLiftingImport.deviceId, startTs: clock.epoch(-3, hour: 18), sets: [
            (exercise: "Fixture Row", weightKg: 52.5, reps: 8, isWarmup: false),
        ])
        // A session under an id that is neither: not a lift source.
        try await addSession(h.store, deviceId: "apple-health", startTs: clock.epoch(-4, hour: 18), sets: [
            (exercise: "Fixture Press", weightKg: 200.0, reps: 1, isWarmup: false),
        ])

        let input = await h.builder.build(today: clock.today)

        XCTAssertEqual(heaviest(input.lifts), ["\(clock.day(-2)) Fixture Press": 62.5,
                                               "\(clock.day(-9)) Fixture Press": 60.0,
                                               "\(clock.day(-9)) Fixture Row": 50.0,
                                               "\(clock.day(-3)) Fixture Row": 52.5])
        XCTAssertFalse(input.lifts.contains { $0.weightKg == 200.0 })
    }

    /// No sessions: an empty list, so the lift signal reads "no lift data" and never "holding".
    func testNoSessionsYieldsEmptyLifts() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        try await h.weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: clock.instant(0))

        let input = await h.builder.build(today: clock.today)

        XCTAssertTrue(input.lifts.isEmpty)
        let result = CutScorecard.evaluate(input)
        XCTAssertEqual(result.signals.lifts.state, .unknown)
        XCTAssertEqual(result.signals.lifts.reason, .noLiftData)
    }

    /// The observation's day is the local day the session STARTED on, in the zone given to the builder.
    func testLiftDayIsTheLocalDayTheSessionStartedOn() async throws {
        let clock = Clock()
        // 23:30 UTC four days back: still that day in UTC, already the next day in Kolkata.
        let start = clock.epoch(-4, hour: 23, minute: 30)
        let sets: [(exercise: String, weightKg: Double?, reps: Int?, isWarmup: Bool)] =
            [(exercise: "Fixture Press", weightKg: 60.0, reps: 5, isWarmup: false)]

        let inUTC = try await makeHarness(clock)
        try await addSession(inUTC.store, deviceId: "my-whoop", startTs: start, sets: sets)
        let utcInput = await inUTC.builder.build(today: clock.today)
        XCTAssertEqual(Set(utcInput.lifts.map(\.day)), [clock.day(-4)])

        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let inKolkata = try await makeHarness(clock, zone: kolkata)
        try await addSession(inKolkata.store, deviceId: "my-whoop", startTs: start, sets: sets)
        let kolkataInput = await inKolkata.builder.build(today: clock.today)
        XCTAssertEqual(Set(kolkataInput.lifts.map(\.day)), [clock.day(-3)])
        XCTAssertEqual(kolkataInput.lifts.first?.exercise, "Fixture Press", "the name is passed as stored")
    }

    /// Exercise names reach the function as stored: no trimming and no case folding (§6.3, R24).
    func testExerciseNamesArePassedAsStored() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        try await addSession(h.store, deviceId: "my-whoop", startTs: clock.epoch(-2, hour: 18), sets: [
            (exercise: "Fixture Press", weightKg: 60.0, reps: 5, isWarmup: false),
            (exercise: "fixture press", weightKg: 55.0, reps: 5, isWarmup: false),
            (exercise: "Fixture Press ", weightKg: 50.0, reps: 5, isWarmup: false),
        ])

        let input = await h.builder.build(today: clock.today)

        XCTAssertEqual(Set(input.lifts.map(\.exercise)), ["Fixture Press", "fixture press", "Fixture Press "])
    }

    // MARK: - Protein

    func testProteinDaysComeFromTheNutritionSeries() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        // Seven days before the weigh-in, as specification §13.2 week 6: three logged, four not.
        try await h.store.upsertMetricSeries([
            MetricPoint(day: clock.day(-7), key: "protein_g", value: 120.0),
            MetricPoint(day: clock.day(-5), key: "protein_g", value: 80.0),
            MetricPoint(day: clock.day(-2), key: "protein_g", value: 120.5),
            // Other keys of the same import are not protein.
            MetricPoint(day: clock.day(-2), key: "calories_in", value: 2_400.0),
            MetricPoint(day: clock.day(-4), key: "carbs_g", value: 300.0),
            MetricPoint(day: clock.day(-4), key: "fat_g", value: 70.0),
        ], deviceId: "nutrition-csv")
        // The same key under another source is not the nutrition series.
        try await h.store.upsertMetricSeries([MetricPoint(day: clock.day(-3), key: "protein_g", value: 999.0)],
                                             deviceId: "apple-health")

        let input = await h.builder.build(today: clock.today)

        XCTAssertEqual(input.proteinDays.sorted { $0.day < $1.day },
                       [CutScorecardProteinDay(day: clock.day(-7), grams: 120.0),
                        CutScorecardProteinDay(day: clock.day(-5), grams: 80.0),
                        CutScorecardProteinDay(day: clock.day(-2), grams: 120.5)],
                       "one entry per logged day; an unlogged day has no entry and is never a zero")
        XCTAssertEqual(Set(input.proteinDays.map(\.day)).count, input.proteinDays.count, "one per day")
    }

    func testNoNutritionSeriesYieldsNoProteinDays() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        let input = await h.builder.build(today: clock.today)
        XCTAssertTrue(input.proteinDays.isEmpty)
    }

    // MARK: - Phase, rules and today

    func testActiveCutPhaseStoredRulesAndTodayArePassedThrough() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        let cut = CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: clock.day(-14),
                                          targetWeightKg: 94.0, rateLowPercentPerWeek: 0.4,
                                          rateHighPercentPerWeek: 1.2)
        let parameters = CutScorecardParameters(
            rateWindowWeeks: 4, waistWindowWeeks: 2, waistMinDecreaseCm: 0.5, liftDropTolerancePercent: 5,
            liftDropShare: 0.5, liftDropConsecutiveWeeks: 3, addCaloriesKcal: 300,
            slowLossThresholdKgPerWeek: 0.4, slowLossConsecutiveWeeks: 3, reduceCarbsKcal: 250,
            proteinFloorGrams: 100, proteinMinDaysPerWeek: 5, maxWeighInAgeWeeks: 1, maxProjectionWeeks: 104,
            targetToleranceKg: 0)
        h.settings.phases = [cut]
        h.settings.parameters = parameters

        let input = await h.builder.build(today: clock.today)

        XCTAssertEqual(input.today, clock.today)
        XCTAssertEqual(input.parameters, parameters)
        XCTAssertEqual(input.phase, CutScorecardPhase(name: "Fixture cut", startDay: clock.day(-14), targetWeightKg: 94.0,
                                                      rateLowPercentPerWeek: 0.4, rateHighPercentPerWeek: 1.2))
        XCTAssertNil(CutScorecard.evaluate(input).invalidInput)

        // Built for a day before the phase started, the phase is not active yet.
        let before = await h.builder.build(today: clock.day(-15))
        XCTAssertEqual(before.today, clock.day(-15))
        XCTAssertNil(before.phase)
    }

    func testNonCutPhasePassesNilPhase() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        h.settings.phases = [
            CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: clock.day(-60), targetWeightKg: 94.0,
                                    rateLowPercentPerWeek: 0.4, rateHighPercentPerWeek: 1.2),
            CutScorecardStoredPhase(kind: .other, name: "Fixture maintenance", startDay: clock.day(-7),
                                    targetWeightKg: nil, rateLowPercentPerWeek: 0, rateHighPercentPerWeek: 0),
        ]
        try await h.weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: clock.instant(0))

        let input = await h.builder.build(today: clock.today)

        XCTAssertNil(input.phase, "a phase of another kind is active, so the function is passed nil")
        let result = CutScorecard.evaluate(input)
        XCTAssertEqual(result.verdict.kind, .insufficientData)
        XCTAssertEqual(result.verdict.reason, .noActivePhase)
        XCTAssertEqual(result.currentWeightKg, 100.0, "the weight is still reported outside a cut")
    }

    func testAbsentRulesPassTheGenericParameters() async throws {
        let clock = Clock()
        let h = try await makeHarness(clock)
        let input = await h.builder.build(today: clock.today)
        XCTAssertEqual(input.parameters, .generic)
        XCTAssertNil(input.phase)
        XCTAssertTrue(input.weights.isEmpty)
        XCTAssertTrue(input.waists.isEmpty)
        let result = CutScorecard.evaluate(input)
        XCTAssertNil(result.invalidInput)
        XCTAssertEqual(result.verdict.kind, .insufficientData)
        XCTAssertNil(result.currentWeightKg)
        XCTAssertTrue(result.weeks.isEmpty)
    }
}
