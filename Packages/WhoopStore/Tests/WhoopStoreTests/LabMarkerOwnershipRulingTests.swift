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
//   @discardableResult public func WhoopStore.repairLabBookProjection() async throws -> LabBookProjectionRepair
//   public func WhoopStore.allLabMarkers(markerKey: String) async throws -> [LabMarkerRow]
//   LabMarkerUnion.merged(_:activeDeviceId:), isCopy(_:_:), key(_:), conflictingKeys(_:)
//
// What these tests pin is BEHAVIOUR the cross-stage rulings change
// (docs/personal/superapp/specs/RULINGS-ADDENDUM.md, rulings A10 and A11, which override §7.3 and
// §7.4 of the specification), and the five review findings they answer:
//
//   A10  Two different readings at one instant under two strap ids are two readings. An owner-scope
//        write touches ONLY the row the owner acted on and its true copies, never a conflicting row.
//        `upsertOwnerLabMarkers` has no separate row-id parameter, so "the row the owner acted on"
//        is expressed with the existing argument:
//          - an EDIT passes the stored row's own `id` and `deviceId` with new content;
//          - a LANDING SAVE passes a draft as the Lab Book screen builds it (a fresh `id`, the
//            active `deviceId`); the row it lands on is the stored row at that identity under the
//            draft's `deviceId`.
//        Both name one stored row whether the implementation selects by `id` or by `deviceId`.
//   A11  The projection is never a reason to lose information. The repair never replaces a projected
//        value that equals the value of a stored reading of that marker and day, never erases a cell
//        no stored row backs, and neither does a write; true copies stored under different days
//        keep both days' cells.
//
// Left open by the rulings and therefore NOT asserted here:
//   - which `LabBookProjectionRepair` count a kept cell that differs from the latest reading falls
//     in (`unchanged` or `unbackedKept`): only `inserted`, `updated` and the sum of the other two;
//   - which of two conflicting same-instant readings a NEWLY derived cell takes (§7.2 says the
//     greater id, A11 "the reading the listing shows first"): only that the cell holds the value of
//     one stored reading of that marker and day;
//   - what a landing save does when the identity holds a conflict and the draft's device id holds no
//     row there (insert a third reading, or refuse): only that no stored row changes;
//   - whether a true copy's stored `day` follows an edit: only that both days keep a cell.
//
// A "true copy" is what `LabMarkerUnion.isCopy` decides (the stored `day` is not compared, which is
// why A11 can speak of true copies carrying different stored days).
//
// Synthetic values only: the one "Fixture Person" of labbook-ownership.md §13.

final class LabMarkerOwnershipRulingTests: XCTestCase {

    private typealias Fx = LabBookOwnershipFixture

    // MARK: - Constructed rows

    /// A true copy of F8 (N, weight, t3, 98.4) stored under A.
    private static let f8CopyUnderA: LabMarkerRow = {
        var copy = Fx.f8
        copy.id = "weight-1926831600-F00000C8"
        copy.deviceId = Fx.a
        return copy
    }()

    /// A third reading at F3's and F8's identity, under B, differing from both in value.
    private static let conflictUnderB: LabMarkerRow = {
        var row = Fx.f3
        row.id = "weight-1926831600-F00000B3"
        row.deviceId = Fx.b
        row.value = 98.6
        row.note = "fixture panel"
        return row
    }()

    // MARK: - Helpers

    /// The dump of `LabBookOwnershipFixture.storageDump`, keyed by the row's `id` (its second field).
    private func byId(_ dump: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for line in dump {
            let fields = line.components(separatedBy: "|")
            out[fields.count > 1 ? fields[1] : line] = line
        }
        return out
    }

    /// Every stored row that the operation was not allowed to touch is byte-identical to `before`,
    /// rowid and every column included. `changed` rows must still be stored (their content is the
    /// caller's to assert), `removed` rows must be gone, and no row appears that is not in `added`.
    private func assertRows(_ store: WhoopStore, before: [String], changed: Set<String> = [],
                            removed: Set<String> = [], added: Set<String> = [], _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let was = byId(before)
        let now = byId(try Fx.storageDump(store))
        for (id, stored) in was {
            if removed.contains(id) {
                XCTAssertNil(now[id], "\(message): \(id) should be deleted", file: file, line: line)
            } else if changed.contains(id) {
                XCTAssertNotNil(now[id], "\(message): \(id) should still be stored", file: file, line: line)
            } else {
                XCTAssertEqual(now[id], stored, "\(message): \(id) was not the owner's target and changed",
                               file: file, line: line)
            }
        }
        XCTAssertEqual(Set(now.keys).subtracting(was.keys), added, "\(message): rows that appeared",
                       file: file, line: line)
    }

    private func stored(_ store: WhoopStore, _ id: String) throws -> LabMarkerRow? {
        try Fx.rows(store).first { $0.id == id }
    }

    private func cellValue(_ store: WhoopStore, _ key: String, _ day: String) throws -> Double? {
        try Fx.labBookCells(store).first { $0.key == key && $0.day == day }?.value
    }

