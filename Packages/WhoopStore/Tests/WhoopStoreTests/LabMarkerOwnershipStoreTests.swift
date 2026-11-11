import Foundation
import GRDB
import XCTest
@testable import WhoopStore

// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/labbook-ownership.md §6.1.
//
// Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift:
//
//   static let DeviceRegistryStore.deviceScopedTables: [String]                 (exists, unchanged)
//   static let DeviceRegistryStore.ownerEnteredTables: Set<String>              (new; ["labMarker"])
//   static var DeviceRegistryStore.strapScopedTables: [String] { get }          (new)
//   public func DeviceRegistryStore.deleteAllData(deviceId: String) throws      (exists; new behaviour)
//   public func DeviceRegistryStore.adoptSerialIdentity(from activeId: String, to serialId: String) throws -> Bool
//                                                                               (exists; new behaviour)
//   public func DeviceRegistryStore.remove(_ id: String) throws                 (exists, unchanged)
//   public func DeviceRegistryStore.archive(_ id: String) throws                (exists, unchanged)
//   public func WhoopStore.deleteAllData(deviceId: String) async throws         (exists; new behaviour)
//
// Packages/WhoopStore/Sources/WhoopStore/LabMarkerOwnership.swift (new):
//
//   public func WhoopStore.allLabMarkers() async throws -> [LabMarkerRow]
//   public func WhoopStore.allLabMarkers(category: String) async throws -> [LabMarkerRow]
//   public func WhoopStore.allLabMarkers(markerKey: String) async throws -> [LabMarkerRow]
//   public func WhoopStore.labMarkerDeviceIds() async throws -> [String]
//   @discardableResult public func WhoopStore.upsertOwnerLabMarkers(_ rows: [LabMarkerRow]) async throws -> Int
//   @discardableResult public func WhoopStore.deleteLabMarkerAndCopies(id: String) async throws -> [String]
//   public enum LabMarkerUnion { static func merged(_:activeDeviceId:), isCopy(_:_:) }   (see LabMarkerUnionTests)
//
// Packages/WhoopStore/Sources/WhoopStore/LabMarkerStore.swift, module-internal, reached through
// `@testable import` in tests 80 and 82 only:
//
//   struct WhoopStore.LabBookDayCell: Hashable { let markerKey: String; let day: String }
//   func WhoopStore.ownerUpsert(_ db: Database, rows: [LabMarkerRow]) throws
//       -> (written: Int, touched: Set<LabBookDayCell>)
//   func WhoopStore.deleteWithCopies(_ db: Database, id: String) throws
//       -> (deleted: [String], touched: Set<LabBookDayCell>)
//   func WhoopStore.reprojectCells(_ db: Database, cells: Set<LabBookDayCell>) throws
//   func WhoopStore.syncWrite<T>(_ block: (Database) throws -> T) throws -> T    (exists)
//
// Existing per-id functions, whose signatures stay and whose projection step becomes all-id (§7.2):
//
//   public func WhoopStore.upsertLabMarkers(_ rows: [LabMarkerRow]) async throws -> Int
//   public func WhoopStore.deleteLabMarker(id: String) async throws -> Bool
//   public func WhoopStore.labMarkers(deviceId: String, category: String) async throws -> [LabMarkerRow]
//   public func WhoopStore.labMarkers(deviceId: String, markerKey: String) async throws -> [LabMarkerRow]
//   public init WhoopStore(path: String) async throws, public func WhoopStore.checkpointWAL() async throws
//
// Specification §12.2 (cases 16 to 25, 27 to 43, 80, 82), §12.5 (case 72), §12.8 and §13.
//
// Cases 16 to 25 are placed here and not in DeviceRegistryStoreTests.swift, where §12.2 and §14 put
// them: this work package was told to create new files only and to edit no existing file.
//
// Every test asserts the per-id row counts before and after each operation it performs.
// Synthetic values only.

/// Thrown on purpose inside a transaction, to prove a rollback.
private struct LabBookOwnershipInjectedFailure: Error {}

/// Every `metricSeries` row, read inside the transaction that is being observed.
private func labBookOwnershipSeriesSnapshot(_ db: Database) throws -> [LabBookOwnershipFixture.Cell] {
    try Row.fetchAll(db, sql: """
        SELECT deviceId, key, day, value FROM metricSeries ORDER BY deviceId ASC, key ASC, day ASC
        """).map {
            LabBookOwnershipFixture.Cell(deviceId: $0["deviceId"], key: $0["key"], day: $0["day"], value: $0["value"])
        }
}

/// What one composed transaction did, in plain values that can leave the actor.
private struct LabBookOwnershipTrace {
    var firstDeleted: [String] = []
    var firstTouched: [String] = []
    var secondDeleted: [String] = []
    var secondTouched: [String] = []
    var written = 0
    var upsertTouched: [String] = []
    var seriesAfterDeletes: [LabBookOwnershipFixture.Cell] = []
    var seriesAfterUpsert: [LabBookOwnershipFixture.Cell] = []
    var rowCountBeforeProjection = 0
}

private extension WhoopStore {
    /// The composition stage 4's `replaceLabMarkers` will make (§6.3): inside one `syncWrite`,
    /// `deleteWithCopies`, then `ownerUpsert`, then one `reprojectCells` over both touched sets.
    func labBookOwnershipDeleteThenUpsert(deleteId: String, rows: [LabMarkerRow],
                                          failAfterDelete: Bool) throws -> LabBookOwnershipTrace {
        try syncWrite { db in
            var trace = LabBookOwnershipTrace()
            let removed = try deleteWithCopies(db, id: deleteId)
            trace.firstDeleted = removed.deleted
            trace.firstTouched = removed.touched.map { "\($0.markerKey)|\($0.day)" }.sorted()
            trace.seriesAfterDeletes = try labBookOwnershipSeriesSnapshot(db)
            if failAfterDelete { throw LabBookOwnershipInjectedFailure() }
            let upserted = try ownerUpsert(db, rows: rows)
            trace.written = upserted.written
            trace.upsertTouched = upserted.touched.map { "\($0.markerKey)|\($0.day)" }.sorted()
            trace.seriesAfterUpsert = try labBookOwnershipSeriesSnapshot(db)
            trace.rowCountBeforeProjection = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM labMarker") ?? -1
            try reprojectCells(db, cells: removed.touched.union(upserted.touched))
            return trace
        }
    }

    /// Two `deleteWithCopies` calls in one `syncWrite`, then one `reprojectCells`.
    func labBookOwnershipDeleteTwice(first: String, second: String) throws -> LabBookOwnershipTrace {
        try syncWrite { db in
            var trace = LabBookOwnershipTrace()
            let one = try deleteWithCopies(db, id: first)
            trace.firstDeleted = one.deleted
            trace.firstTouched = one.touched.map { "\($0.markerKey)|\($0.day)" }.sorted()
            let two = try deleteWithCopies(db, id: second)
            trace.secondDeleted = two.deleted
            trace.secondTouched = two.touched.map { "\($0.markerKey)|\($0.day)" }.sorted()
            trace.seriesAfterDeletes = try labBookOwnershipSeriesSnapshot(db)
            trace.rowCountBeforeProjection = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM labMarker") ?? -1
            try reprojectCells(db, cells: one.touched.union(two.touched))
            return trace
        }
    }

    /// `ownerUpsert` of an empty list, observed inside a transaction.
    func labBookOwnershipUpsertNothing() throws -> LabBookOwnershipTrace {
        try syncWrite { db in
            var trace = LabBookOwnershipTrace()
            let upserted = try ownerUpsert(db, rows: [])
            trace.written = upserted.written
            trace.upsertTouched = upserted.touched.map { "\($0.markerKey)|\($0.day)" }.sorted()
            return trace
        }
    }
}

final class LabMarkerOwnershipStoreTests: XCTestCase {

    private typealias Fx = LabBookOwnershipFixture

    // MARK: - Helpers

    private func registry(_ store: WhoopStore) -> DeviceRegistryStore {
        DeviceRegistryStore(dbQueue: store.registryWriter)
    }

    /// The strap tables, derived here from the existing list so that the expectation does not come
    /// from the declaration under test.
    private var expectedStrapTables: [String] {
        DeviceRegistryStore.deviceScopedTables.filter { $0 != "labMarker" }
    }

    /// A draft as the Lab Book screen builds it: a freshly minted id and the active device id.
    private func draft(_ base: LabMarkerRow, id: String, _ change: (inout LabMarkerRow) -> Void = { _ in })
        -> LabMarkerRow {
        var row = base
        row.id = id
        row.deviceId = Fx.n
        change(&row)
        return row
    }

