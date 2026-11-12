import Foundation
import GRDB
import XCTest
@testable import WhoopStore

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §9.2 and §12.3: the one multi-row
// store call, `replaceLabMarkers(deleteIds:upsert:)`, composed of the ownership steps. Seeded with the
// ten rows F1 to F10 of the ownership fixture (labbook-ownership.md §13) and their projected cells.
// The tests call the public function only; the in-transaction steps are the ownership tests'.
//
// Where the projection of a cell is asserted, it is asserted against the ownership calls the function
// is built from, run on a twin store, so these tests restate no projection rule (the rules are the
// ownership specification's, §7.2 and rulings A10, A11, A13, A14).
//
// Synthetic values only: the one Fixture Person.

final class LabMarkerReplaceTests: XCTestCase {
    private typealias F = LabBookOwnershipFixture

    private func seeded() async throws -> WhoopStore { try await F.seededStore() }

    private func rowsById(_ store: WhoopStore) throws -> [String: LabMarkerRow] {
        Dictionary(uniqueKeysWithValues: try F.rows(store).map { ($0.id, $0) })
    }

    func testReplaceWithEmptyArgumentsDoesNothing() async throws {
        let store = try await seeded()
        let before = try F.storageDump(store)
        let cells = try F.labBookCells(store)
        let written = try await store.replaceLabMarkers(deleteIds: [], upsert: [])
        XCTAssertEqual(written, 0)
        XCTAssertEqual(try F.storageDump(store), before)
        XCTAssertEqual(try F.labBookCells(store), cells)
    }

    func testReplaceWithOnlyUpsertsBehavesAsTheOwnerUpsert() async throws {
        let incoming = [
            F.row(id: "weight-1926226800-NEW00001", deviceId: F.n, markerKey: "weight", category: "bodyMeasurement",
                  day: F.day2, takenAt: F.t2, value: 99.5, unit: "kg"),
            F.row(id: "ldl-1927436400-NEW00002", deviceId: F.n, markerKey: "ldl", category: "bloodPanel",
                  day: F.day4, takenAt: F.t4, value: 2.9, unit: "mmol/L"),
        ]
        let replaced = try await seeded()
        let upserted = try await seeded()
        let a = try await replaced.replaceLabMarkers(deleteIds: [], upsert: incoming)
        let b = try await upserted.upsertOwnerLabMarkers(incoming)
        XCTAssertEqual(a, b)
        XCTAssertEqual(try F.storageDump(replaced), try F.storageDump(upserted))
        XCTAssertEqual(try F.allSeries(replaced), try F.allSeries(upserted))
    }

    func testReplaceDeletesMatchTheOwnerDeleteOnATwinStore() async throws {
        for id in [F.f7.id, F.f8.id, F.f9.id, F.f10.id] {
            let replaced = try await seeded()
            let deleted = try await seeded()
            try await replaced.replaceLabMarkers(deleteIds: [id], upsert: [])
            try await deleted.deleteLabMarkerAndCopies(id: id)
            XCTAssertEqual(try F.storageDump(replaced), try F.storageDump(deleted), id)
            XCTAssertEqual(try F.allSeries(replaced), try F.allSeries(deleted), id)
        }
    }

    func testReplaceDeletesAndInsertsInOneCall() async throws {
        let store = try await seeded()
        let moved = F.row(id: "weight-1927440000-NEW00003", deviceId: F.n, markerKey: "weight",
                          category: "bodyMeasurement", day: F.day4, takenAt: F.t4 + 3_600, value: 97.5, unit: "kg",
                          source: "body-record-test")
        let written = try await store.replaceLabMarkers(deleteIds: [F.f4.id], upsert: [moved])
        XCTAssertEqual(written, 1)
        let rows = try rowsById(store)
        XCTAssertNil(rows[F.f4.id])
        XCTAssertEqual(rows[moved.id], moved)
        XCTAssertEqual(rows.count, F.all.count)
    }

    /// `deleteIds: [F7.id]` removes F6 and F7, its copy under another id, and the `ldl` cell.
    func testReplaceDeleteRemovesEveryCopyUnderOtherIds() async throws {
        let store = try await seeded()
        try await store.replaceLabMarkers(deleteIds: [F.f7.id], upsert: [])
        let rows = try rowsById(store)
        XCTAssertNil(rows[F.f6.id])
        XCTAssertNil(rows[F.f7.id])
        XCTAssertEqual(rows.count, F.all.count - 2)
        XCTAssertFalse(try F.labBookCells(store).contains { $0.key == "ldl" && $0.day == F.day2 })
    }

    /// `deleteIds: [F8.id]` removes F8 only; F3, a different reading at the same identity, stays.
    func testReplaceDeleteLeavesAConflictingRow() async throws {
        let store = try await seeded()
        try await store.replaceLabMarkers(deleteIds: [F.f8.id], upsert: [])
        let rows = try rowsById(store)
        XCTAssertNil(rows[F.f8.id])
        XCTAssertEqual(rows[F.f3.id], F.f3)
        XCTAssertEqual(rows.count, F.all.count - 1)
    }