    /// The cell exists and holds the value of a stored numeric reading of that marker and day. Which
    /// of two conflicting readings it holds is left to the rulings and is not asserted.
    private func assertCellHeldByAStoredReading(_ store: WhoopStore, _ key: String, _ day: String,
                                                _ message: String,
                                                file: StaticString = #filePath, line: UInt = #line) throws {
        let held = Set(try Fx.rows(store).filter { $0.markerKey == key && $0.day == day }.compactMap(\.value))
        guard let value = try cellValue(store, key, day) else {
            return XCTFail("\(message): no \(key) cell on \(day)", file: file, line: line)
        }
        XCTAssertTrue(held.contains(value), "\(message): the \(key) cell of \(day) holds \(value), which no stored reading holds",
                      file: file, line: line)
    }

    /// The readings the list shows at one identity, in list order.
    private func listed(_ store: WhoopStore, marker: String, at instant: Int, active: String = Fx.n) async throws
        -> [LabMarkerRow] {
        let rows = try await store.allLabMarkers(markerKey: marker)
        return LabMarkerUnion.merged(rows, activeDeviceId: active).filter { $0.takenAt == instant }
    }

    /// A draft as the Lab Book screen builds it: a freshly minted id and the active device id.
    private func draft(_ base: LabMarkerRow, id: String, deviceId: String = Fx.n,
                       _ change: (inout LabMarkerRow) -> Void = { _ in }) -> LabMarkerRow {
        var row = base
        row.id = id
        row.deviceId = deviceId
        change(&row)
        return row
    }

    // MARK: - Ruling A10: an edit touches only the row the owner edited (findings 1 and 3)

    /// Pins ruling A10 and findings 1 and 3. F3 (98.0, under C) and F8 (98.4, under N) are two
    /// different readings at one instant. Editing either one, named by its own id and device id,
    /// changes that row alone: the other keeps every column, both stay listed with their own values,
    /// and the identity is still a conflict. §7.4 as first written updated both.
    func testEditOfOneConflictingRowChangesOnlyThatRowAndBothStayListed() async throws {
        for target in [Fx.f8, Fx.f3] {
            let other = target.id == Fx.f8.id ? Fx.f3 : Fx.f8
            let store = try await Fx.seededStore()
            let before = try Fx.storageDump(store)
            try Fx.assertCounts(store, Fx.countsById, "before editing \(target.id)")

            var edit = target
            edit.value = 97.9
            edit.note = "fixture edit"
            let written = try await store.upsertOwnerLabMarkers([edit])

            XCTAssertEqual(written, 1, "editing \(target.id): one stored row is written")
            try Fx.assertCounts(store, Fx.countsById, "after editing \(target.id)")
            try assertRows(store, before: before, changed: [target.id], "editing \(target.id)")
            XCTAssertEqual(try stored(store, target.id), edit, "the edited row took the new content")
            XCTAssertEqual(try stored(store, other.id), other, "the conflicting row keeps its own value and note")

            let shown = try await listed(store, marker: "weight", at: Fx.t3)
            XCTAssertEqual(shown.sorted { $0.id < $1.id }, [edit, other].sorted { $0.id < $1.id },
                           "editing \(target.id): both readings are still listed, each with its own value")
            let all = try await store.allLabMarkers()
            XCTAssertEqual(LabMarkerUnion.conflictingKeys(all), [LabMarkerUnion.key(Fx.f3)],
                           "editing \(target.id): the edit did not merge the two readings into copies")
            try assertCellHeldByAStoredReading(store, "weight", Fx.day3, "editing \(target.id)")
        }
    }

    /// Pins ruling A10 and findings 1 and 3: a save landing on an instant that holds a conflict
    /// updates the row under the saving (active) device id, here F8 under N, and leaves the
    /// conflicting F3 byte-identical. The draft's own freshly minted id is not stored.
    func testSaveLandingOnAConflictUpdatesOnlyTheActiveIdsRow() async throws {
        let store = try await Fx.seededStore()
        let before = try Fx.storageDump(store)
        try Fx.assertCounts(store, Fx.countsById, "before")
        let incoming = draft(Fx.f8, id: "weight-1926831600-D0000001") { $0.value = 98.2 }

        let written = try await store.upsertOwnerLabMarkers([incoming])

        XCTAssertEqual(written, 1, "one stored row is written, not both rows of the identity")
        try Fx.assertCounts(store, Fx.countsById, "after: no row added or removed under any id")
        try assertRows(store, before: before, changed: [Fx.f8.id], "the landing save")
        var f8 = Fx.f8
        f8.value = 98.2
        XCTAssertEqual(try stored(store, Fx.f8.id), f8, "the active id's row took the value and kept its id")
        XCTAssertEqual(try stored(store, Fx.f3.id), Fx.f3, "the conflicting reading under C is untouched")
        XCTAssertNil(try stored(store, incoming.id), "the draft's id is not stored")
        let shown = try await listed(store, marker: "weight", at: Fx.t3)
        XCTAssertEqual(shown, [Fx.f3, f8], "both readings are listed, 98.0 and 98.2")
        try assertCellHeldByAStoredReading(store, "weight", Fx.day3, "after the landing save")
    }

