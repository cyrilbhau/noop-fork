import Foundation
import GRDB
import XCTest
@testable import WhoopStore

// API ASSUMED BY THESE TESTS
//
// No member that does not exist. Every call is to the API the Lab Book ownership change already
// declares (docs/personal/superapp/specs/labbook-ownership.md §6.1):
//
//   @discardableResult public func WhoopStore.upsertOwnerLabMarkers(_ rows: [LabMarkerRow]) async throws -> Int
//   @discardableResult public func WhoopStore.deleteLabMarkerAndCopies(id: String) async throws -> [String]
//   @discardableResult public func WhoopStore.upsertLabMarkers(_ rows: [LabMarkerRow]) async throws -> Int
//   @discardableResult public func WhoopStore.deleteLabMarker(id: String) async throws -> Bool
//
// What these tests pin (docs/personal/superapp/specs/RULINGS-ADDENDUM.md):
//
//   A14  A value stays projected while any stored reading holds it. When a reading is deleted or
//        edited, its number is treated as having left the projected cell only if no remaining
//        reading of that marker and day still holds that number.
//   A13  An explicit write supersedes a trace. A new reading for a marker and day whose cell no
//        stored row backs takes the cell, and deleting that reading removes the cell.
//
// The A14 scenario is one marker on one day with three readings:
//
//   "z-a"  device A, instant T,            value 3.0
//   "b"    device N, instant T,            value 3.4
//   "e"    device N, one hour before T,    value 3.4
//
// "z-a" and "b" conflict at one instant and "z-a" has the greater id, so a freshly derived cell
// would hold 3.0. The stored cell holds 3.4, the value of "b", and ruling A11 keeps it. "e" is an
// unrelated earlier reading that happens to share the number.
//
// Synthetic values only: the one "Fixture Person" of labbook-ownership.md §13.

final class LabMarkerProjectionValueTests: XCTestCase {

    private typealias Fx = LabBookOwnershipFixture

    private static let marker = "ldl"
    private static let otherDay = Fx.day4

    private static func reading(_ id: String, _ deviceId: String, _ takenAt: Int, _ value: Double) -> LabMarkerRow {
        Fx.row(id: id, deviceId: deviceId, markerKey: marker, category: "bloodPanel", day: Fx.day3,
               takenAt: takenAt, value: value, unit: "mmol/L")
    }

    private static let za = reading("z-a", Fx.a, Fx.t3, 3.0)
    private static let b = reading("b", Fx.n, Fx.t3, 3.4)
    private static func e(_ value: Double = 3.4) -> LabMarkerRow { reading("e", Fx.n, Fx.t3a, value) }

    /// The three readings and the cell at 3.4, written with raw SQL.
    private func conflictDayStore(e: LabMarkerRow = LabMarkerProjectionValueTests.e()) async throws -> WhoopStore {
        let store = try await Fx.emptyStoreWithRegistry()
        try Fx.insertRaw([Self.za, Self.b, e], into: store)
        try Fx.setCell(Fx.cell(Self.marker, Fx.day3, 3.4), in: store)
        return store
    }

    private func cells(_ store: WhoopStore) throws -> [Fx.Cell] {
        try Fx.labBookCells(store)
    }

    private func ids(_ store: WhoopStore) throws -> [String] {
        try Fx.rows(store).map(\.id).sorted()
    }

    // MARK: - A14: a deleted reading whose number another reading still holds

