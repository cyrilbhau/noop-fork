import Foundation
import GRDB
import XCTest
@testable import WhoopStore

// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/labbook-ownership.md §6.1, in
// Packages/WhoopStore/Sources/WhoopStore/LabMarkerStore.swift:
//
//   public struct LabBookProjectionRepair: Equatable, Sendable {
//       public let inserted: Int      // cells that were missing
//       public let updated: Int       // cells replaced by the correct value
//       public let unchanged: Int     // cells already correct
//       public let unbackedKept: Int  // cells left exactly as stored (§7.3)
//   }
//   @discardableResult public func WhoopStore.repairLabBookProjection() async throws -> LabBookProjectionRepair
//
// No initialiser of `LabBookProjectionRepair` is called: results are read field by field, and two
// results are compared with `==`.
//
// Also called, and declared in the API block of LabMarkerOwnershipStoreTests.swift:
//   WhoopStore.upsertOwnerLabMarkers(_:), WhoopStore.deleteLabMarkerAndCopies(id:),
//   WhoopStore.upsertLabMarkers(_:) (exists), WhoopStore.allLabMarkers().
//
// Specification §7.3 (the repair), §12.2 (cases 44 to 51), §12.5 (case 73), §12.8 (faults F15 to
// F17) and §13 (repair variants V1 to V5). Synthetic values only.

final class LabBookProjectionRepairTests: XCTestCase {

    private typealias Fx = LabBookOwnershipFixture

    // MARK: - Helpers

    private func assertRepair(_ repair: LabBookProjectionRepair, inserted: Int, updated: Int, unchanged: Int,
                              unbackedKept: Int, _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(repair.inserted, inserted, "inserted. \(message)", file: file, line: line)
        XCTAssertEqual(repair.updated, updated, "updated. \(message)", file: file, line: line)
        XCTAssertEqual(repair.unchanged, unchanged, "unchanged. \(message)", file: file, line: line)
        XCTAssertEqual(repair.unbackedKept, unbackedKept, "unbackedKept. \(message)", file: file, line: line)
    }

    /// The six cells with the 2031-01-22 weight cell replaced.
    private func cells(day3Weight value: Double) -> [Fx.Cell] {
        Fx.cells.map { $0.key == "weight" && $0.day == Fx.day3 ? Fx.cell("weight", Fx.day3, value) : $0 }
    }

    // MARK: - §12.2 cases 44 to 47 (§13 variants V1 to V4)