    /// Pins ruling A10: the row a save lands on brings its TRUE COPIES with it, and only them. Three
    /// rows share the identity: F8 under N and a copy of it under A (one reading, stored twice), and
    /// the conflicting F3 under C. A landing save under N, and an edit naming the copy under A, each
    /// change the two copies together and leave F3 byte-identical.
    func testSaveLandingOnAConflictUpdatesTheLandedRowAndItsTrueCopiesOnly() async throws {
        let copy = Self.f8CopyUnderA
        var counts = Fx.countsById
        counts[Fx.a] = 2

        // A landing save under N.
        let landing = try await Fx.seededStore()
        try Fx.insertRaw([copy], into: landing)
        var before = try Fx.storageDump(landing)
        try Fx.assertCounts(landing, counts, "before the landing save")
        let written = try await landing.upsertOwnerLabMarkers(
            [draft(Fx.f8, id: "weight-1926831600-D0000001") { $0.value = 98.2 }])
        XCTAssertEqual(written, 2, "the landed row and its one copy")
        try Fx.assertCounts(landing, counts, "after the landing save")
        try assertRows(landing, before: before, changed: [Fx.f8.id, copy.id], "the landing save")
        var f8 = Fx.f8, f8Copy = copy
        f8.value = 98.2
        f8Copy.value = 98.2
        XCTAssertEqual(try stored(landing, Fx.f8.id), f8)
        XCTAssertEqual(try stored(landing, copy.id), f8Copy, "the copy under A took the value under its own id")
        XCTAssertEqual(try stored(landing, Fx.f3.id), Fx.f3, "the conflicting reading is untouched")
        var shown = try await listed(landing, marker: "weight", at: Fx.t3)
        XCTAssertEqual(shown, [Fx.f3, f8], "two readings: the conflict, and the copies as one line")

        // An edit of the copy under A, named by its own id and device id.
        let editing = try await Fx.seededStore()
        try Fx.insertRaw([copy], into: editing)
        before = try Fx.storageDump(editing)
        try Fx.assertCounts(editing, counts, "before the edit")
        var edit = copy
        edit.value = 97.9
        let edited = try await editing.upsertOwnerLabMarkers([edit])
        XCTAssertEqual(edited, 2, "the edited row and its one copy")
        try Fx.assertCounts(editing, counts, "after the edit")
        try assertRows(editing, before: before, changed: [Fx.f8.id, copy.id], "the edit")
        f8.value = 97.9
        XCTAssertEqual(try stored(editing, copy.id), edit)
        XCTAssertEqual(try stored(editing, Fx.f8.id), f8, "the copy under N followed")
        XCTAssertEqual(try stored(editing, Fx.f3.id), Fx.f3, "the conflicting reading is untouched")
        shown = try await listed(editing, marker: "weight", at: Fx.t3)
        XCTAssertEqual(shown, [Fx.f3, f8])
    }

    /// Pins the companion case of finding 1: importing again a reading whose content equals the row
    /// it lands on writes nothing that can be seen. Both conflicting rows are byte-identical
    /// afterwards. §7.4 as first written gave F3 the content of F8.
    func testReimportEqualToTheRowItLandsOnLeavesBothConflictingRowsByteIdentical() async throws {
        let store = try await Fx.seededStore()
        let before = try Fx.storageDump(store)
        try Fx.assertCounts(store, Fx.countsById, "before")

        for round in 1...2 {
            try await store.upsertOwnerLabMarkers([draft(Fx.f8, id: "weight-1926831600-D000000\(round)")])
            try Fx.assertCounts(store, Fx.countsById, "after re-import \(round)")
            XCTAssertEqual(try Fx.storageDump(store), before, "re-import \(round): every row as it was")
            XCTAssertEqual(try Fx.labBookCells(store), Fx.cells, "re-import \(round): every cell as it was")
        }
        let shown = try await listed(store, marker: "weight", at: Fx.t3)
        XCTAssertEqual(shown, [Fx.f3, Fx.f8])
    }

    /// Pins ruling A10 where the saving device id holds no row at the identity: two conflicting
    /// readings sit under B and C, and a draft arrives under N with a third value. Whatever the
    /// write does with the incoming reading, it never changes a conflicting row: both stored rows
    /// are byte-identical afterwards and both are still listed.
    func testSaveOntoAConflictHeldOnlyUnderOtherIdsChangesNeitherStoredRow() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        let underB = Self.conflictUnderB
        try Fx.insertRaw([Fx.f3, underB], into: store)
        try Fx.setCell(Fx.cell("weight", Fx.day3, 98.6), in: store)
        let before = try Fx.storageDump(store)
        try Fx.assertCounts(store, [Fx.b: 1, Fx.c: 1], "before")
        let incoming = draft(Fx.f3, id: "weight-1926831600-D0000001") { $0.value = 97.0 }

        do {
            try await store.upsertOwnerLabMarkers([incoming])
        } catch {
            // Refusing the write is acceptable: the ruling fixes only what may not change.
        }