    private func count(_ store: WhoopStore, _ table: String, _ deviceId: String) throws -> Int {
        try store.registryWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE deviceId = ?", arguments: [deviceId]) ?? 0
        }
    }

    private func insertHeartRate(_ store: WhoopStore, _ deviceId: String, ts: Int, bpm: Int) throws {
        try store.registryWriter.write { db in
            try db.execute(sql: "INSERT INTO hrSample (deviceId, ts, bpm) VALUES (?, ?, ?)",
                           arguments: [deviceId, ts, bpm])
        }
    }

    private func heartRate(_ store: WhoopStore, _ deviceId: String, ts: Int) throws -> Int? {
        try store.registryWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT bpm FROM hrSample WHERE deviceId = ? AND ts = ?",
                             arguments: [deviceId, ts])
        }
    }

    /// One row in each named table for `deviceId`, built from the live schema: the device id column
    /// takes `deviceId`, every other column a value of its declared type made from `ordinal`, so two
    /// devices never collide on a key.
    private func seedOneRowPerTable(_ tables: [String], deviceId: String, ordinal: Int,
                                    in store: WhoopStore) throws {
        try store.registryWriter.write { db in
            for table in tables {
                var names: [String] = []
                var values: [DatabaseValueConvertible?] = []
                for column in try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))") {
                    let name: String = column["name"]
                    let type = ((column["type"] as String?) ?? "").uppercased()
                    names.append("\"\(name)\"")
                    if name == "deviceId" {
                        values.append(deviceId)
                    } else if type.contains("INT") {
                        values.append(ordinal)
                    } else if type.contains("REAL") || type.contains("DOUB") || type.contains("FLOA")
                                || type.contains("NUM") {
                        values.append(Double(ordinal))
                    } else if type.contains("BLOB") {
                        values.append(Data([UInt8(ordinal)]))
                    } else if type.contains("BOOL") {
                        values.append(1)
                    } else {
                        values.append("fixture-\(ordinal)")
                    }
                }
                let marks = Array(repeating: "?", count: names.count).joined(separator: ", ")
                try db.execute(sql: "INSERT INTO \(table) (\(names.joined(separator: ", "))) VALUES (\(marks))",
                               arguments: StatementArguments(values))
            }
        }
    }

    // MARK: - Strap operations (§12.2 cases 16 to 25)

    /// Protects ruling R42: "Delete data" on a strap leaves every Lab Book reading entered while that
    /// strap was active, byte for byte (faults F1, F3). Run for an archived strap, the active strap, a
    /// strap with no registry row, the legacy id and an other-brand id, through both entry points.
    func testDeleteAllDataLeavesEveryLabMarkerRowOfThatDevice() async throws {
        let store = try await Fx.seededStore()
        let before = try Fx.storageDump(store)
        XCTAssertEqual(before.count, 10)
        try Fx.assertCounts(store, Fx.countsById, "before any delete")

        for deviceId in [Fx.b, Fx.n, Fx.c, Fx.a, Fx.d] {
            try registry(store).deleteAllData(deviceId: deviceId)
            try Fx.assertCounts(store, Fx.countsById, "after deleteAllData(\(deviceId))")
            XCTAssertEqual(try Fx.storageDump(store), before, "after deleteAllData(\(deviceId))")
        }
        for deviceId in [Fx.b, Fx.n] {
            try await store.deleteAllData(deviceId: deviceId)
            try Fx.assertCounts(store, Fx.countsById, "after the store's deleteAllData(\(deviceId))")
            XCTAssertEqual(try Fx.storageDump(store), before, "after the store's deleteAllData(\(deviceId))")
        }
        let listed = try await store.allLabMarkers()
        XCTAssertEqual(listed, Fx.storedOrder, "and every reading is still read")
    }

    /// Protects the §13 sequence, which is "Forget device" at store level: `deleteAllData` on B, then
    /// on N, then `remove` of B. All ten rows are byte-identical after each step.
    func testForgetSequenceOfDeleteAllDataThenRemoveLeavesAllTenRowsByteIdentical() async throws {
        let store = try await Fx.seededStore()
        let before = try Fx.storageDump(store)
        try Fx.assertCounts(store, Fx.countsById, "before")

        try registry(store).deleteAllData(deviceId: Fx.b)
        try Fx.assertCounts(store, Fx.countsById, "after deleteAllData(B)")
        XCTAssertEqual(try Fx.storageDump(store), before)

        try registry(store).deleteAllData(deviceId: Fx.n)
        try Fx.assertCounts(store, Fx.countsById, "after deleteAllData(N)")
        XCTAssertEqual(try Fx.storageDump(store), before)

        try registry(store).remove(Fx.b)
        try Fx.assertCounts(store, Fx.countsById, "after remove(B)")
        XCTAssertEqual(try Fx.storageDump(store), before)
        XCTAssertFalse(try Fx.registryIds(store).contains(Fx.b), "B's registry row is gone")

        // B is now an id with no registry row, like C. Its three readings are still read.
        let underB = try await store.allLabMarkers().filter { $0.deviceId == Fx.b }
        XCTAssertEqual(underB, [Fx.f6, Fx.f2, Fx.f9])
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells)
    }

    /// Protects: a strap delete still removes everything the strap recorded (fault F4). One row is
    /// seeded in every strap table for the target and for a bystander; the target's are all gone, the
    /// bystander's all stay.
    func testDeleteAllDataStillClearsEveryStrapScopedTableOfThatDevice() async throws {
        let store = try await Fx.seededStore()
        let tables = expectedStrapTables
        XCTAssertFalse(tables.isEmpty)
        XCTAssertFalse(tables.contains("labMarker"))
        try seedOneRowPerTable(tables, deviceId: Fx.b, ordinal: 1, in: store)
        try seedOneRowPerTable(tables, deviceId: Fx.d, ordinal: 2, in: store)
        for table in tables {
            XCTAssertEqual(try count(store, table, Fx.b), 1, "\(table) seeded for B")
            XCTAssertEqual(try count(store, table, Fx.d), 1, "\(table) seeded for D")
        }
        try Fx.assertCounts(store, Fx.countsById, "before")
        let before = try Fx.storageDump(store)

        try registry(store).deleteAllData(deviceId: Fx.b)

        for table in tables {
            XCTAssertEqual(try count(store, table, Fx.b), 0, "\(table) must be cleared for B")
            XCTAssertEqual(try count(store, table, Fx.d), 1, "\(table) must be left alone for D")
        }
        try Fx.assertCounts(store, Fx.countsById, "after")
        XCTAssertEqual(try Fx.storageDump(store), before)
    }

    /// Protects: a strap delete issues no statement against the `lab-book` projection (§7.4).
    func testDeleteAllDataLeavesTheLabBookProjectionUntouched() async throws {
        let store = try await Fx.seededStore()
        // A strap's own series on the same key and day, to prove the delete tells the two apart.
        try Fx.setCell(Fx.Cell(deviceId: Fx.b, key: "weight", day: Fx.day2, value: 97.5), in: store)
        try Fx.assertCounts(store, Fx.countsById, "before")

        for deviceId in [Fx.b, Fx.n, Fx.c] {
            try registry(store).deleteAllData(deviceId: deviceId)
            XCTAssertEqual(try Fx.labBookCells(store), Fx.cells, "after deleteAllData(\(deviceId))")
            try Fx.assertCounts(store, Fx.countsById, "after deleteAllData(\(deviceId))")
        }
        XCTAssertEqual(try Fx.allSeries(store), Fx.cells, "B's own series row is gone, the six cells are not")
    }

    /// Protects: an owner-entered table is still a device-keyed table, so the schema-coverage test
    /// keeps covering it.
    func testOwnerEnteredTablesAreASubsetOfDeviceScopedTables() {
        XCTAssertFalse(DeviceRegistryStore.ownerEnteredTables.isEmpty)
        XCTAssertTrue(DeviceRegistryStore.ownerEnteredTables.isSubset(of: Set(DeviceRegistryStore.deviceScopedTables)))
    }

    /// Protects: the list a strap delete and an adoption iterate is the device-keyed list without the
    /// owner's tables, in the same order, with nothing else removed or added.
    func testStrapScopedTablesIsDeviceScopedTablesWithoutOwnerEnteredTablesInOrder() {
        let expected = DeviceRegistryStore.deviceScopedTables.filter {
            !DeviceRegistryStore.ownerEnteredTables.contains($0)
        }
        XCTAssertEqual(DeviceRegistryStore.strapScopedTables, expected)
        XCTAssertEqual(DeviceRegistryStore.strapScopedTables, expectedStrapTables)
        XCTAssertEqual(DeviceRegistryStore.strapScopedTables.count, DeviceRegistryStore.deviceScopedTables.count - 1)
        XCTAssertFalse(DeviceRegistryStore.strapScopedTables.contains("labMarker"))
        XCTAssertEqual(Set(DeviceRegistryStore.strapScopedTables).count, DeviceRegistryStore.strapScopedTables.count,
                       "no table twice")
        // The strap tables this change must not exempt (§4.4, decision D10).
        for table in ["hrSample", "metricSeries", "workout", "journal", "liftSession", "liftSet", "sleepSession"] {
            XCTAssertTrue(DeviceRegistryStore.strapScopedTables.contains(table), "\(table) stays strap-scoped")
        }
    }

    /// Protects: `labMarker` is the owner's, and it is the only table this change exempts (faults F3
    /// and F4).
    func testLabMarkerIsOwnerEntered() {
        XCTAssertTrue(DeviceRegistryStore.ownerEnteredTables.contains("labMarker"))
        XCTAssertEqual(DeviceRegistryStore.ownerEnteredTables, ["labMarker"])
    }

    /// Protects decision D7: an adoption does not move Lab Book readings. The rows written under the
    /// provisional id stay under it, and under its computed sibling id (fault F2).
    func testAdoptSerialLeavesLabMarkerRowsUnderTheProvisionalId() async throws {
        let store = try await Fx.seededStore()
        let sibling = Fx.n + DeviceRegistryStore.computedSuffix
        let underSibling = Fx.row(id: "weight-1927436400-F0000011", deviceId: sibling, markerKey: "weight",
                                  category: "bodyMeasurement", day: Fx.day4, takenAt: Fx.t4, value: 97.6, unit: "kg")
        try Fx.insertRaw([underSibling], into: store)
        var counts = Fx.countsById
        counts[sibling] = 1
        try Fx.assertCounts(store, counts, "before")
        let before = try Fx.storageDump(store)

        let adopted = try registry(store).adoptSerialIdentity(from: Fx.n, to: Fx.serial)

        XCTAssertTrue(adopted)
        try Fx.assertCounts(store, counts, "after: nothing under the serial id, three still under N")
        XCTAssertEqual(try Fx.storageDump(store), before)
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells)
        // N has no registry row any more (§8.7); its readings are read all the same.
        XCTAssertEqual(try Fx.registryIds(store), [Fx.a, Fx.d, Fx.b, Fx.serial])
        let listed = try await store.allLabMarkers()
        XCTAssertEqual(listed.count, 11)
        XCTAssertEqual(listed.filter { $0.deviceId == Fx.n }, [Fx.f7, Fx.f8, Fx.f4])
    }

    /// Protects the dropped-row case (§2 row 3, fault F2): the serial id already holds a row with the
    /// natural key of a row under the provisional id. `UPDATE OR IGNORE` then `DELETE` removed the
    /// provisional id's row. Both stay, whether the two are a conflict or copies.
    func testAdoptSerialWithAClashingLabMarkerUnderTheSerialIdKeepsBothRows() async throws {
        let store = try await Fx.seededStore()
        try registry(store).add(PairedDevice(id: Fx.serial, brand: "WHOOP", model: "WHOOP 4.0", sourceKind: .liveBLE,
                                             capabilities: [.hr], status: .paired, addedAt: 1, lastSeenAt: 1))
        // The natural key of F8 (weight, t3, manual) with another value: a conflict.
        let conflict = Fx.row(id: "weight-1926831600-F0000011", deviceId: Fx.serial, markerKey: "weight",
                              category: "bodyMeasurement", day: Fx.day3, takenAt: Fx.t3, value: 98.2, unit: "kg")
        // The natural key and the content of F7: a copy.
        var copy = Fx.f7
        copy.id = "ldl-1926226800-F0000012"
        copy.deviceId = Fx.serial
        try Fx.insertRaw([conflict, copy], into: store)
        var counts = Fx.countsById
        counts[Fx.serial] = 2
        try Fx.assertCounts(store, counts, "before")
        let before = try Fx.storageDump(store)
        XCTAssertEqual(before.count, 12)

        let adopted = try registry(store).adoptSerialIdentity(from: Fx.n, to: Fx.serial)

        XCTAssertTrue(adopted)
        try Fx.assertCounts(store, counts, "after: F4, F7 and F8 are still under N")
        XCTAssertEqual(try Fx.storageDump(store), before, "all twelve rows byte-identical")
        let weightAtT3 = try await store.allLabMarkers(markerKey: "weight").filter { $0.takenAt == Fx.t3 }
        XCTAssertEqual(weightAtT3, [Fx.f3, Fx.f8, conflict], "three readings at the instant, all stored")
    }

    /// Protects existing behaviour (fault F4): an adoption still moves what the strap recorded, the
    /// computed sibling included, and for strap tables the target id's row still wins a clash.
    func testAdoptSerialStillMovesStrapRowsAndTheComputedSibling() async throws {
        let store = try await Fx.seededStore()
        try registry(store).add(PairedDevice(id: Fx.serial, brand: "WHOOP", model: "WHOOP 4.0", sourceKind: .liveBLE,
                                             capabilities: [.hr], status: .paired, addedAt: 1, lastSeenAt: 1))
        let nSibling = Fx.n + DeviceRegistryStore.computedSuffix
        let sSibling = Fx.serial + DeviceRegistryStore.computedSuffix
        try insertHeartRate(store, Fx.n, ts: 10, bpm: 55)
        try insertHeartRate(store, Fx.n, ts: 20, bpm: 56)
        try insertHeartRate(store, Fx.serial, ts: 20, bpm: 60)
        try insertHeartRate(store, nSibling, ts: 30, bpm: 57)
        try Fx.setCell(Fx.Cell(deviceId: nSibling, key: "steps", day: Fx.day1, value: 97.5), in: store)
        try Fx.assertCounts(store, Fx.countsById, "before")
        let before = try Fx.storageDump(store)

        XCTAssertTrue(try registry(store).adoptSerialIdentity(from: Fx.n, to: Fx.serial))

        XCTAssertEqual(try count(store, "hrSample", Fx.n), 0)
        XCTAssertEqual(try count(store, "hrSample", Fx.serial), 2, "ts 10 moved; ts 20 clashed and the serial id's row won")
        XCTAssertEqual(try heartRate(store, Fx.serial, ts: 20), 60)
        XCTAssertEqual(try count(store, "hrSample", nSibling), 0)
        XCTAssertEqual(try count(store, "hrSample", sSibling), 1, "the computed sibling travels with the pairing")
        XCTAssertEqual(try count(store, "metricSeries", nSibling), 0)
        XCTAssertEqual(try count(store, "metricSeries", sSibling), 1)
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells, "the lab-book cells are not a strap's series")
        try Fx.assertCounts(store, Fx.countsById, "after")
        XCTAssertEqual(try Fx.storageDump(store), before)
    }

    /// Protects: removing or archiving a registry row never touches a reading.
    func testRemoveRegistryRowLeavesLabMarkerRows() async throws {
        let store = try await Fx.seededStore()
        let before = try Fx.storageDump(store)
        try Fx.assertCounts(store, Fx.countsById, "before")

        try registry(store).archive(Fx.n)
        try Fx.assertCounts(store, Fx.countsById, "after archive(N)")
        XCTAssertEqual(try Fx.storageDump(store), before)

        for deviceId in [Fx.b, Fx.n, Fx.d, Fx.a] {
            try registry(store).remove(deviceId)
            try Fx.assertCounts(store, Fx.countsById, "after remove(\(deviceId))")
            XCTAssertEqual(try Fx.storageDump(store), before, "after remove(\(deviceId))")
        }
        XCTAssertEqual(try Fx.registryIds(store), [], "no registry row is left")
        let listed = try await store.allLabMarkers()
        XCTAssertEqual(listed, Fx.storedOrder, "and all ten readings are still read")
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells)
    }

    // MARK: - Whole-data removal (§8.6)

    /// Protects ruling R42's second half: removing all of the app's data on purpose still removes the
    /// readings.
    // SPEC-AMBIGUITY: R42 and this work package's brief say "erase all app data still removes them";
    // §3 row L4 says the app has no erase-all action and §8.6 names the two whole-data removals that
    // exist: deleting the app (its database file goes) and restoring a backup (the file is replaced).
    // This test and the next pin those two at store level: nothing about a reading is kept anywhere
    // but the database file.
    func testRemovingTheDatabaseFileRemovesEveryLabBookReading() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("labbook-ownership-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("whoop.sqlite").path

        do {
            let store = try await WhoopStore(path: path)
            try Fx.insertRaw(Fx.all, into: store)
            for cell in Fx.cells { try Fx.setCell(cell, in: store) }
            try Fx.assertCounts(store, Fx.countsById, "written to the file")
            try await store.checkpointWAL()
        }
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }

        let fresh = try await WhoopStore(path: path)
        try Fx.assertCounts(fresh, [:], "after the file was removed")
        XCTAssertEqual(try Fx.labBookCells(fresh), [])
        let listed = try await fresh.allLabMarkers()
        XCTAssertEqual(listed, [])
        let ids = try await fresh.labMarkerDeviceIds()
        XCTAssertEqual(ids, [])
    }

    /// Protects §8.6: restoring a backup replaces the database file, and afterwards the readings are
    /// exactly the restored file's, read by the same path.
    func testReplacingTheDatabaseFileLeavesExactlyTheRestoredFilesReadings() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("labbook-ownership-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let livePath = directory.appendingPathComponent("whoop.sqlite").path
        let backupPath = directory.appendingPathComponent("backup.sqlite").path

        do {
            let live = try await WhoopStore(path: livePath)
            try Fx.insertRaw(Fx.all, into: live)
            try Fx.assertCounts(live, Fx.countsById, "the live file")
            try await live.checkpointWAL()
            let backup = try await WhoopStore(path: backupPath)
            try Fx.insertRaw(Fx.singleIdRows, into: backup)
            try Fx.assertCounts(backup, [Fx.a: 8], "the backup file")
            try await backup.checkpointWAL()
        }
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: livePath + suffix) }
        try FileManager.default.copyItem(atPath: backupPath, toPath: livePath)

        let restored = try await WhoopStore(path: livePath)
        try Fx.assertCounts(restored, [Fx.a: 8], "after the restore")
        let listed = try await restored.allLabMarkers()
        XCTAssertEqual(listed, Fx.singleIdRows)
    }

    // MARK: - Upgrade (§8.3)

    /// Protects §8.3: the first launch of the new build on a database an older build left. Rows sit
    /// under five ids, one of them unregistered; one projected cell holds the wrong one of the day's
    /// readings, one is missing and one is the trace of a reading that is gone. Reading and repairing
    /// deletes, overwrites and hides no row.
    func testUpgradeFromRowsUnderSeveralIdsDeletesOverwritesAndHidesNothing() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        try Fx.insertRaw(Fx.all, into: store)
        // As a per-id projection could have left the cells.
        for cell in Fx.cells where !(cell.key == "weight" && cell.day == Fx.day3) && cell.key != "ldl" {
            try Fx.setCell(cell, in: store)
        }
        try Fx.setCell(Fx.cell("weight", Fx.day3, 98.0), in: store)        // F3's value, not the latest
        try Fx.setCell(Fx.cell("weight", "2031-02-05", 97.5), in: store)   // no reading that day
        let before = try Fx.storageDump(store)
        try Fx.assertCounts(store, Fx.countsById, "before the upgrade")

        let repair = try await store.repairLabBookProjection()
        try Fx.assertCounts(store, Fx.countsById, "after the repair")
        XCTAssertEqual(try Fx.storageDump(store), before, "no row deleted, moved or overwritten")
        XCTAssertEqual(repair.inserted, 1, "the ldl cell")
        XCTAssertEqual(repair.updated, 1, "the 2031-01-22 weight cell")
        XCTAssertEqual(repair.unchanged, 4)
        XCTAssertEqual(repair.unbackedKept, 1, "the 2031-02-05 cell")
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells + [Fx.cell("weight", "2031-02-05", 97.5)])

        let stored = try await store.allLabMarkers()
        XCTAssertEqual(stored, Fx.storedOrder, "every row under every id is read")
        let listed = LabMarkerUnion.merged(stored, activeDeviceId: Fx.n)
        XCTAssertEqual(listed, Fx.mergedWithNActive)
        // Hidden rows are copies of a listed row, and nothing else: listed + surplus copies = stored.
        let hidden = stored.filter { row in !listed.contains { $0.id == row.id } }
        XCTAssertEqual(hidden, [Fx.f6])
        XCTAssertTrue(hidden.allSatisfy { row in listed.contains { LabMarkerUnion.isCopy($0, row) } })
        XCTAssertEqual(listed.count + hidden.count, stored.count)
        try Fx.assertCounts(store, Fx.countsById, "after the reads")
        XCTAssertEqual(try Fx.storageDump(store), before)
    }

    // MARK: - All-id reads (§12.2 cases 27 to 29)

    /// Protects decision D2 (fault F10): the read covers every device id present in the table, a
    /// paired id, an archived id, the active id, an other-brand id and an id with no registry row,
    /// ordered by (`takenAt`, `id`).
    func testAllLabMarkersReturnsRowsUnderRegisteredUnregisteredAndOtherBrandIds() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")
        XCTAssertFalse(try Fx.registryIds(store).contains(Fx.c), "C has no registry row")

        let rows = try await store.allLabMarkers()

        XCTAssertEqual(rows, Fx.storedOrder)
        XCTAssertEqual(Set(rows.map(\.deviceId)), [Fx.a, Fx.b, Fx.c, Fx.d, Fx.n])
        XCTAssertEqual(rows.filter { $0.deviceId == Fx.c }, [Fx.f10, Fx.f3], "the unregistered id's two rows")
        XCTAssertEqual(rows.filter { $0.deviceId == Fx.d }, [Fx.f5], "the other-brand id's row")
        let again = try await store.allLabMarkers()
        XCTAssertEqual(again, rows, "the same on a second read")
        try Fx.assertCounts(store, Fx.countsById, "a read changes nothing")

        let empty = try await WhoopStore.inMemory()
        let none = try await empty.allLabMarkers()
        XCTAssertEqual(none, [])
    }

    /// Protects: the two narrower reads are the full read filtered, and nothing more.
    func testAllLabMarkersByCategoryAndByMarkerFilterOnly() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")
        let all = try await store.allLabMarkers()

        let body = try await store.allLabMarkers(category: "bodyMeasurement")
        XCTAssertEqual(body, [Fx.f5, Fx.f1, Fx.f2, Fx.f9, Fx.f3, Fx.f8, Fx.f4])
        let blood = try await store.allLabMarkers(category: "bloodPanel")
        XCTAssertEqual(blood, [Fx.f6, Fx.f7])
        let other = try await store.allLabMarkers(category: "other")
        XCTAssertEqual(other, [Fx.f10])

        let weight = try await store.allLabMarkers(markerKey: "weight")
        XCTAssertEqual(weight, [Fx.f1, Fx.f2, Fx.f9, Fx.f3, Fx.f8, Fx.f4])
        let ldl = try await store.allLabMarkers(markerKey: "ldl")
        XCTAssertEqual(ldl, [Fx.f6, Fx.f7])
        let waist = try await store.allLabMarkers(markerKey: "waist")
        XCTAssertEqual(waist, [Fx.f5])
        let note = try await store.allLabMarkers(markerKey: "fixture_note")
        XCTAssertEqual(note, [Fx.f10])

        for category in ["bodyMeasurement", "bloodPanel", "other"] {
            let filtered = try await store.allLabMarkers(category: category)
            XCTAssertEqual(filtered, all.filter { $0.category == category }, category)
        }
        for key in ["weight", "ldl", "waist", "fixture_note"] {
            let filtered = try await store.allLabMarkers(markerKey: key)
            XCTAssertEqual(filtered, all.filter { $0.markerKey == key }, key)
        }
        // A name that matches nothing, an empty name, and a name of the other kind return nothing.
        for name in ["", "no-such-name", "BodyMeasurement", "weight "] {
            let byCategory = try await store.allLabMarkers(category: name)
            XCTAssertEqual(byCategory, [], "category '\(name)'")
            let byMarker = try await store.allLabMarkers(markerKey: name)
            XCTAssertEqual(byMarker, [], "marker '\(name)'")
        }
        let crossed = try await store.allLabMarkers(category: "weight")
        XCTAssertEqual(crossed, [], "a marker key is not a category")
        try Fx.assertCounts(store, Fx.countsById, "after")
    }

    /// Protects: the id list names each id holding a row once, ascending, registered or not.
    func testLabMarkerDeviceIdsListsEachIdOnce() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")
        let ids = try await store.labMarkerDeviceIds()
        XCTAssertEqual(ids, [Fx.a, Fx.d, Fx.c, Fx.n, Fx.b])
        XCTAssertEqual(ids, ["my-whoop", "oura-FIXTURE-RING", "whoop-FIXTURE-GONE", "whoop-FIXTURE-NEW",
                             "whoop-FIXTURE-OLD"])

        // An id leaves the list with its last row.
        try await store.deleteLabMarkerAndCopies(id: Fx.f1.id)
        var counts = Fx.countsById
        counts[Fx.a] = nil
        try Fx.assertCounts(store, counts, "after deleting A's only row")
        let fewer = try await store.labMarkerDeviceIds()
        XCTAssertEqual(fewer, [Fx.d, Fx.c, Fx.n, Fx.b])

        let empty = try await Fx.emptyStoreWithRegistry()
        let none = try await empty.labMarkerDeviceIds()
        XCTAssertEqual(none, [], "registered ids with no row are not listed")
    }

    // MARK: - Owner-scope upsert (§12.2 cases 30 to 34)

    /// Protects: a reading no id holds is inserted exactly as given. The identity is compared to the
    /// second and includes the source: one second either side of F6 and F7, and the same instant from
    /// another source, are new readings.
    func testUpsertOwnerInsertsWhenNoIdHoldsTheIdentity() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")
        let fresh = Fx.row(id: "ldl-1927436400-D0000001", deviceId: Fx.n, markerKey: "ldl", category: "bloodPanel",
                           day: Fx.day4, takenAt: Fx.t4, value: 3.0, unit: "mmol/L", source: "lab-csv",
                           note: "fixture panel")

        let written = try await store.upsertOwnerLabMarkers([fresh])

        XCTAssertEqual(written, 1)
        var counts = Fx.countsById
        counts[Fx.n] = 4
        try Fx.assertCounts(store, counts, "after the insert")
        let stored = try await store.allLabMarkers(markerKey: "ldl")
        XCTAssertEqual(stored, [Fx.f6, Fx.f7, fresh], "stored as given, id and device id included")
        XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell("ldl", Fx.day2, 3.0), Fx.cell("ldl", Fx.day4, 3.0)]
                       + Fx.cells.dropFirst())

        // One second after, one second before, and the same instant from another source.
        let after = draft(Fx.f6, id: "ldl-1926226801-D0000002") { $0.takenAt = Fx.t2 + 1; $0.value = 90.0 }
        let earlier = draft(Fx.f6, id: "ldl-1926226799-D0000003") { $0.takenAt = Fx.t2 - 1 }
        let manual = draft(Fx.f6, id: "ldl-1926226800-D0000004") { $0.source = "manual" }
        for (index, row) in [after, earlier, manual].enumerated() {
            let one = try await store.upsertOwnerLabMarkers([row])
            XCTAssertEqual(one, 1, "boundary row \(index)")
        }
        counts[Fx.n] = 7
        try Fx.assertCounts(store, counts, "after the three boundary inserts")
        let ldl = try await store.allLabMarkers(markerKey: "ldl")
        // At t2 the manual draft's id ("…-D0000004") sorts before F6's ("…-F0000006").
        XCTAssertEqual(ldl, [earlier, manual, Fx.f6, Fx.f7, after, fresh], "F6 and F7 are untouched")
        // The latest reading of 2031-01-15 is now the one a second after t2.
        XCTAssertEqual(try Fx.labBookCells(store).first, Fx.cell("ldl", Fx.day2, 90.0))
    }

    /// Protects faults F21 and F22: a reading held under another id is updated where it is. The
    /// stored row keeps its `id` and its `deviceId` and takes every other column from the incoming
    /// row; nothing is created under the active id.
    func testUpsertOwnerUpdatesTheRowUnderAnotherIdInPlaceKeepingItsIdAndDeviceId() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")
        // F2 is held under B only. The draft carries N and a new id.
        let edit = draft(Fx.f2, id: "weight-1926226800-D0000001") { $0.value = 98.2; $0.note = "fixture panel" }

        let written = try await store.upsertOwnerLabMarkers([edit])

        XCTAssertEqual(written, 1)
        try Fx.assertCounts(store, Fx.countsById, "after: ten rows, none new under N")
        var expected = Fx.f2
        expected.value = 98.2
        expected.note = "fixture panel"
        let rows = try Fx.rows(store)
        XCTAssertEqual(rows, Fx.storedOrder.map { $0.id == Fx.f2.id ? expected : $0 })
        XCTAssertFalse(rows.contains { $0.id == edit.id }, "the draft's id is not stored")
        XCTAssertEqual(rows.first { $0.id == Fx.f2.id }?.deviceId, Fx.b)
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells.map {
            $0.key == "weight" && $0.day == Fx.day2 ? Fx.cell("weight", Fx.day2, 98.2) : $0
        })

        // Every content column follows the incoming row, a column going to NULL included.
        let rewrite = draft(Fx.f2, id: "weight-1926226800-D0000002") {
            $0.category = "other"; $0.day = "2031-01-16"; $0.value = nil; $0.valueText = "clear"
            $0.unit = "text"; $0.note = nil; $0.referenceText = "fixture range"
        }
        let again = try await store.upsertOwnerLabMarkers([rewrite])
        XCTAssertEqual(again, 1)
        try Fx.assertCounts(store, Fx.countsById, "after the second update")
        var rewritten = rewrite
        rewritten.id = Fx.f2.id
        rewritten.deviceId = Fx.b
        XCTAssertEqual(try Fx.rows(store), Fx.storedOrder.map { $0.id == Fx.f2.id ? rewritten : $0 })
        // No number is left on 2031-01-15 for weight, and none arrived on 2031-01-16.
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells.filter { !($0.key == "weight" && $0.day == Fx.day2) })
    }

    /// Protects: copies stay copies. An incoming row updates every stored row at its identity, each
    /// under its own id.
    func testUpsertOwnerUpdatesEveryRowAtTheIdentityAcrossIds() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")
        let edit = draft(Fx.f6, id: "ldl-1926226800-D0000001") { $0.value = 90.0 }

        let written = try await store.upsertOwnerLabMarkers([edit])

        XCTAssertEqual(written, 2, "two stored rows were updated")
        try Fx.assertCounts(store, Fx.countsById, "after")
        var f6 = Fx.f6, f7 = Fx.f7
        f6.value = 90.0
        f7.value = 90.0
        XCTAssertEqual(try Fx.rows(store), [Fx.f5, Fx.f1, Fx.f10, f6, f7, Fx.f2, Fx.f9, Fx.f3, Fx.f8, Fx.f4])
        XCTAssertTrue(LabMarkerUnion.isCopy(f6, f7))
        XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell("ldl", Fx.day2, 90.0)] + Fx.cells.dropFirst())
    }

    /// Protects §7.4 as written for an identity that holds a conflict: "update each of those stored
    /// rows in place".
    // SPEC-AMBIGUITY: §7.4 has an owner-scope upsert update EVERY stored row at the identity. Applied
    // to F3 and F8, which are two different readings (98.0 and 98.4), one saved value replaces both,
    // which sits badly with §8.3's "no row is overwritten" and with R42. §7.4 is explicit and it is an
    // action the owner takes on that identity, so the algorithm is what is asserted here. If the
    // ruling is that a conflict must survive an upsert, this test changes and §7.4 needs a rule for
    // which row an incoming reading lands on.
    func testUpsertOwnerOntoAnIdentityHoldingAConflictUpdatesBothRowsInPlace() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")
        let edit = draft(Fx.f8, id: "weight-1926831600-D0000001") { $0.value = 98.2 }

        let written = try await store.upsertOwnerLabMarkers([edit])

        XCTAssertEqual(written, 2)
        try Fx.assertCounts(store, Fx.countsById, "after: both rows are still stored, each under its own id")
        var f3 = Fx.f3, f8 = Fx.f8
        f3.value = 98.2
        f8.value = 98.2
        XCTAssertEqual(try Fx.rows(store), [Fx.f5, Fx.f1, Fx.f10, Fx.f6, Fx.f7, Fx.f2, Fx.f9, f3, f8, Fx.f4])
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells.map {
            $0.key == "weight" && $0.day == Fx.day3 ? Fx.cell("weight", Fx.day3, 98.2) : $0
        })
    }

    /// Protects decision D6 (fault F21): importing the same file again after the active id changed
    /// updates and does not double. Seven readings come back as drafts under N with new ids; the table
    /// is exactly what it was, twice over.
    // SPEC-AMBIGUITY: "Returns the number of stored rows inserted or updated" does not say whether a
    // stored row that already holds the incoming content counts. The return value of a no-change
    // re-import is therefore not asserted; cases 30 to 32 assert it where content changes.
    func testUpsertOwnerReimportOfTheSameRowsIsANoOpInRowCount() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")
        // One row per identity. F3 and F8 share an identity and differ, so no single file holds both.
        let file = [Fx.f1, Fx.f2, Fx.f4, Fx.f5, Fx.f6, Fx.f9, Fx.f10].enumerated().map { index, row in
            draft(row, id: "reimport-D000000\(index)")
        }

        for round in 1...2 {
            try await store.upsertOwnerLabMarkers(file)
            try Fx.assertCounts(store, Fx.countsById, "after re-import \(round)")
            XCTAssertEqual(try Fx.rows(store), Fx.storedOrder, "re-import \(round): every row as it was")
            XCTAssertEqual(try Fx.labBookCells(store), Fx.cells, "re-import \(round)")
        }
        // Re-importing in the opposite order changes nothing either.
        try await store.upsertOwnerLabMarkers(file.reversed())
        try Fx.assertCounts(store, Fx.countsById, "after the reversed re-import")
        XCTAssertEqual(try Fx.rows(store), Fx.storedOrder)
    }

    /// Protects: when an update moves a reading to another day, the cell of the day it left and the
    /// cell of the day it arrived on are both recomputed.
    func testUpsertOwnerMovingADayRecomputesBothCells() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")

        // F2 is the only weight reading of 2031-01-15: its old cell goes, a new one appears.
        try await store.upsertOwnerLabMarkers([draft(Fx.f2, id: "weight-1926226800-D0000001") { $0.day = "2031-01-16" }])
        try Fx.assertCounts(store, Fx.countsById, "after moving F2's day")
        XCTAssertEqual(try Fx.rows(store).first { $0.id == Fx.f2.id }?.day, "2031-01-16")
        XCTAssertEqual(try Fx.labBookCells(store), [
            Fx.cell("ldl", Fx.day2, 3.0), Fx.cell("waist", Fx.day1, 100.0), Fx.cell("weight", Fx.day1, 100.0),
            Fx.cell("weight", "2031-01-16", 99.2), Fx.cell("weight", Fx.day3, 98.4), Fx.cell("weight", Fx.day4, 97.6),
        ])

        // F9 leaves 2031-01-22, where F3 and F8 remain: that cell stays, a new one appears.
        try await store.upsertOwnerLabMarkers([draft(Fx.f9, id: "weight-1926828000-D0000002") { $0.day = "2031-01-21" }])
        try Fx.assertCounts(store, Fx.countsById, "after moving F9's day")
        XCTAssertEqual(try Fx.labBookCells(store), [
            Fx.cell("ldl", Fx.day2, 3.0), Fx.cell("waist", Fx.day1, 100.0), Fx.cell("weight", Fx.day1, 100.0),
            Fx.cell("weight", "2031-01-16", 99.2), Fx.cell("weight", "2031-01-21", 98.2),
            Fx.cell("weight", Fx.day3, 98.4), Fx.cell("weight", Fx.day4, 97.6),
        ])
    }

    /// Protects §6.1: an empty list writes nothing and reports nothing.
    func testUpsertOwnerOfAnEmptyListChangesNothing() async throws {
        let store = try await Fx.seededStore()
        let before = try Fx.storageDump(store)
        try Fx.assertCounts(store, Fx.countsById, "before")

        let written = try await store.upsertOwnerLabMarkers([])
        XCTAssertEqual(written, 0)
        let trace = try await store.labBookOwnershipUpsertNothing()
        XCTAssertEqual(trace.written, 0)
        XCTAssertEqual(trace.upsertTouched, [])

        try Fx.assertCounts(store, Fx.countsById, "after")
        XCTAssertEqual(try Fx.storageDump(store), before)
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells)
    }

    /// Protects §6.1: two incoming rows with one identity are applied in list order, so one row is
    /// stored, holding the later one's content under the first one's `id` and `deviceId`.
    func testUpsertOwnerAppliesTwoIncomingRowsOfOneIdentityInListOrder() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        try Fx.assertCounts(store, [:], "before")
        let first = Fx.row(id: "weight-1927436400-D0000001", deviceId: Fx.n, markerKey: "weight",
                           category: "bodyMeasurement", day: Fx.day4, takenAt: Fx.t4, value: 98.0, unit: "kg")
        let second = Fx.row(id: "weight-1927436400-D0000002", deviceId: Fx.b, markerKey: "weight",
                            category: "bodyMeasurement", day: Fx.day4, takenAt: Fx.t4, value: 97.6, unit: "kg",
                            note: "fixture panel")

        try await store.upsertOwnerLabMarkers([first, second])

        try Fx.assertCounts(store, [Fx.n: 1], "one stored row, under the first row's id")
        var expected = second
        expected.id = first.id
        expected.deviceId = first.deviceId
        XCTAssertEqual(try Fx.rows(store), [expected])
        XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell("weight", Fx.day4, 97.6)])
    }

    /// Protects: "not measured" is never zero. A value that is not a number is never stored or
    /// projected as a number.
    // SPEC-AMBIGUITY: §7.4 names no rule for a non-finite incoming value. SQLite stores NaN as NULL.
    // The test accepts either a thrown error or a stored row with no number, and in both cases
    // requires that no cell is created and that no stored or projected value is 0.
    func testUpsertOwnerOfAValueThatIsNotANumberNeverStoresOrProjectsANumber() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        try Fx.assertCounts(store, [:], "before")
        let broken = Fx.row(id: "weight-1927436400-D0000001", deviceId: Fx.n, markerKey: "weight",
                            category: "bodyMeasurement", day: Fx.day4, takenAt: Fx.t4, value: .nan, unit: "kg")
        do {
            try await store.upsertOwnerLabMarkers([broken])
        } catch {
            // Refusing the row is acceptable.
        }
        let rows = try Fx.rows(store)
        XCTAssertLessThanOrEqual(rows.count, 1)
        XCTAssertNil(rows.first?.value ?? nil, "a NaN is stored as no number, never as 0 or any other number")
        XCTAssertEqual(try Fx.labBookCells(store), [], "and it projects no cell")
    }

    // MARK: - Owner-scope delete (§12.2 cases 35 to 38)

    /// Protects decision D5 (faults F20, F27): deleting a reading that is listed once removes every
    /// stored copy of it, so it cannot come back from another id, and the cell is recomputed from the
    /// rows as they stand after the delete.
    func testDeleteAndCopiesRemovesTheRowAndItsCopiesAcrossIds() async throws {
        for target in [Fx.f7, Fx.f6] {
            let store = try await Fx.seededStore()
            try Fx.assertCounts(store, Fx.countsById, "before deleting \(target.id)")

            let deleted = try await store.deleteLabMarkerAndCopies(id: target.id)

            XCTAssertEqual(deleted, [Fx.f6.id, Fx.f7.id], "both ids, ascending, whichever was named")
            try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 2, Fx.c: 2, Fx.d: 1, Fx.n: 2], "after deleting \(target.id)")
            XCTAssertEqual(try Fx.rows(store), [Fx.f5, Fx.f1, Fx.f10, Fx.f2, Fx.f9, Fx.f3, Fx.f8, Fx.f4])
            XCTAssertEqual(try Fx.labBookCells(store), Array(Fx.cells.dropFirst()), "the ldl cell is gone")
            let listed = try await store.allLabMarkers(markerKey: "ldl")
            XCTAssertEqual(listed, [], "the reading does not reappear from the other id")
        }
    }

    /// Protects: a copy is a copy whatever `day` it was stored under (ruling R39), and each deleted
    /// copy's own cell is recomputed.
    func testDeleteAndCopiesRemovesACopyStoredUnderAnotherDayAndItsCell() async throws {
        let store = try await Fx.seededStore()
        var third = Fx.f6
        third.id = "ldl-1926226800-F0000011"
        third.deviceId = Fx.a
        third.day = "2031-01-14"
        try Fx.insertRaw([third], into: store)
        try Fx.setCell(Fx.cell("ldl", "2031-01-14", 3.0), in: store)
        var counts = Fx.countsById
        counts[Fx.a] = 2
        try Fx.assertCounts(store, counts, "before")

        let deleted = try await store.deleteLabMarkerAndCopies(id: Fx.f7.id)

        XCTAssertEqual(deleted, [Fx.f6.id, Fx.f7.id, third.id])
        try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 2, Fx.c: 2, Fx.d: 1, Fx.n: 2], "after")
        XCTAssertEqual(try Fx.labBookCells(store), Array(Fx.cells.dropFirst()), "both ldl cells are gone")
    }

    /// Protects fault F19: a different reading at the same identity is not deleted. §13: deleting F8
    /// leaves F3 and the cell becomes 98.0; deleting F3 leaves F8 and the cell stays 98.4.
    func testDeleteAndCopiesLeavesAConflictingRowAtTheSameIdentity() async throws {
        let first = try await Fx.seededStore()
        try Fx.assertCounts(first, Fx.countsById, "before deleting F8")
        let deletedF8 = try await first.deleteLabMarkerAndCopies(id: Fx.f8.id)
        XCTAssertEqual(deletedF8, [Fx.f8.id])
        try Fx.assertCounts(first, [Fx.a: 1, Fx.b: 3, Fx.c: 2, Fx.d: 1, Fx.n: 2], "after deleting F8")
        XCTAssertEqual(try Fx.rows(first), Fx.storedOrder.filter { $0.id != Fx.f8.id }, "F3 is byte-identical")
        XCTAssertEqual(try Fx.labBookCells(first), Fx.cells.map {
            $0.key == "weight" && $0.day == Fx.day3 ? Fx.cell("weight", Fx.day3, 98.0) : $0
        })

        let second = try await Fx.seededStore()
        try Fx.assertCounts(second, Fx.countsById, "before deleting F3")
        let deletedF3 = try await second.deleteLabMarkerAndCopies(id: Fx.f3.id)
        XCTAssertEqual(deletedF3, [Fx.f3.id])
        try Fx.assertCounts(second, [Fx.a: 1, Fx.b: 3, Fx.c: 1, Fx.d: 1, Fx.n: 3], "after deleting F3")
        XCTAssertEqual(try Fx.rows(second), Fx.storedOrder.filter { $0.id != Fx.f3.id }, "F8 is byte-identical")
        XCTAssertEqual(try Fx.labBookCells(second), Fx.cells, "the 2031-01-22 cell stays 98.4")

        // A row that differs from the pair only in its note is a different reading too.
        let third = try await Fx.seededStore()
        var noted = Fx.f6
        noted.id = "ldl-1926226800-F0000012"
        noted.deviceId = Fx.a
        noted.note = nil
        try Fx.insertRaw([noted], into: third)
        let deletedPair = try await third.deleteLabMarkerAndCopies(id: Fx.f6.id)
        XCTAssertEqual(deletedPair, [Fx.f6.id, Fx.f7.id])
        try Fx.assertCounts(third, [Fx.a: 2, Fx.b: 2, Fx.c: 2, Fx.d: 1, Fx.n: 2], "after deleting the pair")
        let ldl = try await third.allLabMarkers(markerKey: "ldl")
        XCTAssertEqual(ldl, [noted])
        XCTAssertEqual(try Fx.labBookCells(third), Fx.cells, "the ldl cell is still backed, by the remaining row")
    }

    /// Protects fault F31: an id that is not stored deletes nothing and is not an error.
    func testDeleteAndCopiesOfAnUnknownIdDeletesNothing() async throws {
        let store = try await Fx.seededStore()
        let before = try Fx.storageDump(store)
        try Fx.assertCounts(store, Fx.countsById, "before")

        for id in ["weight-0-FFFFFFFF", "", "ldl-1926226800-F0000006 ", "LDL-1926226800-F0000006", Fx.b, "weight"] {
            let deleted = try await store.deleteLabMarkerAndCopies(id: id)
            XCTAssertEqual(deleted, [], "id '\(id)'")
            try Fx.assertCounts(store, Fx.countsById, "after id '\(id)'")
        }
        XCTAssertEqual(try Fx.storageDump(store), before)
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells)

        // Deleting the same reading a second time finds nothing.
        let once = try await store.deleteLabMarkerAndCopies(id: Fx.f1.id)
        XCTAssertEqual(once, [Fx.f1.id])
        let twice = try await store.deleteLabMarkerAndCopies(id: Fx.f1.id)
        XCTAssertEqual(twice, [])
    }

    /// Protects: a delete touches the named reading and its copies, and nothing else. Rows one second
    /// either side, the same instant from another source, another marker at the same instant, and the
    /// rest of the fixture are byte-identical afterwards.
    func testDeleteAndCopiesNeverTouchesAnotherMarkerOrInstant() async throws {
        let store = try await Fx.seededStore()
        func near(_ id: String, deviceId: String, _ change: (inout LabMarkerRow) -> Void) -> LabMarkerRow {
            var row = Fx.f6
            row.id = id
            row.deviceId = deviceId
            change(&row)
            return row
        }
        let bystanders = [
            near("ldl-1926226801-F0000011", deviceId: Fx.b) { $0.takenAt = Fx.t2 + 1 },
            near("ldl-1926226799-F0000012", deviceId: Fx.n) { $0.takenAt = Fx.t2 - 1 },
            near("ldl-1926226800-F0000013", deviceId: Fx.b) { $0.source = "manual" },
            near("hdl-1926226800-F0000014", deviceId: Fx.n) { $0.markerKey = "hdl" },
        ]
        try Fx.insertRaw(bystanders, into: store)
        try Fx.setCell(Fx.cell("hdl", Fx.day2, 3.0), in: store)
        try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 5, Fx.c: 2, Fx.d: 1, Fx.n: 5], "before")
        let before = try Fx.storageDump(store)
        XCTAssertEqual(before.count, 14)

        let deleted = try await store.deleteLabMarkerAndCopies(id: Fx.f7.id)

        XCTAssertEqual(deleted, [Fx.f6.id, Fx.f7.id])
        try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 4, Fx.c: 2, Fx.d: 1, Fx.n: 4], "after")
        let after = try Fx.storageDump(store)
        XCTAssertEqual(after, before.filter { !$0.contains("|\(Fx.f6.id)|") && !$0.contains("|\(Fx.f7.id)|") },
                       "the twelve other rows are byte-identical, rowid included")
        // The ldl cell of 2031-01-15 is recomputed from the three ldl rows left that day (all 3.0);
        // every other cell, hdl included, is as it was.
        XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell("hdl", Fx.day2, 3.0)] + Fx.cells)
    }

    // MARK: - In-transaction steps (§12.2 cases 80 and 82)

    /// Protects §6.1's composition rules (faults F27, F30): inside one transaction, `deleteWithCopies`
    /// of F7, `ownerUpsert` of a new `ldl` row at t4 and one `reprojectCells` over both touched sets.
    /// Neither step writes `metricSeries`; the single projection at the end is computed from the rows
    /// as they stand after both. A throw after the delete rolls everything back.
    func testOwnerUpsertAndDeleteWithCopiesComposeInOneTransaction() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")
        let before = try Fx.storageDump(store)
        let fresh = Fx.row(id: "ldl-1927436400-D0000001", deviceId: Fx.n, markerKey: "ldl", category: "bloodPanel",
                           day: Fx.day4, takenAt: Fx.t4, value: 3.0, unit: "mmol/L", source: "lab-csv",
                           note: "fixture panel")

        // The failing run first: nothing may have changed.
        do {
            _ = try await store.labBookOwnershipDeleteThenUpsert(deleteId: Fx.f7.id, rows: [fresh],
                                                                 failAfterDelete: true)
            XCTFail("the injected failure must propagate")
        } catch is LabBookOwnershipInjectedFailure {
            // expected
        }
        try Fx.assertCounts(store, Fx.countsById, "after the rolled-back run")
        XCTAssertEqual(try Fx.storageDump(store), before, "all ten rows as they were")
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells, "all six cells as they were")

        let trace = try await store.labBookOwnershipDeleteThenUpsert(deleteId: Fx.f7.id, rows: [fresh],
                                                                     failAfterDelete: false)

        XCTAssertEqual(trace.firstDeleted, [Fx.f6.id, Fx.f7.id])
        XCTAssertEqual(trace.firstTouched, ["ldl|2031-01-15"])
        XCTAssertEqual(trace.written, 1)
        XCTAssertEqual(trace.upsertTouched, ["ldl|2031-01-29"])
        XCTAssertEqual(trace.seriesAfterDeletes, Fx.cells, "deleteWithCopies wrote no metricSeries row")
        XCTAssertEqual(trace.seriesAfterUpsert, Fx.cells, "ownerUpsert wrote no metricSeries row")
        XCTAssertEqual(trace.rowCountBeforeProjection, 9)

        try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 2, Fx.c: 2, Fx.d: 1, Fx.n: 3], "after the committed run")
        // At t4 the new row's id ("ldl-…") sorts before F4's ("weight-…").
        XCTAssertEqual(try Fx.rows(store), [Fx.f5, Fx.f1, Fx.f10, Fx.f2, Fx.f9, Fx.f3, Fx.f8, fresh, Fx.f4])
        XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell("ldl", Fx.day4, 3.0)] + Fx.cells.dropFirst(),
                       "no ldl cell on 2031-01-15, one on 2031-01-29")
    }

    /// Protects §6.1 (faults F30, F31): an id that an earlier step of the same transaction already
    /// removed as a copy returns an empty result and is not an error, and no step has changed a
    /// `metricSeries` row before `reprojectCells` runs.
    func testDeleteWithCopiesOfAnIdAlreadyRemovedAsACopyIsEmptyAndNotAnError() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")

        let trace = try await store.labBookOwnershipDeleteTwice(first: Fx.f7.id, second: Fx.f6.id)

        XCTAssertEqual(trace.firstDeleted, [Fx.f6.id, Fx.f7.id])
        XCTAssertEqual(trace.firstTouched, ["ldl|2031-01-15"])
        XCTAssertEqual(trace.secondDeleted, [])
        XCTAssertEqual(trace.secondTouched, [])
        XCTAssertEqual(trace.rowCountBeforeProjection, 8)
        XCTAssertEqual(trace.seriesAfterDeletes, Fx.cells,
                       "the ldl cell is still stored after both deletes and before the projection")

        try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 2, Fx.c: 2, Fx.d: 1, Fx.n: 2], "after")
        XCTAssertEqual(try Fx.labBookCells(store), Array(Fx.cells.dropFirst()), "and gone once it has run")

        // An id that was never stored is the same: empty, no error.
        let unknown = try await store.labBookOwnershipDeleteTwice(first: "weight-0-FFFFFFFF", second: "")
        XCTAssertEqual(unknown.firstDeleted, [])
        XCTAssertEqual(unknown.firstTouched, [])
        XCTAssertEqual(unknown.secondDeleted, [])
        XCTAssertEqual(unknown.secondTouched, [])
        try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 2, Fx.c: 2, Fx.d: 1, Fx.n: 2], "after the unknown ids")
    }

    // MARK: - Projection through writes (§12.2 cases 39 to 43)

    /// Protects §7.2 (fault F13): a cell holds the latest reading of the day across every id. With F3,
    /// F8 and F9 stored and the cell absent, re-saving B's earlier reading F9 through the per-id
    /// function must write 98.4, not B's own 98.2. Then the rule to the second: a reading one second
    /// later under another id takes the cell, one second earlier does not.
    func testProjectionPicksTheLatestReadingOfTheDayAcrossIds() async throws {
        let store = try await Fx.seededStore()
        try Fx.removeLabBookCell("weight", Fx.day3, in: store)
        try Fx.assertCounts(store, Fx.countsById, "before")

        try await store.upsertLabMarkers([Fx.f9])

        try Fx.assertCounts(store, Fx.countsById, "after re-saving F9")
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells, "98.4: F8 under N is later than F9 under B")

        // One second before the latest instant, under another id: the cell stays.
        let earlier = Fx.row(id: "weight-1926831599-F0000011", deviceId: Fx.a, markerKey: "weight",
                             category: "bodyMeasurement", day: Fx.day3, takenAt: Fx.t3 - 1, value: 97.5, unit: "kg")
        try await store.upsertLabMarkers([earlier])
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells)

        // One second after it, under yet another id: the cell follows.
        let later = Fx.row(id: "weight-1926831601-F0000012", deviceId: Fx.d, markerKey: "weight",
                           category: "bodyMeasurement", day: Fx.day3, takenAt: Fx.t3 + 1, value: 90.0, unit: "kg")
        try await store.upsertLabMarkers([later])
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells.map {
            $0.key == "weight" && $0.day == Fx.day3 ? Fx.cell("weight", Fx.day3, 90.0) : $0
        })
        try Fx.assertCounts(store, [Fx.a: 2, Fx.b: 3, Fx.c: 2, Fx.d: 2, Fx.n: 3], "after the two boundary rows")
    }

    /// Protects §7.2 (fault F14): readings at one instant are ordered by `id`, greatest first, in
    /// whatever order they were written and whichever device id they sit under.
    func testProjectionTieOnInstantPicksTheGreatestId() async throws {
        // §13: F3 (…03, 98.0, under C) and F8 (…08, 98.4, under N).
        for order in [[Fx.f3, Fx.f8], [Fx.f8, Fx.f3]] {
            let store = try await Fx.emptyStoreWithRegistry()
            try Fx.assertCounts(store, [:], "before")
            for row in order { try await store.upsertLabMarkers([row]) }
            try Fx.assertCounts(store, [Fx.c: 1, Fx.n: 1], "after")
            XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell("weight", Fx.day3, 98.4)], "F8 has the greater id")
        }
        // Mirrored: the greater id now holds the smaller value and sits under the smaller device id,
        // so a rule keyed on the value or on the device id gives the other answer.
        var low = Fx.f3, high = Fx.f8
        low.deviceId = Fx.n
        low.value = 98.4
        high.deviceId = Fx.c
        high.value = 98.0
        for order in [[low, high], [high, low]] {
            let store = try await Fx.emptyStoreWithRegistry()
            for row in order { try await store.upsertLabMarkers([row]) }
            try Fx.assertCounts(store, [Fx.c: 1, Fx.n: 1], "after, mirrored")
            XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell("weight", Fx.day3, 98.0)], "…08 has the greater id")
        }
        // The owner-scope write path follows the same rule when both rows are already stored.
        let store = try await Fx.emptyStoreWithRegistry()
        try Fx.insertRaw([low, high], into: store)
        try await store.upsertOwnerLabMarkers([Fx.f9])
        XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell("weight", Fx.day3, 98.0)])
    }

    /// Protects the R29 quirk (fault F13): deleting one id's last reading of a day keeps the cell
    /// while another id still has a reading that day, and the cell goes with the last reading.
    func testDeletingOneIdsLastReadingOfADayKeepsTheCellWhenAnotherIdHasOne() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")
        func day3Cell() throws -> [Fx.Cell] {
            try Fx.labBookCells(store).filter { $0.key == "weight" && $0.day == Fx.day3 }
        }

        // N's only reading of 2031-01-22. C and B still have one each.
        let deletedF8 = try await store.deleteLabMarker(id: Fx.f8.id)
        XCTAssertTrue(deletedF8)
        try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 3, Fx.c: 2, Fx.d: 1, Fx.n: 2], "after deleting F8")
        XCTAssertEqual(try day3Cell(), [Fx.cell("weight", Fx.day3, 98.0)], "F3 under C is now the latest")

        let deletedF3 = try await store.deleteLabMarker(id: Fx.f3.id)
        XCTAssertTrue(deletedF3)
        try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 3, Fx.c: 1, Fx.d: 1, Fx.n: 2], "after deleting F3")
        XCTAssertEqual(try day3Cell(), [Fx.cell("weight", Fx.day3, 98.2)], "F9 under B is the only one left")

        let deletedF9 = try await store.deleteLabMarker(id: Fx.f9.id)
        XCTAssertTrue(deletedF9)
        try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 2, Fx.c: 1, Fx.d: 1, Fx.n: 2], "after deleting F9")
        XCTAssertEqual(try day3Cell(), [], "no reading that day, no cell")
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells.filter { !($0.key == "weight" && $0.day == Fx.day3) },
                       "every other cell is as it was")
    }

    /// Protects fault F13 on the write side: an earlier reading written under one id does not replace
    /// the cell of a later reading under another, through either write function.
    func testWritingAnEarlierReadingUnderOneIdDoesNotReplaceALaterOneUnderAnother() async throws {
        let perId = try await Fx.emptyStoreWithRegistry()
        try await perId.upsertLabMarkers([Fx.f8])
        try Fx.assertCounts(perId, [Fx.n: 1], "after F8")
        XCTAssertEqual(try Fx.labBookCells(perId), [Fx.cell("weight", Fx.day3, 98.4)])
        try await perId.upsertLabMarkers([Fx.f9])
        try Fx.assertCounts(perId, [Fx.n: 1, Fx.b: 1], "after F9")
        XCTAssertEqual(try Fx.labBookCells(perId), [Fx.cell("weight", Fx.day3, 98.4)],
                       "F9 is an hour earlier and under another id")

        let owner = try await Fx.emptyStoreWithRegistry()
        try await owner.upsertOwnerLabMarkers([Fx.f8])
        try await owner.upsertOwnerLabMarkers([Fx.f9])
        try Fx.assertCounts(owner, [Fx.n: 1, Fx.b: 1], "owner-scope writes")
        XCTAssertEqual(try Fx.labBookCells(owner), [Fx.cell("weight", Fx.day3, 98.4)])

        // The whole fixture written through the per-id function, in three orders, gives the six cells.
        for (name, order) in [("table order", Fx.all), ("reversed", Array(Fx.all.reversed())),
                              ("instant order", Fx.storedOrder)] {
            let store = try await Fx.emptyStoreWithRegistry()
            for row in order { try await store.upsertLabMarkers([row]) }
            try Fx.assertCounts(store, Fx.countsById, name)
            XCTAssertEqual(try Fx.labBookCells(store), Fx.cells, name)
        }
        let batch = try await Fx.emptyStoreWithRegistry()
        try await batch.upsertLabMarkers(Fx.all)
        try Fx.assertCounts(batch, Fx.countsById, "one batch")
        XCTAssertEqual(try Fx.labBookCells(batch), Fx.cells, "one batch of all ten")
    }

    /// Protects: a reading with no number never becomes a projected number, and never displaces one.
    func testQualitativeRowsNeverProject() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        try await store.upsertOwnerLabMarkers([Fx.f10])
        try Fx.assertCounts(store, [Fx.c: 1], "after the text row")
        XCTAssertEqual(try Fx.labBookCells(store), [], "F10 holds text only")

        // A text-only ldl row later than F6 on the same day: the cell stays F6's number.
        try await store.upsertOwnerLabMarkers([Fx.f6])
        XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell("ldl", Fx.day2, 3.0)])
        let text = Fx.row(id: "ldl-1926226801-F0000011", deviceId: Fx.n, markerKey: "ldl", category: "bloodPanel",
                          day: Fx.day2, takenAt: Fx.t2 + 1, value: nil, valueText: "clear", unit: "text",
                          source: "lab-csv")
        try await store.upsertOwnerLabMarkers([text])
        try Fx.assertCounts(store, [Fx.c: 1, Fx.b: 1, Fx.n: 1], "after the later text row")
        XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell("ldl", Fx.day2, 3.0)],
                       "the later row has no number, so the earlier number is still the day's cell")

        // With the number deleted, only text is left that day: no cell, and never a zero.
        try await store.deleteLabMarkerAndCopies(id: Fx.f6.id)
        try Fx.assertCounts(store, [Fx.c: 1, Fx.n: 1], "after deleting the number")
        XCTAssertEqual(try Fx.labBookCells(store), [])
    }

    // MARK: - Single-id equivalence (§12.5 case 72, store level)

    /// Protects §8.5: on an install whose rows all sit under one id, the all-id reads return exactly
    /// what the per-id reads return, and the merge hides nothing.
    func testSingleIdInstallListsExactlyTheRowsThePerIdReadReturns() async throws {
        let store = try await WhoopStore.inMemory()
        try Fx.insertRaw(Fx.singleIdRows, into: store)
        try Fx.assertCounts(store, [Fx.a: 8], "before")

        let all = try await store.allLabMarkers()
        XCTAssertEqual(all, Fx.singleIdRows)
        for key in ["weight", "waist", "ldl", "fixture_note"] {
            let perId = try await store.labMarkers(deviceId: Fx.a, markerKey: key)
            let everyId = try await store.allLabMarkers(markerKey: key)
            XCTAssertEqual(everyId, perId, key)
        }
        for category in ["bodyMeasurement", "bloodPanel", "other"] {
            // The per-id read orders by `takenAt` alone, so rows at one instant are put in id order
            // before comparing.
            let perId = try await store.labMarkers(deviceId: Fx.a, category: category)
                .sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
            let everyId = try await store.allLabMarkers(category: category)
            XCTAssertEqual(everyId, perId, category)
        }
        XCTAssertEqual(LabMarkerUnion.merged(all, activeDeviceId: Fx.a), all)
        let ids = try await store.labMarkerDeviceIds()
        XCTAssertEqual(ids, [Fx.a])
        try Fx.assertCounts(store, [Fx.a: 8], "after")
    }

    // MARK: - Generated input

    /// Protects, over 60 generated histories from a fixed seed: whatever mix of owner-scope upserts,
    /// owner-scope deletes and strap deletes runs, (1) a strap delete never changes a row, (2) an
    /// upsert never changes the stored row count by more than its new identities and never changes a
    /// stored `id` or `deviceId`, (3) a delete removes exactly the named row and its copies, and
    /// (4) the projected cells always equal the latest reading (greatest `takenAt`, then greatest
    /// `id`) of each marker and day over every id.
    func testGeneratedHistoriesKeepRowsAndProjectionConsistent() async throws {
        var generator = Fx.Generator(seed: 0x1AB0_0C0F_F1CE_0003)
        let devices = [Fx.a, Fx.b, Fx.c, Fx.d, Fx.n]
        var strapDeletes = 0, copyDeletes = 0, updates = 0

        func expectedCells(_ rows: [LabMarkerRow]) -> [Fx.Cell] {
            var best: [String: LabMarkerRow] = [:]
            for row in rows where row.value != nil {
                let cellKey = row.markerKey + "|" + row.day
                if let held = best[cellKey], (held.takenAt, held.id) > (row.takenAt, row.id) { continue }
                best[cellKey] = row
            }
            return best.values.map { Fx.cell($0.markerKey, $0.day, $0.value!) }
                .sorted { ($0.key, $0.day) < ($1.key, $1.day) }
        }

        for round in 0..<60 {
            let store = try await Fx.emptyStoreWithRegistry()
            // A starting table under several ids, written raw, with copies and conflicts in it.
            var seed: [LabMarkerRow] = []
            var taken = Set<String>()
            for index in 0..<(4 + generator.below(8)) {
                let device = generator.pick(devices)
                let marker = generator.below(4) == 0 ? "waist" : "weight"
                let instant = [Fx.t2, Fx.t3a, Fx.t3][generator.below(3)]
                let natural = "\(device)|\(marker)|\(instant)"
                guard taken.insert(natural).inserted else { continue }
                let value: Double? = [98.0, 98.0, 98.4, 99.2, nil][generator.below(5)]
                seed.append(Fx.row(id: "g\(generator.below(90) + 10)-\(round)-\(index)", deviceId: device,
                                   markerKey: marker, category: "bodyMeasurement",
                                   day: instant == Fx.t2 ? Fx.day2 : Fx.day3, takenAt: instant, value: value,
                                   valueText: value == nil ? "clear" : nil, unit: marker == "weight" ? "kg" : "cm"))
            }
            try Fx.insertRaw(seed, into: store)
            for cell in expectedCells(seed) { try Fx.setCell(cell, in: store) }

            for step in 0..<8 {
                let context = "round \(round), step \(step)"
                let before = try Fx.rows(store)
                let countsBefore = try Fx.countsById(store)
                XCTAssertEqual(countsBefore.values.reduce(0, +), before.count, context)

                switch generator.below(3) {
                case 0:
                    // A strap delete, on an id that may or may not hold rows or be registered.
                    let dumpBefore = try Fx.storageDump(store)
                    try await store.deleteAllData(deviceId: generator.pick(devices))
                    XCTAssertEqual(try Fx.storageDump(store), dumpBefore, "\(context): strap delete")
                    XCTAssertEqual(try Fx.countsById(store), countsBefore, "\(context): strap delete")
                    strapDeletes += 1
                case 1:
                    guard let target = before.isEmpty ? nil : generator.pick(before) else { continue }
                    let expectedGone = before.filter { LabMarkerUnion.isCopy($0, target) }.map(\.id).sorted()
                    let gone = try await store.deleteLabMarkerAndCopies(id: target.id)
                    XCTAssertEqual(gone, expectedGone, "\(context): delete")
                    XCTAssertEqual(try Fx.rows(store), before.filter { !expectedGone.contains($0.id) },
                                   "\(context): delete")
                    if expectedGone.count > 1 { copyDeletes += 1 }
                default:
                    let marker = generator.below(4) == 0 ? "waist" : "weight"
                    let instant = [Fx.t2, Fx.t3a, Fx.t3, Fx.t4][generator.below(4)]
                    let value: Double? = [97.6, 98.2, 100.0, nil][generator.below(4)]
                    let incoming = Fx.row(id: "u\(round)-\(step)", deviceId: generator.pick(devices), markerKey: marker,
                                          category: "bodyMeasurement",
                                          day: instant == Fx.t2 ? Fx.day2 : (instant == Fx.t4 ? Fx.day4 : Fx.day3),
                                          takenAt: instant, value: value, valueText: value == nil ? "clear" : nil,
                                          unit: marker == "weight" ? "kg" : "cm")
                    let holders = before.filter {
                        $0.markerKey == marker && $0.takenAt == instant && $0.source == "manual"
                    }
                    try await store.upsertOwnerLabMarkers([incoming])
                    let after = try Fx.rows(store)
                    if holders.isEmpty {
                        XCTAssertEqual(after.count, before.count + 1, "\(context): insert")
                        XCTAssertTrue(after.contains(incoming), "\(context): stored as given")
                    } else {
                        XCTAssertEqual(after.count, before.count, "\(context): update")
                        XCTAssertEqual(after.map(\.id), before.map(\.id), "\(context): ids kept")
                        XCTAssertEqual(after.map(\.deviceId), before.map(\.deviceId), "\(context): device ids kept")
                        for holder in holders {
                            let stored = after.first { $0.id == holder.id }
                            XCTAssertEqual(stored?.value, incoming.value, "\(context): value taken")
                            XCTAssertEqual(stored?.valueText, incoming.valueText, "\(context): text taken")
                        }
                        updates += 1
                    }
                }
                XCTAssertEqual(try Fx.labBookCells(store), expectedCells(try Fx.rows(store)), "\(context): cells")
            }
        }
        XCTAssertGreaterThan(strapDeletes, 50, "too few strap deletes were generated")
        XCTAssertGreaterThan(copyDeletes, 5, "too few deletes hit a set of copies")
        XCTAssertGreaterThan(updates, 30, "too few upserts hit a stored identity")
    }
}
