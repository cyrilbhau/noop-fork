// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §7.3, §8.2, §8.3, §9.1 and §12.3 (`IntakeHealthSyncTests.swift`). Written
// before the implementation exists. New, in Strand/Data/IntakeHealthSync.swift, as §8.2 gives it:
//
//     @MainActor struct IntakeHealthSync {
//         enum Outcome: Equatable { case disabled, failedRead, preserved, unchanged,
//                                   written(changedDays: [String]), failedWrite }
//         init(repository: Repository, settings: IntakeSettings, now: @escaping () -> Date,
//              zoneIdentifier: @escaping () -> String)
//         func queryWindow(days: Int) -> (start: Date, end: Date, firstDay: String, lastDay: String)
//         func apply(samples: [IntakeSample]?, firstDay: String, lastDay: String) async -> Outcome
//     }
//
// `IntakeSettings` and `IntakeProvider` as at the top of IntakeTestSupport.swift. No HealthKit is
// involved: Path A's bridge edit waits for the owner's go-ahead, and this type imports none.
//
// Behaviour assumed where the specification leaves it open:
//  1. `apply` returns `.disabled` and does nothing whenever `settings.healthReadEnabled` is false
//     (the flag off, or the source not Apple Health).
//  2. `apply` sets `healthBackfilled` once a read returned at least one sample and its write
//     succeeded (§8.2: "set only once a read returned at least one sample").
//  3. `apply` records every admitted bundle id it saw with the latest day it saw it on (§9.2,
//     `recordHealthSource`); the recorded name is not asserted, since a sample carries none.
//  4. Which provider instance `apply` tells to refresh (§8.2) is not asserted: the tests read the
//     store through their own provider after calling its `refresh()`.
//  5. `testAStoreReadFailureWritesNothing` is skipped: the tree has no seam that makes a store read
//     fail from this target (see the test).
//
// Synthetic values only: the samples of §13.2, moved onto the real clock (§13.6).

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class IntakeHealthSyncTests: XCTestCase {
    private let suites = IntakeSuites()
    private let id = IntakeFixture.healthId

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func harness(flag: Bool = true, source: IntakeSourceSetting? = .appleHealth) async throws -> IntakeHarness {
        let h = try await IntakeHarness.make(flag: flag, source: source, suites: suites)
        try await h.seedUnrelated()
        return h
    }

    /// The §13.2 samples s1 to s8, on yesterday (offset -1) and today, UTC.
    private func fixtureSamples(_ h: IntakeHarness) -> [IntakeSample] {
        [h.sample("s1", .protein, h.clock.epoch(-1, hour: 8), 30),
         h.sample("s2", .energy, h.clock.epoch(-1, hour: 8), 450),
         h.sample("s3", .protein, h.clock.epoch(-1, hour: 13), 40),
         h.sample("s4", .energy, h.clock.epoch(-1, hour: 13), 700),
         h.sample("s5", .protein, h.clock.epoch(-1, hour: 23, minute: 59, second: 59), 25),
         h.sample("s6", .energy, h.clock.epoch(-1, hour: 23, minute: 59, second: 59), 300),
         h.sample("s7", .protein, h.clock.epoch(0, hour: 0), 20),
         h.sample("s8", .energy, h.clock.epoch(0, hour: 0), 250)]
    }

    private func onlyHealthRows(_ row: IntakeRow) -> Bool { row.deviceId == IntakeFixture.healthId }

    // MARK: - Nothing happens

    func testDisabledSettingReadsAndWritesNothing() async throws {
        for (flag, source) in [(false, IntakeSourceSetting.appleHealth), (true, .quickAdd), (true, .none),
                               (false, .quickAdd)] {
            let h = try await harness(flag: flag, source: source)
            try await h.seed(id, day: h.clock.day(-1), protein: 90, energy: 1_000, readAt: h.clock.epoch(-1, hour: 9))
            let before = try await h.rows()
            let defaultsBefore = h.defaults.snapshot()
            h.defaults.written = []
            let sync = h.healthSync()
            let outcome = await sync.apply(samples: fixtureSamples(h), firstDay: h.clock.day(-1), lastDay: h.today)
            XCTAssertEqual(outcome, .disabled, "flag \(flag), source \(source)")
            let after = try await h.rows()
            XCTAssertEqual(after, before, "flag \(flag), source \(source): no row written or deleted")
            XCTAssertEqual(h.defaults.written, [], "flag \(flag), source \(source): no setting written")
            XCTAssertEqual(h.defaults.snapshot(), defaultsBefore)
        }
    }

    func testAFailedReadLeavesEveryStoredDayUntouched() async throws {
        let h = try await harness()
        try await h.seed(id, day: h.clock.day(-1), protein: 95, energy: 1_450, readAt: h.clock.epoch(-1, hour: 22))
        try await h.seed(id, day: h.today, protein: 20, energy: 250, readAt: h.clock.epoch(0, hour: 9))
        let before = try await h.rows()
        h.defaults.written = []
        let outcome = await h.healthSync().apply(samples: nil, firstDay: h.clock.day(-1), lastDay: h.today)
        XCTAssertEqual(outcome, .failedRead)
        let after = try await h.rows()
        XCTAssertEqual(after, before, "a failed read is never treated as an empty one, and freshness does not advance")
        XCTAssertFalse(h.settings.healthBackfilled)
        XCTAssertFalse(h.defaults.written.contains(IntakeSettings.healthBackfilledKey))
        XCTAssertFalse(h.defaults.written.contains(IntakeSettings.healthKnownSourcesKey))
    }

    func testAnEmptyWindowLeavesEveryStoredDayUntouched() async throws {
        let h = try await harness()
        try await h.seed(id, day: h.clock.day(-1), protein: 95, energy: 1_450, readAt: h.clock.epoch(-1, hour: 22))
        let before = try await h.rows()
        let outcome = await h.healthSync().apply(samples: [], firstDay: h.clock.day(-1), lastDay: h.today)
        XCTAssertEqual(outcome, .preserved)
        let after = try await h.rows()
        XCTAssertEqual(after, before, "an empty window is not evidence that a stored day is wrong")
        XCTAssertFalse(h.settings.healthBackfilled)

        // Samples that are all outside the window or all from an excluded app are an empty window too.
        h.settings.admittedHealthSources = [IntakeFixture.otherApp.bundleId]
        let excluded = await h.healthSync().apply(samples: fixtureSamples(h), firstDay: h.clock.day(-1), lastDay: h.today)
        XCTAssertEqual(excluded, .preserved)
        let still = try await h.rows()
        XCTAssertEqual(still, before)
    }

    // MARK: - Writes

    func testASuccessfulReadWritesTotalsAndReadTimes() async throws {
        let h = try await harness()
        let before = try await h.rows()
        let outcome = await h.healthSync().apply(samples: fixtureSamples(h), firstDay: h.clock.day(-1), lastDay: h.today)
        XCTAssertEqual(outcome, .written(changedDays: [h.clock.day(-1), h.today]))
        let readAt = Double(Int(h.clock.now.timeIntervalSince1970))
        let expected: Set<IntakeRow> = [
            IntakeRow(deviceId: id, day: h.clock.day(-1), key: "protein_g", value: 95),
            IntakeRow(deviceId: id, day: h.clock.day(-1), key: "calories_in", value: 1_450),
            IntakeRow(deviceId: id, day: h.clock.day(-1), key: "intake_read_at", value: readAt),
            IntakeRow(deviceId: id, day: h.today, key: "protein_g", value: 20),
            IntakeRow(deviceId: id, day: h.today, key: "calories_in", value: 250),
            IntakeRow(deviceId: id, day: h.today, key: "intake_read_at", value: readAt),
        ]
        let after = try await h.rows()
        XCTAssertEqual(after.filter(onlyHealthRows), expected,
                       "s5 at 23:59:59 counts to yesterday and s7 at 00:00:00 to today (§13.3)")
        assertOnlyRowsChanged(before: before, after: after, allowed: onlyHealthRows)

        // The same read again: nothing changed but the read times, which advance.
        let later = h.clock.at(0, hour: 16)
        let again = await h.healthSync(now: later).apply(samples: fixtureSamples(h), firstDay: h.clock.day(-1),
                                                          lastDay: h.today)
        XCTAssertEqual(again, .unchanged)
        let readAgain = try await h.value(id, h.today, "intake_read_at")
        XCTAssertEqual(readAgain, Double(Int(later.timeIntervalSince1970)))
        let protein = try await h.value(id, h.clock.day(-1), "protein_g")
        XCTAssertEqual(protein, 95)
    }

    func testADeletedLastEntryRemovesTheDayAtTheNextRead() async throws {
        let h = try await harness()
        _ = await h.healthSync().apply(samples: fixtureSamples(h), firstDay: h.clock.day(-1), lastDay: h.today)
        let before = try await h.rows()
        // s7 and s8 deleted at the source: today has no sample left, yesterday still has its own.
        let remaining = fixtureSamples(h).filter { $0.id != "s7" && $0.id != "s8" }
        let outcome = await h.healthSync().apply(samples: remaining, firstDay: h.clock.day(-1), lastDay: h.today)
        XCTAssertEqual(outcome, .written(changedDays: [h.today]))
        let after = try await h.rows()
        XCTAssertEqual(after.filter { onlyHealthRows($0) && $0.day == h.today }, [],
                       "the emptied day's three rows are deleted; it reads not measured, never zero")
        XCTAssertEqual(after.filter { onlyHealthRows($0) && $0.day == h.clock.day(-1) && $0.key != "intake_read_at" },
                       before.filter { onlyHealthRows($0) && $0.day == h.clock.day(-1) && $0.key != "intake_read_at" })
        assertOnlyRowsChanged(before: before, after: after, allowed: onlyHealthRows)

        // Protein deleted from yesterday while its energy stays: only the protein row goes.
        let energyOnly = remaining.filter { $0.nutrient == .energy }
        let third = await h.healthSync().apply(samples: energyOnly, firstDay: h.clock.day(-1), lastDay: h.today)
        XCTAssertEqual(third, .written(changedDays: [h.clock.day(-1)]))
        let protein = try await h.value(id, h.clock.day(-1), "protein_g")
        XCTAssertNil(protein)
        let energy = try await h.value(id, h.clock.day(-1), "calories_in")
        XCTAssertEqual(energy, 1_450)
    }

    func testAStoreReadFailureWritesNothing() async throws {
        // §8.2: "a failed store read returns failedWrite and writes nothing". Not pinnable from the
        // app test target today: `Repository` opens the real on-disk database when it has no store,
        // which a test must never do, and making an in-memory store's read fail needs GRDB, which
        // StrandTests does not link (adding it is a project.yml change this stage may not make).
        // Pinned instead by review and by the fault line F2/F3 tests around it.
        throw XCTSkip("no seam makes a store read fail without GRDB linkage or the real database (§8.2)")
    }

    // MARK: - The window and the zone log

    func testQueryWindowStartsFourDaysBeforeTheFirstWrittenDay() async throws {
        let h = try await harness()
        for days in [1, 30, 90] {
            let window = h.healthSync().queryWindow(days: days)
            XCTAssertEqual(window.lastDay, h.today)
            XCTAssertEqual(window.firstDay, h.clock.day(-days))
            XCTAssertEqual(window.end, h.clock.at(1, hour: 0), "the start of the day after the last day")
            XCTAssertEqual(window.start, h.clock.at(-(days + 4), hour: 0),
                           "four local days before the first written day (§7.3)")
            XCTAssertLessThanOrEqual(window.start, h.clock.at(-days, hour: 0).addingTimeInterval(-4 * 86_400))
        }
        // In a zone ahead of UTC the boundaries are that zone's midnights.
        let auckland = TimeZone(identifier: "Pacific/Auckland")!
        let window = h.healthSync(zone: "Pacific/Auckland").queryWindow(days: 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = auckland
        XCTAssertEqual(calendar.component(.hour, from: window.start), 0)
        XCTAssertEqual(calendar.component(.minute, from: window.start), 0)
        XCTAssertEqual(calendar.component(.hour, from: window.end), 0)
        XCTAssertEqual(calendar.dateComponents([.day], from: window.start, to: window.end).day, 6,
                       "five days before today to the end of today, in the current zone")
    }

    func testTheZoneLogIsExtendedBeforeTheRead() async throws {
        let h = try await harness()
        XCTAssertEqual(h.settings.zoneLog.map(\.zoneIdentifier), ["Etc/UTC"])
        let sync = h.healthSync(zone: "Pacific/Auckland")
        let window = sync.queryWindow(days: 1)
        let log = h.settings.zoneLog
        XCTAssertEqual(log.map(\.zoneIdentifier), ["Etc/UTC", "Pacific/Auckland"])
        XCTAssertEqual(log.last?.fromEpochSeconds, Int(h.clock.now.timeIntervalSince1970))
        XCTAssertEqual(window.lastDay, IntakeAggregation.dayKey(epochSeconds: Int(h.clock.now.timeIntervalSince1970),
                                                                zoneLog: log))

        // A sample before the change is keyed in UTC; one after it in Auckland.
        let early = h.sample("e1", .protein, h.clock.epoch(0, hour: 9), 30)            // 09:00 UTC today
        let late = h.sample("e2", .protein, h.clock.epoch(0, hour: 15, minute: 30), 40) // after now: Auckland, tomorrow
        let outcome = await sync.apply(samples: [early, late], firstDay: h.clock.day(-1), lastDay: h.clock.day(1))
        guard case .written = outcome else { return XCTFail("expected a write, got \(outcome)") }
        let today = try await h.value(id, h.today, "protein_g")
        let tomorrow = try await h.value(id, h.clock.day(1), "protein_g")
        XCTAssertEqual(today, 30)
        XCTAssertEqual(tomorrow, 40)
    }

    // MARK: - Settings the sync keeps

    func testTheBackfillFlagIsSetOnlyAfterSamplesWereFound() async throws {
        let h = try await harness()
        _ = await h.healthSync().apply(samples: nil, firstDay: h.clock.day(-1), lastDay: h.today)
        XCTAssertFalse(h.settings.healthBackfilled, "a failed read")
        _ = await h.healthSync().apply(samples: [], firstDay: h.clock.day(-1), lastDay: h.today)
        XCTAssertFalse(h.settings.healthBackfilled, "an empty window")
        _ = await h.healthSync().apply(samples: fixtureSamples(h), firstDay: h.clock.day(-1), lastDay: h.today)
        XCTAssertTrue(h.settings.healthBackfilled, "a read that found samples")
    }

    func testTotalsAreWrittenUnderTheDedicatedIdAndNeverUnderAppleHealth() async throws {
        let h = try await harness()
        let before = try await h.rows([IntakeFixture.appleHealthId])
        _ = await h.healthSync().apply(samples: fixtureSamples(h), firstDay: h.clock.day(-1), lastDay: h.today)
        let appleHealth = try await h.rows([IntakeFixture.appleHealthId])
        XCTAssertEqual(appleHealth, before, "nothing under apple-health changes")
        let keys = try await h.store.metricKeys(deviceId: IntakeFixture.appleHealthId)
        XCTAssertFalse(keys.contains { IntakeFixture.intakeKeys.contains($0) }, "no intake key under apple-health")
        let health = try await h.store.metricKeys(deviceId: IntakeFixture.healthId)
        XCTAssertEqual(Set(health), Set(IntakeFixture.intakeKeys))
        let quick = try await h.store.metricKeys(deviceId: IntakeFixture.quickAddId)
        XCTAssertEqual(quick, [], "the Health funnel never writes the quick-add id")
        XCTAssertEqual(IntakeProvider.healthSourceId, "noop-intake-health")
        XCTAssertEqual(IntakeProvider.quickAddSourceId, "noop-intake")
        XCTAssertEqual(IntakeProvider.csvSourceId, "nutrition-csv")
    }

    func testKnownSourcesAreRecordedWithTheirLastSeenDay() async throws {
        let h = try await harness()
        var samples = fixtureSamples(h)
        samples.append(h.sample("s9", .protein, h.clock.epoch(-1, hour: 10), 10, source: IntakeFixture.otherApp.bundleId))
        _ = await h.healthSync().apply(samples: samples, firstDay: h.clock.day(-1), lastDay: h.today)
        let known = h.settings.knownHealthSources
        XCTAssertEqual(Set(known.keys), [IntakeFixture.foodApp.bundleId, IntakeFixture.otherApp.bundleId])
        XCTAssertEqual(known[IntakeFixture.foodApp.bundleId]?.lastSeenDay, h.today)
        XCTAssertEqual(known[IntakeFixture.otherApp.bundleId]?.lastSeenDay, h.clock.day(-1))
        let total = try await h.value(id, h.clock.day(-1), "protein_g")
        XCTAssertEqual(total, 105, "both apps are counted by default (§13.3)")

        // With one app admitted, the other is left out of the total.
        h.settings.admittedHealthSources = [IntakeFixture.foodApp.bundleId]
        _ = await h.healthSync().apply(samples: samples, firstDay: h.clock.day(-1), lastDay: h.today)
        let admitted = try await h.value(id, h.clock.day(-1), "protein_g")
        XCTAssertEqual(admitted, 95)
    }

    func testProviderRevisionMovesAfterAWrite() async throws {
        let h = try await harness()
        await h.provider.refresh()
        let start = h.provider.revision
        XCTAssertNil(h.provider.day(h.clock.day(-1)))
        _ = await h.healthSync().apply(samples: fixtureSamples(h), firstDay: h.clock.day(-1), lastDay: h.today)
        await h.provider.refresh()
        XCTAssertGreaterThan(h.provider.revision, start)
        let resolved = h.provider.day(h.clock.day(-1))
        XCTAssertEqual(resolved?.protein?.value, 95)
        XCTAssertEqual(resolved?.protein?.source, .appleHealth)
        XCTAssertEqual(resolved?.protein?.readAtEpochSeconds, Int(h.clock.now.timeIntervalSince1970))
        XCTAssertEqual(resolved?.energy?.value, 1_450)
    }
}