    func testDeletingWithCopiesAReadingThatSharesTheProjectedNumberKeepsTheCell() async throws {
        let store = try await conflictDayStore()

        let deleted = try await store.deleteLabMarkerAndCopies(id: "e")

        XCTAssertEqual(deleted, ["e"])
        XCTAssertEqual(try ids(store), ["b", "z-a"])
        XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Fx.day3, 3.4)],
                       "b still holds 3.4, so the number did not leave the cell")
    }

    func testDeletingByIdAReadingThatSharesTheProjectedNumberKeepsTheCell() async throws {
        let store = try await conflictDayStore()

        let deleted = try await store.deleteLabMarker(id: "e")

        XCTAssertTrue(deleted)
        XCTAssertEqual(try ids(store), ["b", "z-a"])
        XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Fx.day3, 3.4)],
                       "b still holds 3.4, so the number did not leave the cell")
    }

    // MARK: - A14: an edited reading whose former number another reading still holds

    func testOwnerValueEditOfAReadingThatSharesTheProjectedNumberKeepsTheCell() async throws {
        let store = try await conflictDayStore()
        var edit = Self.e()
        edit.value = 3.3

        let written = try await store.upsertOwnerLabMarkers([edit])

        XCTAssertEqual(written, 1)
        XCTAssertEqual(try Fx.rows(store).first { $0.id == "e" }?.value, 3.3)
        XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Fx.day3, 3.4)],
                       "b still holds 3.4, so the number did not leave the cell")
    }

    func testPerDeviceValueEditOfAReadingThatSharesTheProjectedNumberKeepsTheCell() async throws {
        let store = try await conflictDayStore()
        var edit = Self.e()
        edit.value = 3.3

        try await store.upsertLabMarkers([edit])

        XCTAssertEqual(try Fx.rows(store).first { $0.id == "e" }?.value, 3.3)
        XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Fx.day3, 3.4)],
                       "b still holds 3.4, so the number did not leave the cell")
    }

    func testOwnerDateEditOfAReadingThatSharesTheProjectedNumberKeepsTheCell() async throws {
        let store = try await conflictDayStore()
        var edit = Self.e()
        edit.day = Self.otherDay

        let written = try await store.upsertOwnerLabMarkers([edit])

        XCTAssertEqual(written, 1)
        XCTAssertEqual(try Fx.rows(store).first { $0.id == "e" }?.day, Self.otherDay)
        XCTAssertEqual(try cells(store), [
            Fx.cell(Self.marker, Fx.day3, 3.4),
            Fx.cell(Self.marker, Self.otherDay, 3.4),
        ], "b still holds 3.4 on the day e left, and e projects on the day it moved to")
    }

    func testPerDeviceDateEditOfAReadingThatSharesTheProjectedNumberKeepsTheCell() async throws {
        let store = try await conflictDayStore()
        var edit = Self.e()
        edit.day = Self.otherDay

        try await store.upsertLabMarkers([edit])

        XCTAssertEqual(try Fx.rows(store).first { $0.id == "e" }?.day, Self.otherDay)
        XCTAssertEqual(try cells(store), [
            Fx.cell(Self.marker, Fx.day3, 3.4),
            Fx.cell(Self.marker, Self.otherDay, 3.4),
        ], "b still holds 3.4 on the day e left, and e projects on the day it moved to")
    }

    // MARK: - A14 controls

    /// e holds 3.3, which the cell does not hold: its delete never touched the cell.
    func testDeletingAReadingWithAnotherNumberLeavesTheCell() async throws {
        for perId in [false, true] {
            let store = try await conflictDayStore(e: Self.e(3.3))

            if perId {
                let deleted = try await store.deleteLabMarker(id: "e")
                XCTAssertTrue(deleted)
            } else {
                let deleted = try await store.deleteLabMarkerAndCopies(id: "e")
                XCTAssertEqual(deleted, ["e"])
            }

            XCTAssertEqual(try ids(store), ["b", "z-a"])
            XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Fx.day3, 3.4)], "per-id delete: \(perId)")
        }
    }

    /// b is the only reading that holds 3.4: deleting it takes the number out of the cell, which is
    /// re-derived from the readings that remain.
    func testDeletingTheOnlyHolderOfTheProjectedNumberMovesTheCell() async throws {
        for perId in [false, true] {
            let store = try await conflictDayStore(e: Self.e(3.3))

            if perId {
                let deleted = try await store.deleteLabMarker(id: "b")
                XCTAssertTrue(deleted)
            } else {
                let deleted = try await store.deleteLabMarkerAndCopies(id: "b")
                XCTAssertEqual(deleted, ["b"])
            }

            XCTAssertEqual(try ids(store), ["e", "z-a"])
            XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Fx.day3, 3.0)],
                           "per-id delete: \(perId): z-a is now the latest reading of the day")
        }
    }

    /// Once e is gone b is the only holder; deleting b then moves the cell.
    func testDeletingEveryHolderOfTheProjectedNumberMovesTheCellOnTheLastOne() async throws {
        let store = try await conflictDayStore()

        try await store.deleteLabMarkerAndCopies(id: "e")
        XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Fx.day3, 3.4)])

        try await store.deleteLabMarkerAndCopies(id: "b")
        XCTAssertEqual(try ids(store), ["z-a"])
        XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Fx.day3, 3.0)])
    }

    /// The only holder edited to another number: the number left the cell, which is re-derived.
    func testValueEditOfTheOnlyHolderOfTheProjectedNumberMovesTheCell() async throws {
        let store = try await conflictDayStore(e: Self.e(3.3))
        var edit = Self.b
        edit.value = 3.5

        try await store.upsertOwnerLabMarkers([edit])

        XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Fx.day3, 3.0)],
                       "no reading holds 3.4 any more; z-a is the latest reading of the day")
    }

    // MARK: - A13: an explicit write supersedes a trace

    /// A cell no stored row backs is a trace (ruling A11). A reading the owner adds for that marker
    /// and day takes the cell, and deleting that reading removes the cell.
    func testOwnerWriteTakesAnUnbackedCellAndItsDeleteRemovesTheCell() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        try Fx.setCell(Fx.cell(Self.marker, Fx.day3, 2.6), in: store)
        XCTAssertEqual(try ids(store), [])

        try await store.upsertOwnerLabMarkers([Self.b])
        XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Fx.day3, 3.4)],
                       "the reading the owner entered outranks the trace")

        let deleted = try await store.deleteLabMarkerAndCopies(id: "b")
        XCTAssertEqual(deleted, ["b"])
        XCTAssertEqual(try ids(store), [])
        XCTAssertEqual(try cells(store), [], "the cell held the deleted reading's number and nothing backs it")
    }

    func testPerDeviceWriteTakesAnUnbackedCellAndItsDeleteRemovesTheCell() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        try Fx.setCell(Fx.cell(Self.marker, Fx.day3, 2.6), in: store)

        try await store.upsertLabMarkers([Self.b])
        XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Fx.day3, 3.4)],
                       "the reading the owner entered outranks the trace")

        let deleted = try await store.deleteLabMarker(id: "b")
        XCTAssertTrue(deleted)
        XCTAssertEqual(try cells(store), [], "the cell held the deleted reading's number and nothing backs it")
    }

    /// A write to ANOTHER day leaves the trace alone (the half of A11 that A13 does not override).
    func testOwnerWriteOnAnotherDayLeavesAnUnbackedCell() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        try Fx.setCell(Fx.cell(Self.marker, Self.otherDay, 2.6), in: store)

        try await store.upsertOwnerLabMarkers([Self.b])
        try await store.deleteLabMarkerAndCopies(id: "b")

        XCTAssertEqual(try cells(store), [Fx.cell(Self.marker, Self.otherDay, 2.6)])
    }
}
