import Foundation
import GRDB
import XCTest
@testable import WhoopStore

// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/labbook-ownership.md §6.1 (each is declared in full in the API
// blocks of LabMarkerUnionTests.swift, LabMarkerOwnershipStoreTests.swift and
// LabBookProjectionRepairTests.swift):
//
//   public func WhoopStore.allLabMarkers() async throws -> [LabMarkerRow]
//   public func WhoopStore.labMarkerDeviceIds() async throws -> [String]
//   @discardableResult public func WhoopStore.repairLabBookProjection() async throws -> LabBookProjectionRepair
//   LabBookProjectionRepair.inserted / .updated / .unchanged / .unbackedKept: Int
//   public static func LabMarkerUnion.merged(_ rows: [LabMarkerRow], activeDeviceId: String) -> [LabMarkerRow]
//   public static func LabMarkerUnion.isCopy(_ a: LabMarkerRow, _ b: LabMarkerRow) -> Bool
//   public static func LabMarkerUnion.conflictingKeys(_ rows: [LabMarkerRow]) -> [LabMarkerUnion.ReadingKey]
//   public static func LabMarkerUnion.key(_ row: LabMarkerRow) -> LabMarkerUnion.ReadingKey
//   public func WhoopStore.deleteAllData(deviceId: String) async throws          (exists; new behaviour)
//
// Existing API used: WhoopStore.init(path:), checkpointWAL(), registryWriter,
// DeviceRegistryStore.init(dbQueue:), all(), activeDeviceId().
//
// Specification §12.10: the real-data rehearsal the Verifier runs before any device install.
//
//   NOOP_REHEARSAL_DB=<absolute path to work.sqlite> swift test --filter LabBookOwnershipRehearsalTests
//
// `testRehearsalOnACopyOfTheOwnersDatabase` is skipped unless that variable is set. It opens only the
// file the variable names, writes its temporary copies beside that file and removes them, and prints
// counts only: no value, marker name, date or device id. The second test runs the same procedure on
// a synthetic file built from the §13 fixture, so the procedure itself is exercised on every run.

final class LabBookOwnershipRehearsalTests: XCTestCase {

    private typealias Fx = LabBookOwnershipFixture

    /// The counts §12.10 step 3 prints.
    private struct Counts: Equatable {
        var rows = 0
        var deviceIds = 0
        var unregisteredIds = 0
        var identitiesWithCopies = 0
        var identitiesWithConflicts = 0
        var qualitativeRows = 0
        var inserted = 0
        var updated = 0
        var unchanged = 0
        var unbackedKept = 0
        var registeredIdsDeleted = 0
    }

