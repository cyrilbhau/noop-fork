// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md §9.5 (ruling R42) and §12.3 before the
// implementation exists. New: `PersonalEventStore` (API block in PersonalEventStoreTests.swift),
// over the runner's standard defaults here, because that is where the app keeps the list and where a
// strap operation would have to reach to lose it. The two stage 5 keys are saved before each test and
// restored after it.
//
// Existing API used unchanged: `DeviceRegistry.init(store:)`, `reload()`, `deleteDeviceData(_:store:)`,
// `forget(_:store:)`, `setActive(_:)`, `archive(_:)`, `adoptSerialIdentity(from:to:)`;
// `WhoopStore.inMemory()`, `WhoopStore(path:)`, `checkpointWAL()`, `deleteAllData(deviceId:)`,
// `upsertMetricSeries(_:deviceId:)`, `metricSeries(deviceId:key:from:to:)`; and the stage 1b registry
// fixture `LabBookOwnershipAppFixture` (strap ids B, D, N and the serial id; none owns a raw IMU file).
//
// Behaviour assumed: the store holds no device id and no database handle, so no strap operation and
// no database write reaches it; a store built after the operation reads the same list.

import XCTest
import SQLite3
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class PersonalEventOwnershipTests: XCTestCase {

    private typealias Fx = PersonalEventAppFixture
    private typealias LB = LabBookOwnershipAppFixture

    private var standardKeys: PersonalEventStandardKeys?
    private var tmp: URL?

    override func setUp() {
        super.setUp()
        standardKeys = PersonalEventStandardKeys()
        UserDefaults.standard.set(true, forKey: PersonalEventStore.enabledKey)
        UserDefaults.standard.set(Fx.stored(Fx.allNormalized, extra: [Fx.unknownKindElement]),
                                  forKey: PersonalEventStore.itemsKey)
    }

    override func tearDown() {
        standardKeys?.restore()
        standardKeys = nil
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
        tmp = nil
        super.tearDown()
    }

    // MARK: Helpers

    private var storedText: String? {
        UserDefaults.standard.object(forKey: PersonalEventStore.itemsKey) as? String
    }

    private func assertEveryEventKept(_ stage: String, _ text: String?,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(storedText, text, "\(stage): the stored string is byte-identical", file: file, line: line)
        let store = PersonalEventStore(defaults: .standard)
        XCTAssertEqual(store.events, Fx.allNormalized, "\(stage): every event is read", file: file, line: line)
        XCTAssertEqual(store.unreadableEntryCount, 1, "\(stage): the unreadable entry is kept", file: file, line: line)
        XCTAssertEqual(PersonalEventStore.shared.events, Fx.allNormalized, "\(stage): the shared store",
                       file: file, line: line)
    }

    private func seedStrapSeries(_ store: WhoopStore, _ id: String) async throws {
        try await store.upsertMetricSeries([MetricPoint(day: "2031-03-10", key: "fixture_strap_series", value: 1)],
                                           deviceId: id)
    }

    private func strapSeriesCount(_ store: WhoopStore, _ id: String) async throws -> Int {
        try await store.metricSeries(deviceId: id, key: "fixture_strap_series", from: "0000-01-01", to: "9999-12-31").count
    }

    // MARK: R42

    func testDeletingAStrapsDataLeavesEveryEvent() async throws {
        let text = storedText
        assertEveryEventKept("before", text)
        let store = try await LB.emptyStoreWithRegistry()
        let registry = DeviceRegistry(store: LB.registry(store))
        registry.reload()
        for id in [LB.b, LB.d, LB.n] { try await seedStrapSeries(store, id) }

        for id in [LB.b, LB.d, LB.n] {
            await registry.deleteDeviceData(id, store: store)
            let left = try await strapSeriesCount(store, id)
            XCTAssertEqual(left, 0, "the delete ran for \(id)")
            assertEveryEventKept("after Delete data on \(id)", text)
        }
        try await store.deleteAllData(deviceId: LB.n)
        assertEveryEventKept("after the store's own delete", text)
    }

    func testForgettingAStrapAndRepointingTheActiveIdLeavesEveryEvent() async throws {
        let text = storedText
        let store = try await LB.emptyStoreWithRegistry()
        let registry = DeviceRegistry(store: LB.registry(store))
        registry.reload()

        registry.setActive(LB.d)
        assertEveryEventKept("after re-pointing the active id", text)
        registry.archive(LB.d)
        assertEveryEventKept("after archiving", text)
        registry.setActive(LB.n)
        _ = registry.adoptSerialIdentity(from: LB.n, to: LB.serial)
        assertEveryEventKept("after adopting a serial identity", text)
        await registry.forget(LB.b, store: store)
        XCTAssertFalse(registry.devices.contains { $0.id == LB.b }, "the forget ran")
        assertEveryEventKept("after forgetting a strap", text)
        await registry.forget(LB.d, store: store)
        assertEveryEventKept("after forgetting the ring", text)
    }

    func testNoEventIsStoredInTheDatabase() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("personal-events-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmp = dir
        let path = dir.appendingPathComponent("store.sqlite").path
        let database = try await WhoopStore(path: path)
        try await seedStrapSeries(database, "my-whoop")
        try await database.checkpointWAL()
        let before = try rowCounts(path)
        XCTAssertFalse(before.isEmpty)

        let store = PersonalEventStore(defaults: .standard, now: { Date(timeIntervalSince1970: 1_930_000_000) })
        let added = try store.add(kind: .custom, label: "Fixture change", startDay: "2031-03-27", endDay: nil,
                                  note: "Fixture note", sensitive: true)
        try store.update(Fx.make(Fx.id(1), .travel, "2031-03-10", "2031-03-17", note: "Fixture trip", createdAt: 1000))
        try store.delete(id: Fx.id(8))
        try store.delete(id: added.id)
        try await database.checkpointWAL()

        XCTAssertEqual(try rowCounts(path), before, "no table gains or loses a row from an event write")
        XCTAssertFalse(try databaseText(path).contains("Fixture change"), "no event text reaches the database")
    }

    // MARK: SQLite, read-only

    private func rowCounts(_ path: String) throws -> [String: Int] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw NSError(domain: "PersonalEventOwnershipTests", code: 1)
        }
        defer { sqlite3_close(db) }
        var tables: [String] = []
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type = 'table'", -1, &statement, nil)
        while sqlite3_step(statement) == SQLITE_ROW {
            tables.append(String(cString: sqlite3_column_text(statement, 0)))
        }
        sqlite3_finalize(statement)
        var counts: [String: Int] = [:]
        for table in tables {
            var count: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \"\(table)\"", -1, &count, nil)
            if sqlite3_step(count) == SQLITE_ROW { counts[table] = Int(sqlite3_column_int64(count, 0)) }
            sqlite3_finalize(count)
        }
        return counts
    }

    private func databaseText(_ path: String) throws -> String {
        var text = ""
        for suffix in ["", "-wal"] where FileManager.default.fileExists(atPath: path + suffix) {
            let data = try Data(contentsOf: URL(fileURLWithPath: path + suffix))
            text += String(decoding: data, as: UTF8.self)
        }
        return text
    }
}
