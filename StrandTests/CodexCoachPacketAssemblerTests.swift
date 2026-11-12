// API ASSUMED BY THESE TESTS
// Stage 2 §§6.2, 8.2–8.4, 12.3 and ruling A17, packet version 1.
// CoachPacketAssembler(repository:provider:scorecardSettings:settings:now:timeZone:
// effortScale:identifiers:) exposes input() async -> CoachPacketInput? and
// assemble() async -> CoachPacketOutcome (.ready(document), .blocked(findings:), .unavailable).
// CoachPacketInput exposes generatedAt, rangeStartDay, rangeEndDay, sections, days,
// strainFactor, scorecard, body, steps, workouts and optional baseline fields as specified.
// CoachPacketSettings(defaults:) exposes isEnabled, rangeDays, sections, setSection(_:on:).
// No new test seam is assumed. Existing Repository.setStoreForTesting is used.
// These tests are authored before the implementation, from the specification. No app build
// is authorised for C5; swiftc -parse checks syntax only, not API or runtime correctness.
import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class CodexCoachPacketAssemblerTests: XCTestCase {
    private var suites: [String] = []
    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func harness(now: @escaping () -> Date, zone: @escaping () -> TimeZone,
                         scale: @escaping () -> EffortScale = { .hundred },
                         identifiers: @escaping () -> [String] = { [] }) async throws
        -> (WhoopStore, Repository, UserDefaults, BodyMeasurementProvider, CoachPacketSettings, CoachPacketAssembler) {
        let suite = "CodexPacket-\(UUID().uuidString)"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults,
            today: { Repository.localDayKey(Date()) })
        let settings = CoachPacketSettings(defaults: defaults)
        settings.isEnabled = true
        let assembler = CoachPacketAssembler(repository: repo, provider: provider,
            scorecardSettings: CutScorecardSettings(defaults: defaults), settings: settings,
            now: now, timeZone: zone, effortScale: scale, identifiers: identifiers)
        return (store, repo, defaults, provider, settings, assembler)
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testOneClockGivesGeneratedAtTodayAndInclusiveRange() async throws {
        var reads = 0
        let instant = date("2026-11-10T21:00:10Z")
        let h = try await harness(now: { reads += 1; return instant },
                                  zone: { TimeZone(secondsFromGMT: 19800)! })
        let value = await h.5.input()
        let input = try XCTUnwrap(value)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(input.generatedAt, "2026-11-11T02:30:10+05:30")
        XCTAssertEqual(input.rangeEndDay, "2026-11-11")
        XCTAssertEqual(input.rangeStartDay, "2026-10-29")
    }

    func testRangeAcrossDaylightSavingUsesCalendarDays() async throws {
        let instant = date("2026-11-02T05:30:00Z")
        let h = try await harness(now: { instant }, zone: { TimeZone(identifier: "America/New_York")! })
        h.4.rangeDays = 7
        let value = await h.5.input()
        let input = try XCTUnwrap(value)
        XCTAssertEqual(input.rangeEndDay, "2026-11-02")
        XCTAssertEqual(input.rangeStartDay, "2026-10-27")
        XCTAssertEqual(input.generatedAt, "2026-11-02T00:30:00-05:00")
    }

    func testZoneChangeMovesTodayOnNextAssembly() async throws {
        let instant = date("2026-11-10T23:30:00Z")
        var zone = TimeZone(secondsFromGMT: 0)!
        let h = try await harness(now: { instant }, zone: { zone })
        let first = await h.5.input()
        zone = TimeZone(secondsFromGMT: 19800)!
        let second = await h.5.input()
        XCTAssertEqual(first?.rangeEndDay, "2026-11-10")
        XCTAssertEqual(second?.rangeEndDay, "2026-11-11")
    }

    func testAllAllowedRangesAreInclusive() async throws {
        let instant = date("2026-11-11T08:00:00Z")
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 0)! })
        for (days, start) in [(7, "2026-11-05"), (14, "2026-10-29"), (28, "2026-10-15")] {
            h.4.rangeDays = days
            let input = await h.5.input()
            XCTAssertEqual(input?.rangeStartDay, start)
            XCTAssertEqual(input?.rangeEndDay, "2026-11-11")
        }
    }

    func testScorecardOffProducesSwitchedOffAndOmitsUnsetProfile() async throws {
        let instant = Date()
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 0)! })
        let value = await h.5.input()
        let input = try XCTUnwrap(value)
        XCTAssertEqual(input.scorecard, .switchedOff)
        XCTAssertTrue(input.body.isEmpty)
    }

    func testBodyValuesEqualTheProviderAfterRefresh() async throws {
        let instant = Date()
        let today = LocalDayWindows(timeZone: TimeZone(secondsFromGMT: 0)!).dayKey(for: instant)
        let number = try XCTUnwrap(CanonicalDay.number(today))
        // Fixture week 1 shifted by whole weeks to a past Wednesday, safely before now.
        let day = CanonicalDay.key(number - 7 - (number % 7 + 5) % 7)
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 0)! })
        h.2.set(true, forKey: CutScorecardSettings.enabledKey)
        let epoch = Int(date(day + "T07:00:00Z").timeIntervalSince1970)
        let rows = [("weight", 100.0, "kg"), ("waist", 100.0, "cm")].map { key, value, unit in
            LabMarkerRow(id: "fixture-\(key)", deviceId: "my-whoop", markerKey: key,
                category: "bodyMeasurement", day: day, takenAt: epoch, value: value,
                valueText: nil, unit: unit, source: "manual", note: nil, referenceText: nil)
        }
        try await h.0.upsertLabMarkers(rows)
        let value = await h.5.input()
        let input = try XCTUnwrap(value)
        XCTAssertEqual(input.body.count, 2)
        for (kind, packetKind) in [(BodyMeasurementKind.weight, CoachPacketBodyKind.weight), (.waist, .waist)] {
            let body = try XCTUnwrap(input.body.first { $0.kind == packetKind })
            let resolved = try XCTUnwrap(h.3.current(kind, consumer: .display))
            XCTAssertEqual(body.value, resolved.value)
            XCTAssertEqual(body.day, resolved.day)
            XCTAssertEqual(body.source, .labBook)
        }
    }

    func testEffortScaleUsesTheDisplayFactor() async throws {
        let instant = Date()
        var scale = EffortScale.hundred
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 0)! }, scale: { scale })
        let hundred = await h.5.input()
        scale = .whoop
        let whoop = await h.5.input()
        XCTAssertEqual(hundred?.strainFactor, 1)
        XCTAssertEqual(whoop?.strainFactor, 0.21)
    }

    func testStoredSectionChoicesAreCapturedInTheInputAndDocument() async throws {
        let instant = Date()
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 0)! })
        h.4.setSection(.activity, on: false)
        h.4.setSection(.trends, on: false)
        let input = await h.5.input()
        XCTAssertEqual(input?.sections, h.4.sections)
        guard case .ready(let document) = await h.5.assemble() else { return XCTFail("Expected ready") }
        XCTAssertEqual(document.sections, h.4.sections)
        XCTAssertEqual(document.byteCount, document.text.utf8.count)
        XCTAssertEqual(document.generatedAt, instant)
        XCTAssertEqual(document.rangeDays, 14)
    }

    func testDailyRowsOutsideTheRangeAreExcluded() async throws {
        let instant = date("2026-11-11T08:00:00Z")
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 0)! })
        func row(_ day: String) -> DailyMetric {
            DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                strain: nil, exerciseCount: nil)
        }
        h.1.days = [row("2026-10-28"), row("2026-10-29"), row("2026-11-11"), row("2026-11-12")]
        let input = await h.5.input()
        XCTAssertEqual(input?.days.map(\.day), ["2026-10-29", "2026-11-11"])
    }

    func testKnownIdentifierFailsClosedWithoutReturningText() async throws {
        let instant = Date()
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 0)! },
                                  identifiers: { ["Fixture Device"] })
        h.2.set(true, forKey: CutScorecardSettings.enabledKey)
        let day = LocalDayWindows(timeZone: TimeZone(secondsFromGMT: 0)!).dayKey(for: instant)
        CutScorecardSettings(defaults: h.2).phases = [CutScorecardStoredPhase(kind: .cut,
            name: "Fixture Device", startDay: day, targetWeightKg: nil,
            rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)]
        guard case .blocked(let findings) = await h.5.assemble() else { return XCTFail("Expected blocked") }
        XCTAssertGreaterThan(findings, 0)
    }

    func testAssemblyDoesNotRequireCoachConsentOrChangeDefaultsAndRows() async throws {
        let instant = Date()
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 0)! })
        h.2.set(false, forKey: "noop.coachEnabled")
        let before = h.2.dictionaryRepresentation() as NSDictionary
        let rowsBefore = try await h.0.labMarkers(deviceId: "my-whoop", markerKey: "weight")
        guard case .ready = await h.5.assemble() else { return XCTFail("Expected ready without Coach consent") }
        let rowsAfter = try await h.0.labMarkers(deviceId: "my-whoop", markerKey: "weight")
        XCTAssertEqual(before, h.2.dictionaryRepresentation() as NSDictionary)
        XCTAssertEqual(rowsBefore, rowsAfter)
    }
    func testStepsEqualTheRepositoryResolutionIncludingSourceClassification() async throws {
        let instant = Date()
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 0)! })
        let today = Repository.localDayKey(instant)
        let n = try XCTUnwrap(CanonicalDay.number(today))
        let prior = CanonicalDay.key(n - 1)
        let earlier = CanonicalDay.key(n - 2)
        try await h.0.upsertMetricSeries([MetricPoint(day: earlier, key: "steps", value: 7000)], deviceId: "my-whoop")
        try await h.0.upsertMetricSeries([MetricPoint(day: prior, key: "steps", value: 6000)], deviceId: "apple-health")
        try await h.0.upsertMetricSeries([MetricPoint(day: today, key: "steps_est", value: 5000)], deviceId: "my-whoop-noop")
        let value = await h.5.input()
        let input = try XCTUnwrap(value)
        let resolution = await h.1.resolvedSteps(from: input.rangeStartDay, to: input.rangeEndDay)
        XCTAssertEqual(input.steps.count, 3)
        XCTAssertEqual(input.steps.map(\.day), resolution.points.map(\.day))
        XCTAssertEqual(input.steps.map(\.steps), resolution.points.map(\.value))
        XCTAssertEqual(input.steps.map(\.source), [.strap, .appleHealth, .strapEstimate])
    }

    func testWorkoutUsesLocalDayMinuteAndConvertedUnits() async throws {
        let instant = Date()
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 19800)! })
        let start = Int(instant.timeIntervalSince1970) - 7200
        let row = WorkoutRow(startTs: start, endTs: start + 1800, sport: "Running", source: "manual",
            durationS: 1800, energyKcal: 200, avgHr: 120, maxHr: 140, strain: nil,
            distanceM: 3500, zonesJSON: nil, notes: nil, steps: nil)
        try await h.0.upsertWorkouts([row], deviceId: "my-whoop")
        let value = await h.5.input()
        let input = try XCTUnwrap(value)
        let workout = try XCTUnwrap(input.workouts.first)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 19800)!
        let startDate = Date(timeIntervalSince1970: Double(start))
        let parts = calendar.dateComponents([.hour, .minute], from: startDate)
        XCTAssertEqual(workout.day, LocalDayWindows(timeZone: calendar.timeZone).dayKey(for: startDate))
        XCTAssertEqual(workout.startMinuteOfDay, parts.hour! * 60 + parts.minute!)
        XCTAssertEqual(workout.source, .manual)
        XCTAssertEqual(workout.durationMinutes, 30)
        XCTAssertEqual(workout.distanceKm, 3.5)
        XCTAssertEqual(workout.energyKcal, 200)
    }

    func testBaselineBoundsAreChargeTypicalBands() async throws {
        let instant = Date()
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 0)! })
        let number = try XCTUnwrap(CanonicalDay.number(Repository.localDayKey(instant)))
        let rows = (0..<35).map { offset in
            DailyMetric(day: CanonicalDay.key(number - offset), totalSleepMin: 480,
                efficiency: 90, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                restingHr: 60, avgHrv: 50, recovery: 70, strain: nil, exerciseCount: nil)
        }
        try await h.0.upsertDailyMetrics(rows, deviceId: "my-whoop")
        await h.1.refresh()
        let resolved = try XCTUnwrap(h.1.chargeBaselines)
        let value = await h.5.input()
        let input = try XCTUnwrap(value)
        let hrv = try XCTUnwrap(input.hrvBaseline)
        let rhr = try XCTUnwrap(input.restingHrBaseline)
        XCTAssertEqual(hrv.center, resolved.hrv.baseline)
        XCTAssertEqual(hrv.typical, ChargeTypicalBand.range(resolved.hrv))
        XCTAssertEqual(hrv.status, resolved.hrv.status.rawValue)
        XCTAssertEqual(hrv.nights, resolved.hrv.nValid)
        XCTAssertEqual(rhr.center, resolved.restingHR.baseline)
        XCTAssertEqual(rhr.typical, ChargeTypicalBand.range(resolved.restingHR))
        XCTAssertEqual(rhr.status, resolved.restingHR.status.rawValue)
        XCTAssertEqual(rhr.nights, resolved.restingHR.nValid)
    }

    func testScorecardResultEqualsTheSharedBuildersEvaluation() async throws {
        let instant = Date()
        let zone = TimeZone(secondsFromGMT: 0)!
        let h = try await harness(now: { instant }, zone: { zone })
        let settings = CutScorecardSettings(defaults: h.2)
        settings.isEnabled = true
        let today = LocalDayWindows(timeZone: zone).dayKey(for: instant)
        settings.phases = [CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: today,
            targetWeightKg: 94, rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)]
        let value = await h.5.input()
        let input = try XCTUnwrap(value)
        let expected = await CutScorecardInputBuilder(repository: h.1, provider: h.3,
            settings: settings, intake: .live(repository: h.1), // Adapted: intake is required (stage 3)
            timeZone: { zone }).evaluation(today: today)
        guard case .evaluated(let phase, let result) = input.scorecard else {
            return XCTFail("Expected evaluated scorecard")
        }
        XCTAssertEqual(result, expected.result)
        XCTAssertEqual(phase?.name, expected.input.phase?.name)
        XCTAssertEqual(phase?.targetWeightKg, expected.input.phase?.targetWeightKg)
    }

    func testEmptyRepositoryDoesNotFabricateBaselines() async throws {
        let instant = Date()
        let h = try await harness(now: { instant }, zone: { TimeZone(secondsFromGMT: 0)! })
        let value = await h.5.input()
        let input = try XCTUnwrap(value)
        XCTAssertNil(input.hrvBaseline)
        XCTAssertNil(input.restingHrBaseline)
        XCTAssertTrue(input.steps.isEmpty)
        XCTAssertTrue(input.workouts.isEmpty)
    }

}
