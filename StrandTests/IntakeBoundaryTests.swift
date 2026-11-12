// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §9.1 (R42: a strap never owns the owner's readings), §9.6 (backup),
// §12.2 (the store boundaries, exercised here through the app's funnels and the real store),
// §12.5 (flag-off equivalence) and §12.8 (privacy of the backup). Written before the
// implementation exists. Uses, as at the top of IntakeTestSupport.swift: `IntakeSettings`,
// `IntakeProvider`, `IntakeHealthSync`, `IntakeQuickAddStore`; and, as at the top of their own test
// files, `IntakeSupplementTick` and `IntakeCutoffReminder`.
//
// `WhoopStore.deleteAllData(deviceId:)` and `BackupSettings.snapshot(from:)`, `encode(_:)`,
// `decode(_:)`, `apply(_:to:)` are used as they exist today.
//
// The two backup round-trip tests are the ones §12.2 lists for BackupSettingsTests.swift in the
// WhoopStore package; they are written here, in a new app-target file, because this work package
// adds new files only. They fail until the orchestrator's commit 3-6h adds the two keys to
// `BackupSettings.whitelist` and `appleDefaultsKey`.
//
// Synthetic values only.

import XCTest
import UserNotifications
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class IntakeBoundaryTests: XCTestCase {
    private let suites = IntakeSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private final class SilentCenter: WeighInReminderCenter {
        private(set) var calls = 0
        func authorizationStatus() async -> UNAuthorizationStatus { calls += 1; return .authorized }
        func requestAuthorization() async -> Bool { calls += 1; return true }
        func add(_ request: UNNotificationRequest) async { calls += 1 }
        func removePendingRequests(withIdentifiers identifiers: [String]) { calls += 1 }
        func pendingRequests() async -> [UNNotificationRequest] { calls += 1; return [] }
    }

    /// Intake rows under both intake ids, within and beyond 30 days, plus the unrelated rows.
    private func seedIntakeEverywhere(_ h: IntakeHarness) async throws {
        try await h.seedUnrelated()
        for offset in [-1, -45] {
            try await h.seed(IntakeFixture.healthId, day: h.clock.day(offset), protein: 120, energy: 2_400,
                             readAt: h.clock.epoch(offset, hour: 21))
            try await h.seed(IntakeFixture.quickAddId, day: h.clock.day(offset), protein: 80, energy: 1_900,
                             readAt: h.clock.epoch(offset, hour: 20))
        }
    }

    private func intakeRows(_ rows: Set<IntakeRow>) -> Set<IntakeRow> {
        rows.filter { $0.deviceId == IntakeFixture.healthId || $0.deviceId == IntakeFixture.quickAddId }
    }

    // MARK: - R42 and the Apple Health delete (§9.1, §12.2)

    func testIntakeRowsSurviveDeletingAStrapsData() async throws {
        let h = try await IntakeHarness.make(suites: suites)
        try await seedIntakeEverywhere(h)
        let before = try await h.rows()
        XCTAssertEqual(intakeRows(before).count, 12)
        try await h.store.deleteAllData(deviceId: IntakeFixture.strapId)
        let after = try await h.rows()
        XCTAssertEqual(intakeRows(after), intakeRows(before), "removing a strap's data never touches intake")
        XCTAssertTrue(after.filter { $0.deviceId == IntakeFixture.strapId }.isEmpty, "the strap's own rows did go")
        await h.provider.refresh()
        XCTAssertEqual(h.provider.day(h.clock.day(-1))?.protein?.value, 120, "nothing is hidden either")
    }

    func testDeletingAppleHealthDataLeavesEveryIntakeRow() async throws {
        let h = try await IntakeHarness.make(suites: suites)
        try await seedIntakeEverywhere(h)
        let before = try await h.rows()
        try await h.store.deleteAllData(deviceId: IntakeFixture.appleHealthId)
        let after = try await h.rows()
        XCTAssertEqual(intakeRows(after), intakeRows(before),
                       "days older and newer than 30 days survive the Apple Health page's delete")
        XCTAssertTrue(after.filter { $0.deviceId == IntakeFixture.appleHealthId }.isEmpty)
    }

    func testTheTwoIntakeIdsAreIndependent() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .appleHealth, suites: suites)
        try await seedIntakeEverywhere(h)
        let before = try await h.rows()
        // A Health read in which yesterday lost every sample deletes that day under the Health id only.
        let today = h.sample("t1", .protein, h.clock.epoch(0, hour: 9), 30)
        _ = await h.healthSync().apply(samples: [today], firstDay: h.clock.day(-1), lastDay: h.today)
        let after = try await h.rows()
        XCTAssertTrue(after.filter { $0.deviceId == IntakeFixture.healthId && $0.day == h.clock.day(-1) }.isEmpty)
        XCTAssertEqual(after.filter { $0.deviceId == IntakeFixture.quickAddId },
                       before.filter { $0.deviceId == IntakeFixture.quickAddId },
                       "the quick-add row for the same day and key is untouched")
        assertOnlyRowsChanged(before: before, after: after, allowed: {
            $0.deviceId == IntakeFixture.healthId && ($0.day == h.clock.day(-1) || $0.day == h.today)
        })

        // And a quick-add delete never touches the Health id.
        let store = h.quickAdd()
        let entry = try await store.add(proteinGrams: 30, energyKcal: nil, label: nil, at: h.clock.at(0, hour: 10))
        let mid = try await h.rows()
        try await store.delete(id: entry.id, day: h.today)
        let end = try await h.rows()
        XCTAssertEqual(end.filter { $0.deviceId == IntakeFixture.healthId }, mid.filter { $0.deviceId == IntakeFixture.healthId })
    }

    func testIntakeDeletionRemovesOnlyTheNamedDayAndKey() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .appleHealth, suites: suites)
        try await seedIntakeEverywhere(h)
        let before = try await h.rows()
        // Yesterday keeps its energy and loses its protein; the day 45 back is outside the window.
        let energy = h.sample("e1", .energy, h.clock.epoch(-1, hour: 12), 2_400)
        let outcome = await h.healthSync().apply(samples: [energy], firstDay: h.clock.day(-1), lastDay: h.today)
        XCTAssertEqual(outcome, .written(changedDays: [h.clock.day(-1)]))
        let after = try await h.rows()
        let removed = before.subtracting(after)
        XCTAssertEqual(removed, Set([IntakeRow(deviceId: IntakeFixture.healthId, day: h.clock.day(-1), key: "protein_g", value: 120)])
                       .union(before.filter { $0.deviceId == IntakeFixture.healthId && $0.day == h.clock.day(-1)
                                              && $0.key == "intake_read_at" }),
                       "one value row deleted; the read time is rewritten, not dropped")
        XCTAssertNotNil(after.first { $0.deviceId == IntakeFixture.healthId && $0.day == h.clock.day(-1) && $0.key == "intake_read_at" })
        XCTAssertEqual(after.filter { $0.day == h.clock.day(-45) }, before.filter { $0.day == h.clock.day(-45) })
    }

    // MARK: - Flag-off equivalence (§12.5)

    func testWithTheFlagOffConstructingAndReadingTheStageWritesNothing() async throws {
        let h = try await IntakeHarness.make(flag: false, source: nil, floor: 100, zoneLog: false, suites: suites)
        try await h.seedUnrelated()
        let rowsBefore = try await h.rows()
        let defaultsBefore = h.defaults.snapshot()
        let center = SilentCenter()

        let settings = IntakeSettings(defaults: h.defaults)
        let provider = IntakeProvider(repository: h.repo, settings: settings)
        let tick = IntakeSupplementTick(repository: h.repo, settings: settings)
        let reminder = IntakeCutoffReminder(center: center, settings: settings, windDownFireTimes: { [:] })
        _ = h.quickAdd()
        _ = h.healthSync()
        _ = settings.isEnabled
        _ = settings.targets(on: h.today)
        _ = settings.supplementQuestions
        _ = IntakeSettings.coachVisible([], defaults: h.defaults)
        await reminder.reconcileOnActive()
        let states = await tick.states(day: h.today)

        XCTAssertEqual(provider.revision, 0, "no work when nothing asks")
        XCTAssertTrue(states.isEmpty)
        XCTAssertEqual(center.calls, 0, "no call to the notification centre")
        XCTAssertEqual(h.defaults.written, [], "no defaults key written")
        XCTAssertEqual(h.defaults.snapshot(), defaultsBefore)
        let rowsAfter = try await h.rows()
        XCTAssertEqual(rowsAfter, rowsBefore, "no metric series row written")
        let journal = try await h.store.journalEntries(deviceId: Repository.journalDeviceId, from: "0000-01-01", to: "9999-12-31")
        XCTAssertEqual(journal, [], "no Journal row written")
    }

    func testWithTheFlagOffTheProviderResolvesTheCsvSeriesOnly() async throws {
        let h = try await IntakeHarness.make(flag: false, source: .appleHealth, suites: suites)
        try await seedIntakeEverywhere(h)
        try await h.seed(IntakeFixture.csvId, day: h.clock.day(-1), protein: 60)
        await h.provider.refresh()
        XCTAssertEqual(h.provider.series().map(\.day), [h.clock.day(-10), h.clock.day(-1)])
        XCTAssertEqual(h.provider.series().compactMap { $0.protein?.source }, [.nutritionCsv, .nutritionCsv])
        XCTAssertEqual(h.provider.proteinDays(), [CutScorecardProteinDay(day: h.clock.day(-10), grams: 60),
                                                  CutScorecardProteinDay(day: h.clock.day(-1), grams: 60)])
        XCTAssertEqual(h.defaults.written, [])
    }

    // MARK: - Backup (§9.6, §12.2, §12.8)

    private func populatedSuite() throws -> IntakeRecordingDefaults {
        let name = "IntakeBoundaryTests-backup-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(IntakeRecordingDefaults(suiteName: name))
        suites.names.append(name)
        let settings = IntakeSettings(defaults: defaults)
        settings.isEnabled = true
        settings.source = .quickAdd
        XCTAssertTrue(settings.setTargets(IntakeFixture.targets))
        XCTAssertTrue(settings.addSupplementQuestion(IntakeFixture.supplementQuestion))
        settings.zoneLog = [IntakeZoneSegment(fromEpochSeconds: 0, zoneIdentifier: "Etc/UTC")]
        settings.admittedHealthSources = [IntakeFixture.foodApp.bundleId]
        settings.recordHealthSource(bundleId: IntakeFixture.foodApp.bundleId, name: IntakeFixture.foodApp.name, day: "2031-01-29")
        settings.recordHealthSource(bundleId: IntakeFixture.otherApp.bundleId, name: IntakeFixture.otherApp.name, day: "2031-01-29")
        settings.healthBackfilled = true
        settings.cutoffEnabled = true
        settings.cutoffMinuteOfDay = IntakeFixture.cutoffMinute
        settings.cutoffTimeSet = true
        settings.quickAddPresets = [IntakeSettings.Preset(label: IntakeFixture.preset.label, proteinGrams: 30, energyKcal: 150)]
        defaults.set(#"[{"id":"00000000-0000-0000-0000-000000000001","label":"Fixture shake","day":"2031-01-29"}]"#,
                     forKey: IntakeSettings.entriesKeyPrefix + "2031-01-29")
        return defaults
    }

    func testIntakeTargetsAndSupplementQuestionsRoundTrip() throws {
        let source = try populatedSuite()
        let data = try XCTUnwrap(BackupSettings.encode(BackupSettings.snapshot(from: source)))
        let values = BackupSettings.decode(data)
        XCTAssertEqual(values["intake.targets"] as? String, source.string(forKey: IntakeSettings.targetsKey))
        XCTAssertEqual(values["intake.supplement.questions"] as? String,
                       source.string(forKey: IntakeSettings.supplementQuestionsKey))

        let name = "IntakeBoundaryTests-restore-\(UUID().uuidString)"
        let target = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.names.append(name)
        BackupSettings.apply(values, to: target)
        let restored = IntakeSettings(defaults: target)
        XCTAssertEqual(restored.storedTargets, IntakeFixture.targets)
        XCTAssertEqual(restored.supplementQuestions, [IntakeFixture.supplementQuestion])
    }

    func testIntakeFlagSourceAndCutoffAreNotCarried() throws {
        let source = try populatedSuite()
        let values = BackupSettings.snapshot(from: source)
        for key in ["noop.intakeEnabled", "intake.source", "intake.zoneLog", "intake.health.sources",
                    "intake.health.knownSources", "intake.health.backfilled", "intake.cutoff.enabled",
                    "intake.cutoff.minuteOfDay", "intake.cutoff.timeSet", "intake.quickAdd.presets",
                    "intake.entries.2031-01-29"] {
            XCTAssertNil(values[key], "\(key) is per install and never carried")
        }
        XCTAssertNil(BackupSettings.whitelist["noop.intakeEnabled"])
    }

    func testBackupSettingsCarryNoEntryLabelsOrSourceIds() throws {
        let source = try populatedSuite()
        let data = BackupSettings.encode(BackupSettings.snapshot(from: source)) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        for forbidden in [IntakeFixture.preset.label, IntakeFixture.foodApp.bundleId, IntakeFixture.foodApp.name,
                          IntakeFixture.otherApp.bundleId, IntakeFixture.otherApp.name, "noop-intake", "lastSeenDay",
                          "Etc/UTC"] {
            XCTAssertFalse(text.contains(forbidden), "\(forbidden) reached settings.json: \(text)")
        }
    }
}