    /// §12.10 step 3 on the database at `path`. Asserts the four properties and returns the counts.
    private func rehearse(databaseAt path: String) async throws -> Counts {
        var counts = Counts()
        let store = try await WhoopStore(path: path)
        let registry = DeviceRegistryStore(dbQueue: store.registryWriter)
        let registered = try registry.all().map(\.id)
        let active = try registry.activeDeviceId() ?? ""

        let before = try Fx.storageDump(store)
        let stored = try await store.allLabMarkers()
        XCTAssertEqual(stored.count, before.count, "the all-id read returns every stored row")
        let ids = try await store.labMarkerDeviceIds()
        XCTAssertEqual(Set(ids), Set(stored.map(\.deviceId)))

        counts.rows = stored.count
        counts.deviceIds = ids.count
        counts.unregisteredIds = ids.filter { !registered.contains($0) }.count
        counts.qualitativeRows = stored.filter { $0.value == nil }.count
        counts.identitiesWithConflicts = LabMarkerUnion.conflictingKeys(stored).count

        // Copy classes, built here and not taken from `merged`, so the two can be compared.
        var byIdentity: [LabMarkerUnion.ReadingKey: [[LabMarkerRow]]] = [:]
        for row in stored {
            var classes = byIdentity[LabMarkerUnion.key(row)] ?? []
            if let index = classes.firstIndex(where: { LabMarkerUnion.isCopy($0[0], row) }) {
                classes[index].append(row)
            } else {
                classes.append([row])
            }
            byIdentity[LabMarkerUnion.key(row)] = classes
        }
        counts.identitiesWithCopies = byIdentity.values.filter { classes in classes.contains { $0.count > 1 } }.count
        let surplusCopies = byIdentity.values.reduce(0) { sum, classes in
            sum + classes.reduce(0) { $0 + $1.count - 1 }
        }

        // Every `labMarker` row is byte-identical before and after the repair.
        let repair = try await store.repairLabBookProjection()
        counts.inserted = repair.inserted
        counts.updated = repair.updated
        counts.unchanged = repair.unchanged
        counts.unbackedKept = repair.unbackedKept
        XCTAssertEqual(try Fx.storageDump(store), before, "the repair changed a labMarker row")

        // A second repair inserts and updates nothing.
        let second = try await store.repairLabBookProjection()
        XCTAssertEqual(second.inserted, 0, "the repair is not idempotent")
        XCTAssertEqual(second.updated, 0, "the repair is not idempotent")
        XCTAssertEqual(try Fx.storageDump(store), before)

        // `merged` hides only copies: the listed count plus the surplus copies is the row count.
        let listed = LabMarkerUnion.merged(stored, activeDeviceId: active)
        XCTAssertEqual(listed.count + surplusCopies, stored.count, "a merge hid a row that is not a copy")
        let listedIds = Set(listed.map(\.id))
        for row in stored where !listedIds.contains(row.id) {
            XCTAssertTrue(listed.contains { LabMarkerUnion.isCopy($0, row) }, "a hidden row has no listed copy")
        }

        // For each registered id in turn, on a fresh copy, `deleteAllData` leaves the rows unchanged.
        try await store.checkpointWAL()
        let directory = (path as NSString).deletingLastPathComponent
        for deviceId in registered {
            let copyPath = (directory as NSString)
                .appendingPathComponent("labbook-rehearsal-copy-\(UUID().uuidString).sqlite")
            defer {
                for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: copyPath + suffix) }
            }
            try FileManager.default.copyItem(atPath: path, toPath: copyPath)
            let copy = try await WhoopStore(path: copyPath)
            XCTAssertEqual(try Fx.storageDump(copy), before, "the copy differs from the original")
            try await copy.deleteAllData(deviceId: deviceId)
            XCTAssertEqual(try Fx.storageDump(copy), before, "a strap delete changed a labMarker row")
            counts.registeredIdsDeleted += 1
        }
        return counts
    }

    private func report(_ counts: Counts) {
        print("""
            Lab Book ownership rehearsal (counts only)
              rows: \(counts.rows)
              distinct device ids: \(counts.deviceIds)
              ids with no registry row: \(counts.unregisteredIds)
              identities with copies: \(counts.identitiesWithCopies)
              identities with conflicts: \(counts.identitiesWithConflicts)
              qualitative rows: \(counts.qualitativeRows)
              repair inserted: \(counts.inserted)
              repair updated: \(counts.updated)
              repair unchanged: \(counts.unchanged)
              repair unbackedKept: \(counts.unbackedKept)
              registered ids rehearsed for delete: \(counts.registeredIdsDeleted)
            """)
    }

    /// Protects §12.10: the rehearsal on a copy of the owner's database. Skipped unless
    /// `NOOP_REHEARSAL_DB` names the copy.
    func testRehearsalOnACopyOfTheOwnersDatabase() async throws {
        guard let path = ProcessInfo.processInfo.environment["NOOP_REHEARSAL_DB"], !path.isEmpty else {
            throw XCTSkip("NOOP_REHEARSAL_DB is not set; the real-data rehearsal runs only on request")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "NOOP_REHEARSAL_DB names no file")
        let counts = try await rehearse(databaseAt: path)
        report(counts)
    }

    /// Protects the rehearsal procedure itself: on a file holding the §13 fixture, with one cell
    /// missing, one wrong and one unbacked, it reports the counts §13 gives and all four properties
    /// hold.
    func testRehearsalProcedureHoldsOnTheSyntheticFixtureFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("labbook-rehearsal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("work.sqlite").path

        do {
            let store = try await WhoopStore(path: path)
            let registry = DeviceRegistryStore(dbQueue: store.registryWriter)
            try registry.add(PairedDevice(id: Fx.b, brand: "WHOOP", model: "WHOOP 4.0", sourceKind: .liveBLE,
                                          capabilities: [.hr], status: .archived, addedAt: 2, lastSeenAt: 2))
            try registry.add(PairedDevice(id: Fx.d, brand: "Oura", model: "Oura Ring 3", sourceKind: .oura,
                                          capabilities: [.hr, .sleep], status: .paired, addedAt: 3, lastSeenAt: 3))
            try registry.add(PairedDevice(id: Fx.n, brand: "WHOOP", model: "WHOOP 4.0", sourceKind: .liveBLE,
                                          capabilities: [.hr], status: .paired, addedAt: 4, lastSeenAt: 4))
            try registry.setActive(Fx.n)
            try Fx.insertRaw(Fx.all, into: store)
            for cell in Fx.cells where cell.key != "ldl" { try Fx.setCell(cell, in: store) }
            try Fx.setCell(Fx.cell("weight", Fx.day3, 98.0), in: store)
            try Fx.setCell(Fx.cell("weight", "2031-02-05", 97.5), in: store)
            try Fx.assertCounts(store, Fx.countsById, "the synthetic file")
            try await store.checkpointWAL()
        }

        let counts = try await rehearse(databaseAt: path)

        var expected = Counts()
        expected.rows = 10
        expected.deviceIds = 5
        expected.unregisteredIds = 1            // C
        expected.identitiesWithCopies = 1       // ldl at t2: F6 and F7
        expected.identitiesWithConflicts = 1    // weight at t3: F3 and F8
        expected.qualitativeRows = 1            // F10
        expected.inserted = 1                   // the ldl cell
        expected.updated = 1                    // the 2031-01-22 weight cell
        expected.unchanged = 4
        expected.unbackedKept = 1               // the 2031-02-05 cell
        expected.registeredIdsDeleted = 4       // A, B, D, N
        XCTAssertEqual(counts, expected)

        // Nothing is left beside the work file.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("labbook-rehearsal-copy-") }
        XCTAssertEqual(leftovers, [])
    }
}