    /// Protects V1: a cell that is missing is inserted with the day's latest reading across every id.
    func testRepairInsertsAMissingCell() async throws {
        let store = try await Fx.seededStore()
        try Fx.removeLabBookCell("weight", Fx.day3, in: store)
        XCTAssertEqual(try Fx.labBookCells(store).count, 5)
        try Fx.assertCounts(store, Fx.countsById, "before")

        let repair = try await store.repairLabBookProjection()

        assertRepair(repair, inserted: 1, updated: 0, unchanged: 5, unbackedKept: 0)
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells, "98.4: F8, the greater id at the latest instant")
        try Fx.assertCounts(store, Fx.countsById, "after")
    }

    /// Protects V2 as ruling A11 (RULINGS-ADDENDUM.md) re-decides it: a cell holding another of the
    /// day's readings is left exactly as stored. Its value is a reading the owner entered, and with
    /// two ids holding different readings the repair cannot know which was meant. Superseded by
    /// rulings A10 and A11: this test was `testRepairCorrectsACellHoldingAnotherOfTheDaysReadings` and
    /// asserted `updated == 1` and a cell rewritten to 98.4.
    func testRepairKeepsACellHoldingAnotherOfTheDaysReadings() async throws {
        // 98.0 is F3's value (the same instant, the smaller id); 98.2 is F9's (an hour earlier).
        for held in [98.0, 98.2] {
            let store = try await Fx.seededStore()
            try Fx.setCell(Fx.cell("weight", Fx.day3, held), in: store)
            try Fx.assertCounts(store, Fx.countsById, "before, cell \(held)")

            let repair = try await store.repairLabBookProjection()

            XCTAssertEqual(repair.inserted, 0, "cell \(held)")
            XCTAssertEqual(repair.updated, 0, "cell \(held)")
            XCTAssertEqual(repair.unchanged + repair.unbackedKept, 6, "cell \(held)")
            XCTAssertEqual(try Fx.labBookCells(store), cells(day3Weight: held), "cell \(held) stays")
            try Fx.assertCounts(store, Fx.countsById, "after, cell \(held)")
        }
    }

    /// Protects V3 and decision D8 (fault F16): a cell whose value no row of that marker and day holds
    /// is the last trace of a reading that is gone. It is left exactly as stored. The comparison is
    /// `==` on the stored doubles: one unit in the last place either side of a held value is unbacked.
    func testRepairKeepsACellWhoseValueNoRowHolds() async throws {
        let unbacked: [Double] = [90.0, (98.0).nextUp, (98.0).nextDown, (98.2).nextUp, (98.4).nextDown,
                                  (98.4).nextUp, 0.0, -98.0]
        for value in unbacked {
            let store = try await Fx.seededStore()
            try Fx.setCell(Fx.cell("weight", Fx.day3, value), in: store)
            try Fx.assertCounts(store, Fx.countsById, "before, cell \(value)")

            let repair = try await store.repairLabBookProjection()

            assertRepair(repair, inserted: 0, updated: 0, unchanged: 5, unbackedKept: 1, "cell \(value)")
            let after = try Fx.labBookCells(store)
            XCTAssertEqual(after, cells(day3Weight: value), "cell \(value) stays")
            XCTAssertEqual(after.first { $0.key == "weight" && $0.day == Fx.day3 }?.value.bitPattern,
                           value.bitPattern, "cell \(value) is bit-identical")
            try Fx.assertCounts(store, Fx.countsById, "after, cell \(value)")
        }
        // A value held by a row of ANOTHER day or ANOTHER marker does not back the cell: 99.2 is F2's
        // weight of 2031-01-15, and 3.0 is the ldl reading.
        for value in [99.2, 3.0] {
            let store = try await Fx.seededStore()
            try Fx.setCell(Fx.cell("weight", Fx.day3, value), in: store)
            let repair = try await store.repairLabBookProjection()
            assertRepair(repair, inserted: 0, updated: 0, unchanged: 5, unbackedKept: 1, "cell \(value)")
            XCTAssertEqual(try Fx.labBookCells(store), cells(day3Weight: value))
        }
    }

    /// Protects V4 (fault F15): a cell for a day on which no reading exists is left as stored.
    func testRepairKeepsACellWithNoRowsThatDay() async throws {
        let store = try await Fx.seededStore()
        let extra = Fx.cell("weight", "2031-02-05", 97.5)
        try Fx.setCell(extra, in: store)
        try Fx.assertCounts(store, Fx.countsById, "before")

        let repair = try await store.repairLabBookProjection()

        assertRepair(repair, inserted: 0, updated: 0, unchanged: 6, unbackedKept: 1)
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells + [extra])
        try Fx.assertCounts(store, Fx.countsById, "after")

        // Also kept: a cell for a marker with no row at all, and a cell on a day whose only reading
        // of that marker holds text (F10), for which §7.3 step 1 folds no expected cell.
        let noMarker = Fx.cell("fixture_absent", Fx.day1, 97.5)
        let textOnly = Fx.cell("fixture_note", Fx.day2, 97.5)
        try Fx.setCell(noMarker, in: store)
        try Fx.setCell(textOnly, in: store)
        let second = try await store.repairLabBookProjection()
        assertRepair(second, inserted: 0, updated: 0, unchanged: 6, unbackedKept: 3)
        XCTAssertEqual(try Fx.labBookCells(store),
                       [noMarker, textOnly] + Fx.cells + [extra])
    }

    /// Protects V5: nothing to do is reported as six unchanged cells and changes nothing.
    func testRepairOfACorrectProjectionReportsSixUnchangedAndWritesNothing() async throws {
        let store = try await Fx.seededStore()
        try Fx.assertCounts(store, Fx.countsById, "before")
        let seriesBefore = try Fx.allSeries(store)

        let repair = try await store.repairLabBookProjection()

        assertRepair(repair, inserted: 0, updated: 0, unchanged: 6, unbackedKept: 0)
        XCTAssertEqual(try Fx.allSeries(store), seriesBefore)
        try Fx.assertCounts(store, Fx.countsById, "after")
    }

    // MARK: - §12.2 cases 48 to 51

    /// Protects §7.3: the repair is idempotent. A second and a third run insert and update nothing
    /// and report the same counts as each other.
    func testRepairIsIdempotent() async throws {
        let store = try await Fx.seededStore()
        try Fx.removeLabBookCell("ldl", Fx.day2, in: store)                     // V1 shape
        try Fx.setCell(Fx.cell("weight", Fx.day3, 98.0), in: store)             // V2 shape
        try Fx.setCell(Fx.cell("weight", Fx.day1, 90.0), in: store)             // V3 shape
        try Fx.setCell(Fx.cell("weight", "2031-02-05", 97.5), in: store)        // V4 shape
        try Fx.assertCounts(store, Fx.countsById, "before")

        let first = try await store.repairLabBookProjection()
        // Superseded by rulings A10 and A11: this asserted `updated: 1` and a V2 cell rewritten to
        // 98.4. The V2 cell holds a stored reading's value and is kept; which count it falls in is
        // not ruled, so the two "left as stored" counts are asserted as a sum.
        XCTAssertEqual(first.inserted, 1, "first run")
        XCTAssertEqual(first.updated, 0, "first run")
        XCTAssertEqual(first.unchanged + first.unbackedKept, 6, "first run")
        let expected = [
            Fx.cell("ldl", Fx.day2, 3.0), Fx.cell("waist", Fx.day1, 100.0), Fx.cell("weight", Fx.day1, 90.0),
            Fx.cell("weight", Fx.day2, 99.2), Fx.cell("weight", Fx.day3, 98.0), Fx.cell("weight", Fx.day4, 97.6),
            Fx.cell("weight", "2031-02-05", 97.5),
        ]
        XCTAssertEqual(try Fx.labBookCells(store), expected)

        let second = try await store.repairLabBookProjection()
        XCTAssertEqual(second.inserted, 0, "second run")
        XCTAssertEqual(second.updated, 0, "second run")
        XCTAssertEqual(second.unchanged + second.unbackedKept, 7, "second run")
        XCTAssertEqual(try Fx.labBookCells(store), expected)

        let third = try await store.repairLabBookProjection()
        XCTAssertEqual(third, second, "every later run reports the same")
        XCTAssertEqual(try Fx.labBookCells(store), expected)
        try Fx.assertCounts(store, Fx.countsById, "after three runs")
    }

    /// Protects: with no reading and no cell there is nothing to count and nothing is created.
    func testRepairOnAnEmptyTableChangesNothing() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        try Fx.assertCounts(store, [:], "before")
        let seriesBefore = try Fx.allSeries(store)

        let repair = try await store.repairLabBookProjection()

        assertRepair(repair, inserted: 0, updated: 0, unchanged: 0, unbackedKept: 0)
        XCTAssertEqual(try Fx.allSeries(store), seriesBefore)
        try Fx.assertCounts(store, [:], "after")
    }

    /// Protects decision D8 at its limit (fault F15): every reading was removed by an earlier strap
    /// delete and only the six projected cells are left. The repair keeps all six.
    func testRepairKeepsEveryCellWhenNoReadingSurvives() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        for cell in Fx.cells { try Fx.setCell(cell, in: store) }
        try Fx.assertCounts(store, [:], "before")

        let repair = try await store.repairLabBookProjection()

        assertRepair(repair, inserted: 0, updated: 0, unchanged: 0, unbackedKept: 6)
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells)
        try Fx.assertCounts(store, [:], "after")
    }

    /// Protects fault F17: the repair reads and writes `metricSeries` rows under `lab-book` only. A
    /// strap's series, a computed sibling's and an import's, on the very keys and days it repairs, are
    /// bit-identical afterwards.
    func testRepairLeavesMetricSeriesOfOtherSourcesUntouched() async throws {
        let store = try await Fx.seededStore()
        let others = [
            Fx.Cell(deviceId: Fx.a, key: "weight", day: Fx.day3, value: 97.5),
            Fx.Cell(deviceId: Fx.n, key: "weight", day: Fx.day3, value: 90.0),
            Fx.Cell(deviceId: Fx.n + DeviceRegistryStore.computedSuffix, key: "ldl", day: Fx.day2, value: 97.5),
            Fx.Cell(deviceId: "nutrition-csv", key: "weight", day: "2031-02-05", value: 97.5),
            Fx.Cell(deviceId: "lab-book-other", key: "weight", day: Fx.day3, value: 90.0),
        ]
        for cell in others { try Fx.setCell(cell, in: store) }
        try Fx.removeLabBookCell("ldl", Fx.day2, in: store)
        try Fx.setCell(Fx.cell("weight", Fx.day3, 98.0), in: store)
        try Fx.assertCounts(store, Fx.countsById, "before")
        let othersBefore = try Fx.allSeries(store).filter { $0.deviceId != WhoopStore.labBookSourceId }
        XCTAssertEqual(othersBefore.count, 5)

        let repair = try await store.repairLabBookProjection()

        // Superseded by rulings A10 and A11: this asserted `updated: 1` and the 2031-01-22 cell
        // rewritten to 98.4. That cell holds F3's value, a stored reading, and is kept.
        XCTAssertEqual(repair.inserted, 1)
        XCTAssertEqual(repair.updated, 0)
        XCTAssertEqual(repair.unchanged + repair.unbackedKept, 5)
        XCTAssertEqual(try Fx.labBookCells(store), cells(day3Weight: 98.0))
        XCTAssertEqual(try Fx.allSeries(store).filter { $0.deviceId != WhoopStore.labBookSourceId }, othersBefore)
        try Fx.assertCounts(store, Fx.countsById, "after")
    }

    /// Protects §8.3: the repair rewrites derived cells only. Every `labMarker` row is byte-identical
    /// after a run that inserted, updated and kept cells.
    func testRepairDoesNotChangeAnyLabMarkerRow() async throws {
        let store = try await Fx.seededStore()
        try Fx.removeLabBookCell("ldl", Fx.day2, in: store)
        try Fx.setCell(Fx.cell("weight", Fx.day3, 98.0), in: store)
        try Fx.setCell(Fx.cell("weight", Fx.day1, 90.0), in: store)
        try Fx.setCell(Fx.cell("weight", "2031-02-05", 97.5), in: store)
        let before = try Fx.storageDump(store)
        try Fx.assertCounts(store, Fx.countsById, "before")

        for run in 1...2 {
            try await store.repairLabBookProjection()
            XCTAssertEqual(try Fx.storageDump(store), before, "run \(run)")
            try Fx.assertCounts(store, Fx.countsById, "after run \(run)")
        }
    }

    // MARK: - §12.5 case 73

    /// Protects §8.5: on an install whose rows all sit under one id and were written by the per-id
    /// function, the repair finds every cell correct and writes nothing.
    func testSingleIdInstallProjectionIsUnchangedByTheRepair() async throws {
        let store = try await WhoopStore.inMemory()
        for row in Fx.singleIdRows { try await store.upsertLabMarkers([row]) }
        try Fx.assertCounts(store, [Fx.a: 8], "before")
        // Under one id the per-id projection and the all-id projection name the same six cells.
        XCTAssertEqual(try Fx.labBookCells(store), Fx.cells)
        let rowsBefore = try Fx.storageDump(store)
        let seriesBefore = try Fx.allSeries(store)

        let repair = try await store.repairLabBookProjection()

        assertRepair(repair, inserted: 0, updated: 0, unchanged: 6, unbackedKept: 0)
        XCTAssertEqual(try Fx.allSeries(store), seriesBefore)
        XCTAssertEqual(try Fx.storageDump(store), rowsBefore)
        try Fx.assertCounts(store, [Fx.a: 8], "after")
    }

    // MARK: - Generated input

    /// Protects, over 120 generated tables from a fixed seed with no cell stored: the repair inserts
    /// exactly one cell per marker and day that has a numeric reading, holding the reading with the
    /// greatest `takenAt` and then the greatest `id` across every id; rows are never changed; a second
    /// run finds everything correct; and the result does not depend on the order the rows were stored.
    func testGeneratedTablesRepairToTheLatestReadingPerMarkerAndDay() async throws {
        var generator = Fx.Generator(seed: 0x1AB0_0C0F_F1CE_0004)
        let devices = [Fx.a, Fx.b, Fx.c, Fx.d, Fx.n]
        var tiesSeen = 0

        for round in 0..<120 {
            var rows: [LabMarkerRow] = []
            var taken = Set<String>()
            for index in 0..<generator.below(14) {
                let device = generator.pick(devices)
                let marker = ["weight", "weight", "waist", "ldl"][generator.below(4)]
                let instant = [Fx.t3a, Fx.t3 - 1, Fx.t3, Fx.t3 + 1, Fx.t4][generator.below(5)]
                guard taken.insert("\(device)|\(marker)|\(instant)").inserted else { continue }
                let value: Double? = [97.6, 98.0, 98.2, 98.4, nil][generator.below(5)]
                rows.append(Fx.row(id: "g\(generator.below(90) + 10)-\(round)-\(index)", deviceId: device,
                                   markerKey: marker, category: "bodyMeasurement",
                                   day: instant == Fx.t4 ? Fx.day4 : Fx.day3, takenAt: instant, value: value,
                                   valueText: value == nil ? "clear" : nil, unit: "kg"))
            }
            var best: [String: LabMarkerRow] = [:]
            for row in rows where row.value != nil {
                let cellKey = row.markerKey + "|" + row.day
                if let held = best[cellKey] {
                    if held.takenAt == row.takenAt { tiesSeen += 1 }
                    if (held.takenAt, held.id) > (row.takenAt, row.id) { continue }
                }
                best[cellKey] = row
            }
            let expected = best.values.map { Fx.cell($0.markerKey, $0.day, $0.value!) }
                .sorted { ($0.key, $0.day) < ($1.key, $1.day) }

            for (name, order) in [("as generated", rows), ("shuffled", generator.shuffled(rows))] {
                let context = "round \(round), \(name)"
                let store = try await Fx.emptyStoreWithRegistry()
                try Fx.insertRaw(order, into: store)
                let before = try Fx.storageDump(store)
                let countsBefore = try Fx.countsById(store)

                let first = try await store.repairLabBookProjection()
                assertRepair(first, inserted: expected.count, updated: 0, unchanged: 0, unbackedKept: 0, context)
                XCTAssertEqual(try Fx.labBookCells(store), expected, context)
                XCTAssertEqual(try Fx.storageDump(store), before, context)
                XCTAssertEqual(try Fx.countsById(store), countsBefore, context)

                let second = try await store.repairLabBookProjection()
                assertRepair(second, inserted: 0, updated: 0, unchanged: expected.count, unbackedKept: 0, context)
                XCTAssertEqual(try Fx.labBookCells(store), expected, context)
            }
        }
        XCTAssertGreaterThan(tiesSeen, 20, "too few generated days held two readings at one instant")
    }

    /// Protects: the write path and the repair agree. After any generated run of owner-scope upserts
    /// and deletes on the §13 table, the repair has nothing to insert, correct or keep.
    func testGeneratedWritesLeaveAProjectionTheRepairFindsNothingToCorrect() async throws {
        var generator = Fx.Generator(seed: 0x1AB0_0C0F_F1CE_0005)
        for round in 0..<40 {
            let store = try await Fx.seededStore()
            for step in 0..<6 {
                let stored = try Fx.rows(store)
                if generator.below(2) == 0, !stored.isEmpty {
                    try await store.deleteLabMarkerAndCopies(id: generator.pick(stored).id)
                } else {
                    let marker = ["weight", "waist", "ldl"][generator.below(3)]
                    let instant = [Fx.t1, Fx.t2, Fx.t3a, Fx.t3, Fx.t4][generator.below(5)]
                    let day = [Fx.t1: Fx.day1, Fx.t2: Fx.day2, Fx.t3a: Fx.day3, Fx.t3: Fx.day3, Fx.t4: Fx.day4][instant]!
                    let value: Double? = [97.5, 98.0, 99.2, nil][generator.below(4)]
                    try await store.upsertOwnerLabMarkers([Fx.row(
                        id: "u\(round)-\(step)", deviceId: Fx.n, markerKey: marker, category: "bodyMeasurement",
                        day: day, takenAt: instant, value: value, valueText: value == nil ? "clear" : nil,
                        unit: "kg", source: generator.below(3) == 0 ? "lab-csv" : "manual")])
                }
            }
            let cellsBefore = try Fx.labBookCells(store)
            let countsBefore = try Fx.countsById(store)
            let repair = try await store.repairLabBookProjection()
            assertRepair(repair, inserted: 0, updated: 0, unchanged: cellsBefore.count, unbackedKept: 0,
                         "round \(round)")
            XCTAssertEqual(try Fx.labBookCells(store), cellsBefore, "round \(round)")
            XCTAssertEqual(try Fx.countsById(store), countsBefore, "round \(round)")
        }
    }
}
