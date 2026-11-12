import Foundation
import GRDB
import XCTest
@testable import WhoopStore

// Review C6, finding P2: editing the day's LATEST reading bypassed ruling A19
// (docs/personal/superapp/specs/RULINGS-ADDENDUM.md). A14 holds literally: when the reading removed
// or edited was the day's latest, the projected value stays while any remaining reading of that
// marker and day holds the same number.
//
// The scenario is one marker on one day with two readings at distinct instants:
//
//   "older"   device N, one hour before T,  value 100
//   "latest"  device N, instant T,          value 100
//
// and the cell at 100. Editing only "latest" to 98 leaves "older" holding 100, so the cell keeps 100.
//
// Synthetic values only: the one "Fixture Person" of labbook-ownership.md §13.

final class CodexReviewC6Tests: XCTestCase {

    private typealias Fx = LabBookOwnershipFixture

    private static let marker = "weight"

    private static func reading(_ id: String, _ takenAt: Int, _ value: Double) -> LabMarkerRow {
        Fx.row(id: id, deviceId: Fx.n, markerKey: marker, category: "bodyMeasurement", day: Fx.day3,
               takenAt: takenAt, value: value, unit: "kg")
    }

    private func store(older: Double, latest: Double, cell: Double) async throws -> WhoopStore {
        let store = try await Fx.emptyStoreWithRegistry()
        try Fx.insertRaw([Self.reading("older", Fx.t3a, older), Self.reading("latest", Fx.t3, latest)],
                         into: store)
        try Fx.setCell(Fx.cell(Self.marker, Fx.day3, cell), in: store)
        return store
    }

    private func values(_ store: WhoopStore) throws -> [String] {
        try Fx.rows(store).sorted { $0.id > $1.id }.map { "\($0.id):\($0.value ?? .nan)" }
    }

    func testEditingTheLatestReadingKeepsTheCellWhileAnEarlierReadingHoldsItsNumber() async throws {
        for perDevice in [false, true] {
            let store = try await store(older: 100, latest: 100, cell: 100)
            let edit = Self.reading("latest", Fx.t3, 98)

            if perDevice {
                try await store.upsertLabMarkers([edit])
            } else {
                try await store.upsertOwnerLabMarkers([edit])
            }

            XCTAssertEqual(try values(store), ["older:100.0", "latest:98.0"], "per-device: \(perDevice)")
            XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell(Self.marker, Fx.day3, 100)],
                           "per-device: \(perDevice): older still holds 100, so the number did not leave the cell")
        }
    }

    /// One transaction: the latest reading leaves 100, then the earlier reading takes 100. After
    /// every write a remaining reading holds 100, so the cell keeps it.
    func testBatchThatLeavesTheProjectedNumberHeldByAnEarlierReadingKeepsTheCell() async throws {
        let store = try await store(older: 99, latest: 100, cell: 100)

        try await store.upsertOwnerLabMarkers([Self.reading("latest", Fx.t3, 98),
                                               Self.reading("older", Fx.t3a, 100)])

        XCTAssertEqual(try values(store), ["older:100.0", "latest:98.0"])
        XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell(Self.marker, Fx.day3, 100)])
    }

    /// Guard: when no remaining reading holds the projected number, an edit of the latest reading
    /// still moves the cell to it.
    func testEditingTheLatestReadingMovesTheCellWhenNoOtherReadingHoldsItsNumber() async throws {
        for perDevice in [false, true] {
            let store = try await store(older: 99, latest: 100, cell: 100)
            let edit = Self.reading("latest", Fx.t3, 98)

            if perDevice {
                try await store.upsertLabMarkers([edit])
            } else {
                try await store.upsertOwnerLabMarkers([edit])
            }

            XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell(Self.marker, Fx.day3, 98)],
                           "per-device: \(perDevice)")
        }
    }

    /// Guard (§7.2): a NEW reading later than every other still takes the cell, even though an
    /// earlier reading holds the projected number.
    func testANewLatestReadingStillTakesTheCell() async throws {
        for perDevice in [false, true] {
            let store = try await store(older: 100, latest: 100, cell: 100)
            let added = Self.reading("newest", Fx.t3 + 600, 97)

            if perDevice {
                try await store.upsertLabMarkers([added])
            } else {
                try await store.upsertOwnerLabMarkers([added])
            }

            XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell(Self.marker, Fx.day3, 97)],
                           "per-device: \(perDevice)")
        }
    }
}