    /// An incoming row at F2's identity under another id and a new id updates F2 where it is.
    func testReplaceUpsertUpdatesTheStoredRowUnderAnotherIdInPlace() async throws {
        let store = try await seeded()
        let incoming = F.row(id: "weight-1926226800-NEW00004", deviceId: F.n, markerKey: "weight",
                             category: "bodyMeasurement", day: F.day2, takenAt: F.t2, value: 99.5, unit: "kg")
        let written = try await store.replaceLabMarkers(deleteIds: [], upsert: [incoming])
        XCTAssertEqual(written, 1)
        let rows = try rowsById(store)
        XCTAssertEqual(rows[F.f2.id]?.value, 99.5)
        XCTAssertEqual(rows[F.f2.id]?.deviceId, F.b, "the stored device id is kept")
        XCTAssertNil(rows[incoming.id])
        XCTAssertEqual(rows.count, F.all.count)
    }

    /// An incoming row at the identity of F6 and F7 updates both, each under its own id.
    func testReplaceUpsertUpdatesEveryCopy() async throws {
        let store = try await seeded()
        var incoming = F.f7
        incoming.id = "ldl-1926226800-NEW00005"
        incoming.value = 3.5
        let written = try await store.replaceLabMarkers(deleteIds: [], upsert: [incoming])
        XCTAssertEqual(written, 2)
        let rows = try rowsById(store)
        XCTAssertEqual(rows[F.f6.id]?.value, 3.5)
        XCTAssertEqual(rows[F.f7.id]?.value, 3.5)
        XCTAssertEqual(rows[F.f6.id]?.deviceId, F.b)
        XCTAssertEqual(rows[F.f7.id]?.deviceId, F.n)
    }

    /// The deletes run first: an upsert at the identity they emptied inserts the row as given.
    func testReplaceEvaluatesUpsertsAfterDeletes() async throws {
        let store = try await seeded()
        var incoming = F.f7
        incoming.id = "ldl-1926226800-NEW00006"
        incoming.value = 3.1
        try await store.replaceLabMarkers(deleteIds: [F.f7.id], upsert: [incoming])
        let atIdentity = try F.rows(store).filter { $0.markerKey == "ldl" && $0.takenAt == F.t2 }
        XCTAssertEqual(atIdentity, [incoming])
    }

    func testReplaceSkipsAnUnknownId() async throws {
        let store = try await seeded()
        let before = try F.storageDump(store)
        try await store.replaceLabMarkers(deleteIds: ["no-such-row"], upsert: [])
        XCTAssertEqual(try F.storageDump(store), before)
    }

    /// A primary-key violation in the upsert rolls the deletes back too.
    func testReplaceRollsBackEverythingWhenAnInsertFails() async throws {
        let store = try await seeded()
        let before = try F.storageDump(store)
        let cells = try F.allSeries(store)
        let clash = F.row(id: F.f1.id, deviceId: F.n, markerKey: "ldl", category: "bloodPanel", day: F.day4,
                          takenAt: F.t4, value: 2.8, unit: "mmol/L")
        do {
            try await store.replaceLabMarkers(deleteIds: [F.f2.id, F.f7.id], upsert: [clash])
            XCTFail("the primary-key violation must surface")
        } catch {}
        XCTAssertEqual(try F.storageDump(store), before, "every deleted row is back, byte-identical")
        XCTAssertEqual(try F.allSeries(store), cells)
    }

    func testNoteRowWithNilValueProjectsNothing() async throws {
        let store = try await seeded()
        let note = F.row(id: "fixture_scan_note-1927436400-NEW00007", deviceId: F.n, markerKey: "fixture_scan_note",
                         category: "imaging", day: F.day4, takenAt: F.t4, value: nil, valueText: "Fixture note",
                         unit: "", source: "body-record-test")
        try await store.replaceLabMarkers(deleteIds: [], upsert: [note])
        XCTAssertFalse(try F.allSeries(store).contains { $0.key == "fixture_scan_note" })
    }

    func testScanWeightRowAndManualWeightRowAtOneInstantAreTwoRows() async throws {
        let store = try await seeded()
        let scanWeight = F.row(id: "weight-1925622000-NEW00008", deviceId: F.n, markerKey: "weight",
                               category: "bodyMeasurement", day: F.day1, takenAt: F.t1, value: 100.4, unit: "kg",
                               source: "body-record-test")
        try await store.replaceLabMarkers(deleteIds: [], upsert: [scanWeight])
        let atInstant = try F.rows(store).filter { $0.markerKey == "weight" && $0.takenAt == F.t1 }
        XCTAssertEqual(Set(atInstant.map(\.id)), [F.f1.id, scanWeight.id])
        XCTAssertEqual(try rowsById(store)[F.f1.id], F.f1)
    }

    func testReplaceTouchesNoRowOutsideItsArguments() async throws {
        let store = try await seeded()
        var incoming = F.f4
        incoming.value = 97.0
        try await store.replaceLabMarkers(deleteIds: [F.f9.id], upsert: [incoming])
        let rows = try rowsById(store)
        for row in F.all where row.id != F.f4.id && row.id != F.f9.id {
            XCTAssertEqual(rows[row.id], row, row.id)
        }
        XCTAssertEqual(rows[F.f4.id]?.value, 97.0)
        XCTAssertNil(rows[F.f9.id])
    }
}
