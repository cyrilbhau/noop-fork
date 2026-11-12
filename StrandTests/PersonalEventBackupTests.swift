// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md §9.4 and §12.3 before the implementation
// exists. The change under test is two entries in Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift
// (orchestrator's commit 5-7h):
//
//     BackupSettings.whitelist["personalEvents.items"] == .string
//     BackupSettings.appleDefaultsKey["personalEvents.items"] == "personalEvents.items"
//
// and no entry for `noop.personalEventsEnabled`. Existing API used unchanged:
// `BackupSettings.snapshot(from:)` (the export-side read the app's `currentSettingsJSON()` makes of
// `.standard`), `DataBackup.writeBackupForTesting(databaseAt:to:settings:)` and
// `DataBackup.restore(from:toDatabaseAt:settingsDefaults:)`. `PersonalEventStore` as declared in
// PersonalEventStoreTests.swift.
//
// Behaviour assumed: the stored string crosses the backup unparsed, so the restored value is the
// same bytes, unreadable entries and private events included. Every database and defaults domain
// here is a throwaway: the runner's own domain and database are never touched.

import XCTest
import SQLite3
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class PersonalEventBackupTests: XCTestCase {

    private typealias Fx = PersonalEventAppFixture

    private var tmp: URL!
    private var suites: [String] = []

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("personal-events-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
    }

    private func suite() throws -> UserDefaults {
        let name = "PersonalEventBackupTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        return defaults
    }

    /// A minimal GRDB-origin database (it carries `grdb_migrations`), so the restore accepts it.
    private func makeDatabase(_ name: String) throws -> URL {
        let url = tmp.appendingPathComponent(name)
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw NSError(domain: "fixture", code: 1) }
        defer { sqlite3_close(db) }
        for sql in ["CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)",
                    "INSERT INTO grdb_migrations (identifier) VALUES ('v1')",
                    "CREATE TABLE device (id TEXT NOT NULL PRIMARY KEY)",
                    "INSERT INTO device (id) VALUES ('my-whoop')"] {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw NSError(domain: "fixture", code: 2) }
        }
        return url
    }

    func testEventsSurviveAFullExportAndRestoreThroughDataBackup() throws {
        // This device: the eight fixture events (two private, one with a note) and one unreadable entry.
        let source = try suite()
        source.set(true, forKey: PersonalEventStore.enabledKey)
        let text = Fx.stored(Fx.allNormalized, extra: [Fx.unknownKindElement])
        source.set(text, forKey: PersonalEventStore.itemsKey)

        let snapshot = BackupSettings.snapshot(from: source)
        XCTAssertEqual(snapshot["personalEvents.items"] as? String, text, "the list is carried as one string")
        XCTAssertNil(snapshot["noop.personalEventsEnabled"], "the flag is per install")

        let backup = tmp.appendingPathComponent("events.noopbak")
        try DataBackup.writeBackupForTesting(databaseAt: try makeDatabase("source.sqlite"), to: backup, settings: snapshot)

        // Another install, with its own different list and the feature off.
        let target = try suite()
        target.set(Fx.stored([Fx.e2]), forKey: PersonalEventStore.itemsKey)
        let live = try makeDatabase("live.sqlite")
        let result = DataBackup.restore(from: backup, toDatabaseAt: live.path, settingsDefaults: target)
        guard case .imported = result else { return XCTFail("the restore should succeed, got \(result)") }

        XCTAssertEqual(target.object(forKey: PersonalEventStore.itemsKey) as? String, text,
                       "byte-identical: private events, notes and the unreadable entry included")
        XCTAssertNil(target.object(forKey: PersonalEventStore.enabledKey), "the feature stays off until switched on")

        let restored = PersonalEventStore(defaults: target)
        XCTAssertEqual(restored.events, [], "off after the restore")
        target.set(true, forKey: PersonalEventStore.enabledKey)
        XCTAssertEqual(restored.events, Fx.allNormalized, "and the events are there when it is switched on")
        XCTAssertEqual(restored.unreadableEntryCount, 1)
    }

    func testABackupWithoutTheListLeavesThisDevicesEventsAlone() throws {
        let backup = tmp.appendingPathComponent("no-events.noopbak")
        try DataBackup.writeBackupForTesting(databaseAt: try makeDatabase("source.sqlite"), to: backup,
                                             settings: ["units.system": "metric"])
        let target = try suite()
        let text = Fx.stored(Fx.allNormalized)
        target.set(text, forKey: PersonalEventStore.itemsKey)
        let result = DataBackup.restore(from: backup, toDatabaseAt: try makeDatabase("live.sqlite").path,
                                        settingsDefaults: target)
        guard case .imported = result else { return XCTFail("the restore should succeed, got \(result)") }
        XCTAssertEqual(target.object(forKey: PersonalEventStore.itemsKey) as? String, text)
    }
}