        let after = try Fx.storageDump(store)
        for line in before {
            XCTAssertTrue(after.contains(line), "a conflicting row changed or went: \(line)")
        }
        let counts = try Fx.countsById(store)
        XCTAssertEqual(counts[Fx.b], 1, "the row under B")
        XCTAssertEqual(counts[Fx.c], 1, "the row under C")
        let rows = try Fx.rows(store)
        XCTAssertLessThanOrEqual(rows.count, 3, "at most the incoming reading was added")
        for extra in rows where extra.id != Fx.f3.id && extra.id != underB.id {
            XCTAssertEqual(extra, incoming, "a third row can only be the incoming reading, stored as given")
        }
        let shown = try await listed(store, marker: "weight", at: Fx.t3)
        XCTAssertTrue(shown.contains(Fx.f3), "98.0 is still listed")
        XCTAssertTrue(shown.contains(underB), "98.6 is still listed")
        try assertCellHeldByAStoredReading(store, "weight", Fx.day3, "after the save")
    }

    // MARK: - Ruling A10: a delete removes only that row and its true copies

    /// Pins ruling A10: deleting one of two conflicting readings leaves the other, and a delete takes
    /// the named row's true copies with it and nothing else. With F3 (C), F8 (N) and a copy of F8
    /// (A) at one identity: deleting F8 or its copy removes exactly those two and leaves F3;
    /// deleting F3 removes F3 alone and leaves both copies.
    func testDeleteOfOneConflictingReadingLeavesTheOtherAndTakesOnlyTrueCopies() async throws {
        let copy = Self.f8CopyUnderA
        var counts = Fx.countsById
        counts[Fx.a] = 2

        for named in [Fx.f8.id, copy.id] {
            let store = try await Fx.seededStore()
            try Fx.insertRaw([copy], into: store)
            let before = try Fx.storageDump(store)
            try Fx.assertCounts(store, counts, "before deleting \(named)")

            let deleted = try await store.deleteLabMarkerAndCopies(id: named)

            XCTAssertEqual(deleted, [Fx.f8.id, copy.id].sorted(), "deleting \(named)")
            try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 3, Fx.c: 2, Fx.d: 1, Fx.n: 2], "after deleting \(named)")
            try assertRows(store, before: before, removed: [Fx.f8.id, copy.id], "deleting \(named)")
            let shown = try await listed(store, marker: "weight", at: Fx.t3)
            XCTAssertEqual(shown, [Fx.f3], "deleting \(named): the other reading stays, with its own value")
            XCTAssertEqual(try cellValue(store, "weight", Fx.day3), 98.0, "F3 is now the day's latest reading")
        }

        let store = try await Fx.seededStore()
        try Fx.insertRaw([copy], into: store)
        let before = try Fx.storageDump(store)
        try Fx.assertCounts(store, counts, "before deleting F3")
        let deleted = try await store.deleteLabMarkerAndCopies(id: Fx.f3.id)
        XCTAssertEqual(deleted, [Fx.f3.id])
        try Fx.assertCounts(store, [Fx.a: 2, Fx.b: 3, Fx.c: 1, Fx.d: 1, Fx.n: 3], "after deleting F3")
        try assertRows(store, before: before, removed: [Fx.f3.id], "deleting F3")
        let shown = try await listed(store, marker: "weight", at: Fx.t3)
        XCTAssertEqual(shown, [Fx.f8], "the copies are still one line, 98.4")
        XCTAssertEqual(try cellValue(store, "weight", Fx.day3), 98.4)
    }

    // MARK: - Ruling A10: true copies stay in step

    /// Pins ruling A10: a set of true copies behaves as one reading. An edit naming either copy of
    /// the pair F6 and F7 changes both, each under its own id and device id; the list keeps one
    /// line; a delete of either then removes both. No other row changes at any step.
    func testTrueCopiesStayInStepAfterAnEditAndADelete() async throws {
        for named in [Fx.f7, Fx.f6] {
            let store = try await Fx.seededStore()
            var before = try Fx.storageDump(store)
            try Fx.assertCounts(store, Fx.countsById, "before editing \(named.id)")

            var edit = named
            edit.value = 3.4
            edit.note = nil
            let written = try await store.upsertOwnerLabMarkers([edit])

            XCTAssertEqual(written, 2, "editing \(named.id): both copies")
            try Fx.assertCounts(store, Fx.countsById, "after editing \(named.id)")
            try assertRows(store, before: before, changed: [Fx.f6.id, Fx.f7.id], "editing \(named.id)")
            var f6 = Fx.f6, f7 = Fx.f7
            f6.value = 3.4
            f6.note = nil
            f7.value = 3.4
            f7.note = nil
            XCTAssertEqual(try stored(store, Fx.f6.id), f6)
            XCTAssertEqual(try stored(store, Fx.f7.id), f7)
            XCTAssertTrue(LabMarkerUnion.isCopy(f6, f7))
            var shown = try await listed(store, marker: "ldl", at: Fx.t2)
            XCTAssertEqual(shown, [f7], "editing \(named.id): still one line, the active id's row")
            XCTAssertEqual(try cellValue(store, "ldl", Fx.day2), 3.4)

            before = try Fx.storageDump(store)
            let deleted = try await store.deleteLabMarkerAndCopies(id: named.id)
            XCTAssertEqual(deleted, [Fx.f6.id, Fx.f7.id])
            try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 2, Fx.c: 2, Fx.d: 1, Fx.n: 2], "after deleting \(named.id)")
            try assertRows(store, before: before, removed: [Fx.f6.id, Fx.f7.id], "deleting \(named.id)")
            shown = try await listed(store, marker: "ldl", at: Fx.t2)
            XCTAssertEqual(shown, [], "the reading does not come back from its copy")
            XCTAssertNil(try cellValue(store, "ldl", Fx.day2), "its cell went with it")
        }
    }

    // MARK: - Ruling A11: the repair never replaces a value a stored reading holds (finding 2)

    /// Pins ruling A11 and finding 2 on the §13 fixture. Three ids hold different weight readings on
    /// 2031-01-22: F9 98.2 under B, F3 98.0 under C, F8 98.4 under N. Whichever of the three the
    /// projected cell holds, the repair leaves it exactly as stored, reports no update, and a second
    /// run reports the same. §7.3 as first written replaced 98.0 and 98.2 with 98.4.
    func testRepairLeavesACellEqualToAnyStoredReadingOfTheDayUntouched() async throws {
        for held in [98.0, 98.2, 98.4] {
            let store = try await Fx.seededStore()
            try Fx.setCell(Fx.cell("weight", Fx.day3, held), in: store)
            let rowsBefore = try Fx.storageDump(store)
            let cellsBefore = try Fx.labBookCells(store)
            try Fx.assertCounts(store, Fx.countsById, "before, cell \(held)")

            let first = try await store.repairLabBookProjection()

            XCTAssertEqual(first.inserted, 0, "cell \(held)")
            XCTAssertEqual(first.updated, 0, "cell \(held): a value a stored reading holds is never replaced")
            XCTAssertEqual(first.unchanged + first.unbackedKept, 6, "cell \(held): all six cells are left")
            XCTAssertEqual(try Fx.labBookCells(store), cellsBefore, "cell \(held) stays")
            XCTAssertEqual(try cellValue(store, "weight", Fx.day3)?.bitPattern, held.bitPattern)
            XCTAssertEqual(try Fx.storageDump(store), rowsBefore, "cell \(held): no labMarker row changed")
            try Fx.assertCounts(store, Fx.countsById, "after, cell \(held)")

            let second = try await store.repairLabBookProjection()
            XCTAssertEqual(second, first, "cell \(held): a second run changes nothing and reports the same")
            XCTAssertEqual(try Fx.labBookCells(store), cellsBefore, "cell \(held) stays after the second run")
        }
    }

    /// Pins finding 2 in the shape it was replayed in: two rows at ONE instant under two ids, with
    /// ids minted so that the stale reading has the greater id. The cell holds the later-entered
    /// 3.1; the id tie-break of §7.2 would flip it back to 3.0. The repair leaves it. In the mirror
    /// case, where the cell holds 3.0, the repair leaves that too.
    func testRepairDoesNotFlipACellBetweenSameInstantConflictingReadings() async throws {
        let stale = Fx.row(id: "ldl-1926226800-FZZZZZZZ", deviceId: Fx.b, markerKey: "ldl", category: "bloodPanel",
                           day: Fx.day2, takenAt: Fx.t2, value: 3.0, unit: "mmol/L", source: "lab-csv")
        let corrected = Fx.row(id: "ldl-1926226800-FAAAAAAA", deviceId: Fx.n, markerKey: "ldl",
                               category: "bloodPanel", day: Fx.day2, takenAt: Fx.t2, value: 3.1, unit: "mmol/L",
                               source: "lab-csv")
        for held in [3.1, 3.0] {
            let store = try await Fx.emptyStoreWithRegistry()
            try Fx.insertRaw([stale, corrected], into: store)
            try Fx.setCell(Fx.cell("ldl", Fx.day2, held), in: store)
            let rowsBefore = try Fx.storageDump(store)
            try Fx.assertCounts(store, [Fx.b: 1, Fx.n: 1], "before, cell \(held)")

            for run in 1...2 {
                let repair = try await store.repairLabBookProjection()
                XCTAssertEqual(repair.inserted, 0, "cell \(held), run \(run)")
                XCTAssertEqual(repair.updated, 0, "cell \(held), run \(run)")
                XCTAssertEqual(repair.unchanged + repair.unbackedKept, 1, "cell \(held), run \(run)")
                XCTAssertEqual(try Fx.labBookCells(store), [Fx.cell("ldl", Fx.day2, held)],
                               "cell \(held), run \(run): the value already there is kept")
                XCTAssertEqual(try Fx.storageDump(store), rowsBefore, "cell \(held), run \(run)")
                try Fx.assertCounts(store, [Fx.b: 1, Fx.n: 1], "after, cell \(held), run \(run)")
            }
        }
    }

    // MARK: - Ruling A11: a cell no stored row backs is never erased

    /// Pins ruling A11: the repair never erases, and never rewrites, a cell no stored row backs.
    /// Four such cells: a value no reading of the day holds, a day with no reading, a marker with no
    /// row, and a day whose only reading of the marker is text. Each is bit-identical after two runs.
    func testRepairNeverErasesOrRewritesACellNoStoredRowBacks() async throws {
        let store = try await Fx.seededStore()
        let unbacked = [
            Fx.cell("weight", Fx.day1, 90.0),            // F1 holds 100.0 that day
            Fx.cell("weight", "2031-02-05", 97.5),       // no reading that day
            Fx.cell("fixture_absent", Fx.day1, 97.5),    // no row of that marker
            Fx.cell("fixture_note", Fx.day2, 97.5),      // F10 holds text only
        ]
        for cell in unbacked { try Fx.setCell(cell, in: store) }
        let rowsBefore = try Fx.storageDump(store)
        let cellsBefore = try Fx.labBookCells(store)
        XCTAssertEqual(cellsBefore.count, 9)
        try Fx.assertCounts(store, Fx.countsById, "before")

        for run in 1...2 {
            let repair = try await store.repairLabBookProjection()
            XCTAssertEqual(repair.inserted, 0, "run \(run)")
            XCTAssertEqual(repair.updated, 0, "run \(run)")
            XCTAssertEqual(repair.unchanged, 5, "run \(run): the five cells that are correct")
            XCTAssertEqual(repair.unbackedKept, 4, "run \(run): the four cells no row backs")
            XCTAssertEqual(try Fx.labBookCells(store), cellsBefore, "run \(run)")
            XCTAssertEqual(try Fx.storageDump(store), rowsBefore, "run \(run)")
            try Fx.assertCounts(store, Fx.countsById, "after run \(run)")
        }
    }

    /// Pins ruling A11 for the owner-scope writes: a write on the marker and day of an unbacked cell
    /// does not erase it. The `fixture_note` cell of 2031-01-15 holds a number, and the only reading
    /// of that marker and day (F10) holds text, so no stored row backs the cell. Editing F10's text
    /// and then deleting F10 leave the cell bit-identical. The same for a day with no reading at all,
    /// when a text-only reading is added to it and removed again. §7.3 as first written let the
    /// recomputation of §7.2 delete such a cell on the next write.
    func testOwnerScopeWriteOnTheMarkerAndDayDoesNotEraseAnUnbackedCell() async throws {
        let store = try await Fx.seededStore()
        let trace = Fx.cell("fixture_note", Fx.day2, 97.5)
        let emptyDay = Fx.cell("weight", "2031-02-05", 97.5)
        try Fx.setCell(trace, in: store)
        try Fx.setCell(emptyDay, in: store)
        let cellsBefore = try Fx.labBookCells(store)
        XCTAssertEqual(cellsBefore, [trace] + Fx.cells + [emptyDay])
        var before = try Fx.storageDump(store)
        try Fx.assertCounts(store, Fx.countsById, "before")

        // An edit of the text reading.
        var edit = Fx.f10
        edit.valueText = "cloudy"
        try await store.upsertOwnerLabMarkers([edit])
        try Fx.assertCounts(store, Fx.countsById, "after the edit")
        try assertRows(store, before: before, changed: [Fx.f10.id], "the edit")
        XCTAssertEqual(try stored(store, Fx.f10.id), edit)
        XCTAssertEqual(try Fx.labBookCells(store), cellsBefore, "the edit erased or changed a cell")

        // A text-only weight reading added to the day that has none.
        let text = Fx.row(id: "weight-1928041200-D0000001", deviceId: Fx.n, markerKey: "weight",
                          category: "bodyMeasurement", day: "2031-02-05", takenAt: 1_928_041_200, value: nil,
                          valueText: "clear", unit: "text")
        before = try Fx.storageDump(store)
        try await store.upsertOwnerLabMarkers([text])
        var counts = Fx.countsById
        counts[Fx.n] = 4
        try Fx.assertCounts(store, counts, "after adding the text reading")
        try assertRows(store, before: before, added: [text.id], "adding the text reading")
        XCTAssertEqual(try Fx.labBookCells(store), cellsBefore, "adding a text reading erased or changed a cell")

        // Both text readings deleted.
        before = try Fx.storageDump(store)
        let deletedText = try await store.deleteLabMarkerAndCopies(id: text.id)
        XCTAssertEqual(deletedText, [text.id])
        try Fx.assertCounts(store, Fx.countsById, "after deleting the text reading")
        try assertRows(store, before: before, removed: [text.id], "deleting the text reading")
        XCTAssertEqual(try Fx.labBookCells(store), cellsBefore, "deleting a text reading erased a cell")

        before = try Fx.storageDump(store)
        let deletedNote = try await store.deleteLabMarkerAndCopies(id: Fx.f10.id)
        XCTAssertEqual(deletedNote, [Fx.f10.id])
        try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 3, Fx.c: 1, Fx.d: 1, Fx.n: 3], "after deleting F10")
        try assertRows(store, before: before, removed: [Fx.f10.id], "deleting F10")
        XCTAssertEqual(try Fx.labBookCells(store), cellsBefore, "deleting F10 erased the cell no row backed")
    }

    /// Pins ruling A11 ("every write") for the per-id functions the weigh-in store calls: they
    /// share the projection step, so they must not erase an unbacked cell either.
    func testPerIdWriteOnTheMarkerAndDayDoesNotEraseAnUnbackedCell() async throws {
        let store = try await Fx.seededStore()
        let trace = Fx.cell("fixture_note", Fx.day2, 97.5)
        try Fx.setCell(trace, in: store)
        let cellsBefore = try Fx.labBookCells(store)
        var before = try Fx.storageDump(store)
        try Fx.assertCounts(store, Fx.countsById, "before")

        var edit = Fx.f10
        edit.valueText = "cloudy"
        try await store.upsertLabMarkers([edit])
        try Fx.assertCounts(store, Fx.countsById, "after the per-id upsert")
        try assertRows(store, before: before, changed: [Fx.f10.id], "the per-id upsert")
        XCTAssertEqual(try Fx.labBookCells(store), cellsBefore, "the per-id upsert erased or changed a cell")

        before = try Fx.storageDump(store)
        let deleted = try await store.deleteLabMarker(id: Fx.f10.id)
        XCTAssertTrue(deleted)
        try Fx.assertCounts(store, [Fx.a: 1, Fx.b: 3, Fx.c: 1, Fx.d: 1, Fx.n: 3], "after the per-id delete")
        try assertRows(store, before: before, removed: [Fx.f10.id], "the per-id delete")
        XCTAssertEqual(try Fx.labBookCells(store), cellsBefore, "the per-id delete erased the cell no row backed")
    }

    // MARK: - Ruling A11: true copies stored under different days (finding 5)

    /// Pins ruling A11 and finding 5. One reading is stored twice, under B with the day 2031-01-07
    /// and under N with the day 2031-01-08 (the zone changed between the two writes). It is one
    /// line in the list and two projected cells. The repair reports both cells unchanged and keeps
    /// them; with both cells missing it inserts both. An owner-scope edit of the reading keeps the
    /// copies in step and BOTH days keep a cell: showing a day twice is accepted, losing a cell is
    /// not. A per-id edit of both copies, as the weigh-in store makes it, keeps both cells too.
    func testTrueCopiesStoredUnderDifferentDaysKeepBothDaysCells() async throws {
        let earlyDay = "2031-01-07"
        let old = Fx.row(id: "weight-1925622000-F00000B1", deviceId: Fx.b, markerKey: "weight",
                         category: "bodyMeasurement", day: earlyDay, takenAt: Fx.t1, value: 100.0, unit: "kg")
        let new = Fx.row(id: "weight-1925622000-F00000N1", deviceId: Fx.n, markerKey: "weight",
                         category: "bodyMeasurement", day: Fx.day1, takenAt: Fx.t1, value: 100.0, unit: "kg")
        XCTAssertTrue(LabMarkerUnion.isCopy(old, new), "the premise: the stored day does not make two readings")
        let bothCells = [Fx.cell("weight", earlyDay, 100.0), Fx.cell("weight", Fx.day1, 100.0)]

        // The repair on the pair with both cells stored.
        let store = try await Fx.emptyStoreWithRegistry()
        try Fx.insertRaw([old, new], into: store)
        for cell in bothCells { try Fx.setCell(cell, in: store) }
        var before = try Fx.storageDump(store)
        try Fx.assertCounts(store, [Fx.b: 1, Fx.n: 1], "before")
        let shown = try await listed(store, marker: "weight", at: Fx.t1)
        XCTAssertEqual(shown, [new], "one line, the active id's row")
        for run in 1...2 {
            let repair = try await store.repairLabBookProjection()
            XCTAssertEqual(repair.inserted, 0, "run \(run)")
            XCTAssertEqual(repair.updated, 0, "run \(run)")
            XCTAssertEqual(repair.unchanged, 2, "run \(run): both days' cells are reported unchanged")
            XCTAssertEqual(repair.unbackedKept, 0, "run \(run)")
            XCTAssertEqual(try Fx.labBookCells(store), bothCells, "run \(run): both days keep their cell")
            XCTAssertEqual(try Fx.storageDump(store), before, "run \(run)")
        }

        // The repair on the pair with neither cell stored.
        let bare = try await Fx.emptyStoreWithRegistry()
        try Fx.insertRaw([old, new], into: bare)
        let inserted = try await bare.repairLabBookProjection()
        XCTAssertEqual(inserted.inserted, 2)
        XCTAssertEqual(inserted.updated, 0)
        XCTAssertEqual(try Fx.labBookCells(bare), bothCells)
        let again = try await bare.repairLabBookProjection()
        XCTAssertEqual(again.inserted, 0)
        XCTAssertEqual(again.updated, 0)
        XCTAssertEqual(again.unchanged, 2)
        XCTAssertEqual(try Fx.labBookCells(bare), bothCells)

        // An owner-scope edit of the listed row.
        var edit = new
        edit.value = 99.5
        let written = try await store.upsertOwnerLabMarkers([edit])
        XCTAssertEqual(written, 2, "the edited row and its copy")
        try Fx.assertCounts(store, [Fx.b: 1, Fx.n: 1], "after the owner-scope edit")
        try assertRows(store, before: before, changed: [old.id, new.id], "the owner-scope edit")
        XCTAssertEqual(try stored(store, new.id), edit)
        let oldAfter = try XCTUnwrap(try stored(store, old.id))
        XCTAssertEqual(oldAfter.value, 99.5, "the copy under B followed")
        XCTAssertEqual(oldAfter.deviceId, Fx.b)
        XCTAssertTrue(LabMarkerUnion.isCopy(oldAfter, edit), "still one reading")
        XCTAssertEqual(try cellValue(store, "weight", Fx.day1), 99.5)
        XCTAssertNotNil(try cellValue(store, "weight", earlyDay), "the earlier day lost its cell")
        XCTAssertEqual(try Fx.labBookCells(store).count, 2, "both days keep their cell")
        let afterEdit = try await store.repairLabBookProjection()
        XCTAssertEqual(afterEdit.inserted, 0, "after the owner-scope edit")
        XCTAssertEqual(afterEdit.updated, 0, "after the owner-scope edit")
        XCTAssertEqual(try Fx.labBookCells(store).count, 2)

        // A per-id edit of both copies, each keeping its own day (the weigh-in store's value edit).
        let perId = try await Fx.emptyStoreWithRegistry()
        try Fx.insertRaw([old, new], into: perId)
        for cell in bothCells { try Fx.setCell(cell, in: perId) }
        before = try Fx.storageDump(perId)
        var oldEdit = old, newEdit = new
        oldEdit.value = 99.0
        newEdit.value = 99.0
        try await perId.upsertLabMarkers([newEdit, oldEdit])
        try Fx.assertCounts(perId, [Fx.b: 1, Fx.n: 1], "after the per-id edit")
        try assertRows(perId, before: before, changed: [old.id, new.id], "the per-id edit")
        XCTAssertEqual(try Fx.rows(perId), [oldEdit, newEdit])
        XCTAssertEqual(try Fx.labBookCells(perId), [Fx.cell("weight", earlyDay, 99.0), Fx.cell("weight", Fx.day1, 99.0)])
        let afterPerId = try await perId.repairLabBookProjection()
        XCTAssertEqual(afterPerId.inserted, 0)
        XCTAssertEqual(afterPerId.updated, 0)
        XCTAssertEqual(afterPerId.unchanged, 2)
        XCTAssertEqual(afterPerId.unbackedKept, 0)
    }

    // MARK: - Ruling A11: idempotence

    /// Pins ruling A11 and §7.3's idempotence on one store that holds every shape at once: a
    /// conflict at one instant, copies, a missing cell, a cell holding another of the day's readings,
    /// a cell no row backs and a cell on a day with no reading. The first run only inserts the
    /// missing cell. A second and a third run change nothing and report the same as each other. No
    /// `labMarker` row changes in any run.
    func testRepairIsIdempotentAndASecondRunChangesNothing() async throws {
        let store = try await Fx.seededStore()
        try Fx.removeLabBookCell("ldl", Fx.day2, in: store)                  // missing
        try Fx.setCell(Fx.cell("weight", Fx.day3, 98.0), in: store)          // F3's value, a stored reading
        try Fx.setCell(Fx.cell("weight", Fx.day1, 90.0), in: store)          // no row holds it
        try Fx.setCell(Fx.cell("weight", "2031-02-05", 97.5), in: store)     // no reading that day
        let rowsBefore = try Fx.storageDump(store)
        try Fx.assertCounts(store, Fx.countsById, "before")
        let expected = [
            Fx.cell("ldl", Fx.day2, 3.0), Fx.cell("waist", Fx.day1, 100.0), Fx.cell("weight", Fx.day1, 90.0),
            Fx.cell("weight", Fx.day2, 99.2), Fx.cell("weight", Fx.day3, 98.0), Fx.cell("weight", Fx.day4, 97.6),
            Fx.cell("weight", "2031-02-05", 97.5),
        ]

        let first = try await store.repairLabBookProjection()
        XCTAssertEqual(first.inserted, 1, "the ldl cell")
        XCTAssertEqual(first.updated, 0, "no stored cell is replaced")
        XCTAssertEqual(first.unchanged + first.unbackedKept, 6, "the six cells that were stored are all left")
        XCTAssertEqual(try Fx.labBookCells(store), expected, "first run")
        XCTAssertEqual(try Fx.storageDump(store), rowsBefore, "first run")
        try Fx.assertCounts(store, Fx.countsById, "after the first run")

        let second = try await store.repairLabBookProjection()
        XCTAssertEqual(second.inserted, 0, "second run")
        XCTAssertEqual(second.updated, 0, "second run")
        XCTAssertEqual(second.unchanged + second.unbackedKept, 7, "second run: seven cells, all left")
        XCTAssertEqual(try Fx.labBookCells(store), expected, "second run")
        XCTAssertEqual(try Fx.storageDump(store), rowsBefore, "second run")

        let third = try await store.repairLabBookProjection()
        XCTAssertEqual(third, second, "every later run reports the same")
        XCTAssertEqual(try Fx.labBookCells(store), expected, "third run")
        XCTAssertEqual(try Fx.storageDump(store), rowsBefore, "third run")
        try Fx.assertCounts(store, Fx.countsById, "after three runs")
    }
}
