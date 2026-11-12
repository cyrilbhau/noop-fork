// API ASSUMED BY THESE TESTS
//
// No member that does not exist. Every call is to API the Lab Book ownership change already declares
// (docs/personal/superapp/specs/labbook-ownership.md §6.1, §6.2) or to the weigh-in store:
//
//   WeighInStore.save(weight:waist:unitSystem:takenAt:), edit(_:value:unitSystem:takenAt:), delete(_:),
//   readings(_:)
//   WhoopStore.upsertOwnerLabMarkers(_:), deleteLabMarkerAndCopies(id:), upsertLabMarkers(_:)
//   LabBookRows.all(store:activeDeviceId:), marker(_:store:activeDeviceId:), stored(marker:store:)
//   static func Repository.repairLabBookProjection(afterOpening store: WhoopStore, log: (String) -> Void) async
//
// What these tests pin is BEHAVIOUR the cross-stage rulings change
// (docs/personal/superapp/specs/RULINGS-ADDENDUM.md, rulings A10 and A11, which override §7.3 and
// §7.4 of the specification), at the level of the app's write funnels:
//
//   A10  Two different readings at one instant under two strap ids are two readings. An edit, a
//        delete or a landing save touches ONLY the row the owner acted on and its true copies (what
//        `LabMarkerUnion.isCopy` decides), never a conflicting row. A weigh-in save that lands on
//        the active id's row updates that row's true copies with it (review finding 4).
//   A11  The projection is never a reason to lose information: the repair the repository runs after
//        the store opens leaves a cell that holds a stored reading's value, and a write does not
//        erase a cell no stored row backs.
//
// `LabBookView`'s `save`, `delete` and CSV import are private methods of a SwiftUI view. As in
// LabBookOwnershipFlowTests.swift, the Lab Book cases run the store calls §7.4 names for the screen
// on rows built the way the screen builds them (a fresh id, the active device id).
//
// Left open by the rulings and not asserted: which of two conflicting same-instant readings a
// re-derived cell takes, and what a Lab Book save does with the incoming reading when the identity
// holds a conflict and the active id holds no row there (only that no stored row changes).
//
// The fixture and the harness are in LabBookRowsTests.swift (`LabBookOwnershipAppFixture`,
// `LabBookOwnershipAppHarness`). Synthetic values only: the one "Fixture Person".

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class LabBookOwnershipRulingTests: XCTestCase {

    private typealias Fx = LabBookOwnershipAppFixture
    private typealias H = LabBookOwnershipAppHarness

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    // MARK: - Constructed rows

    /// A different weight reading at F4's instant, under C: it conflicts with F4 and with F4's copy.
    private static let conflictAtT4: LabMarkerRow = {
        var row = LabBookOwnershipAppFixture.f4
        row.id = "weight-1927436400-F00000E4"
        row.deviceId = LabBookOwnershipAppFixture.c
        row.value = 96.9
        row.note = "fixture panel"
        return row
    }()

    // MARK: - Helpers

    /// Collects the lines a log closure receives.
    private final class Lines {
        var all: [String] = []
    }

    private func assertThrows(_ expected: WeighInError, _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line,
                              _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected) \(message)", file: file, line: line)
        } catch let error as WeighInError {
            XCTAssertEqual(error, expected, message, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error) \(message)", file: file, line: line)
        }
    }

    /// The §13 store with F4 stored twice (under N and under B) and a conflicting reading at the
    /// same instant under C. Rows per id: A 1, B 4, C 3, D 1, N 3.
    private func storeWithCopiesAndAConflictAtT4() async throws -> WhoopStore {
        let store = try await Fx.seededStore()
        try await store.upsertLabMarkers([Fx.f4CopyUnderB, Self.conflictAtT4])
        return store
    }

    private static let countsWithCopiesAndConflict = [Fx.a: 1, Fx.b: 4, Fx.c: 3, Fx.d: 1, Fx.n: 3]

    /// Every stored row, with `replacing` substituted by id and `removing` left out, in
    /// (`takenAt`, `id`) order: what a snapshot must equal when nothing else changed.
    private func expected(_ rows: [LabMarkerRow], replacing: [LabMarkerRow] = [], removing: Set<String> = [],
                          adding: [LabMarkerRow] = []) -> [LabMarkerRow] {
        (rows.filter { !removing.contains($0.id) }.map { row in replacing.first { $0.id == row.id } ?? row } + adding)
            .sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
    }

    private func cellValue(_ store: WhoopStore, _ key: String, _ day: String) async throws -> Double? {
        try await Fx.labBookCells(store).first { $0.key == key && $0.day == day }?.value
    }

    // MARK: - Finding 4 and ruling A10: a weigh-in save carries the true copies of the row it lands on

    /// Pins review finding 4 and ruling A10. F4 is stored twice, under the active id N and under B,
    /// and a different reading sits at the same instant under C. A weigh-in saved at that instant
    /// lands on N's row: the copy under B takes the same value under its own id, so the reading
    /// stays one line, and the conflicting row under C is byte-identical. Before the ruling the copy
    /// kept the replaced value and came back as a third reading.
    func testWeighInSaveOntoACopiedReadingKeepsCopiesInStepAndLeavesAConflictAlone() async throws {
        let store = try await storeWithCopiesAndAConflictAtT4()
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        let before = try await Fx.snapshot(store)
        let countsBefore = try await Fx.countsById(store)
        XCTAssertEqual(countsBefore, Self.countsWithCopiesAndConflict, "before")
        let listedBefore = await h.weighIns.readings(.weight)
        XCTAssertEqual(listedBefore.filter { $0.takenAt == Fx.t4 }, [Fx.f4, Self.conflictAtT4],
                       "the premise: the copy is not a line of its own")

        let saved = try await h.weighIns.save(weight: 97.1, waist: nil, unitSystem: .metric, takenAt: Fx.date(Fx.t4))

        var f4 = Fx.f4, copy = Fx.f4CopyUnderB
        f4.value = 97.1
        copy.value = 97.1
        XCTAssertEqual(saved, [f4], "the returned row is the active id's row as stored")
        let after = try await Fx.snapshot(store)
        XCTAssertEqual(after, expected(before, replacing: [f4, copy]),
                       "the copy under B followed under its own id; every other row, the conflict included, is as it was")
        let countsAfter = try await Fx.countsById(store)
        XCTAssertEqual(countsAfter, Self.countsWithCopiesAndConflict, "after: no row added or removed")
        let listedAfter = await h.weighIns.readings(.weight)
        XCTAssertEqual(listedAfter, [Fx.f1, Fx.f2, Fx.f9, Fx.f3, Fx.f8, f4, Self.conflictAtT4],
                       "still two readings on 2031-01-29: the saved one, once, and the conflicting one")
    }

    // MARK: - Ruling A10: a weigh-in edit, delete or save touches one of two conflicting readings

    /// Pins ruling A10 through the weigh-in store. F3 (98.0, under C) and F8 (98.4, under N) are two
    /// readings at one instant. A value edit of either changes that row only, and the history keeps
    /// listing both with their own values.
    func testWeighInValueEditOfOneConflictingReadingChangesOnlyThatRow() async throws {
        for target in [Fx.f3, Fx.f8] {
            let store = try await Fx.seededStore()
            let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
            let countsBefore = try await Fx.countsById(store)
            XCTAssertEqual(countsBefore, Fx.countsById, "before editing \(target.id)")

            let edited = try await h.weighIns.edit(target, value: 97.9, unitSystem: .metric, takenAt: Fx.date(Fx.t3))

            var changed = target
            changed.value = 97.9
            XCTAssertEqual(edited, changed, "the edited row keeps its id and its device id")
            let after = try await Fx.snapshot(store)
            XCTAssertEqual(after, expected(Fx.storedOrder, replacing: [changed]),
                           "editing \(target.id): the other reading at the instant keeps every column")
            let countsAfter = try await Fx.countsById(store)
            XCTAssertEqual(countsAfter, Fx.countsById, "after editing \(target.id)")
            let listed = await h.weighIns.readings(.weight)
            XCTAssertEqual(listed, expected(Fx.weightHistory, replacing: [changed]),
                           "editing \(target.id): both readings are still listed")
        }
    }

    /// Pins ruling A10: deleting one of two conflicting readings leaves the other stored and listed.
    func testWeighInDeleteOfOneConflictingReadingLeavesTheOther() async throws {
        for target in [Fx.f3, Fx.f8] {
            let other = target.id == Fx.f3.id ? Fx.f8 : Fx.f3
            let store = try await Fx.seededStore()
            let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
            let countsBefore = try await Fx.countsById(store)
            XCTAssertEqual(countsBefore, Fx.countsById, "before deleting \(target.id)")

            try await h.weighIns.delete(target)

            let after = try await Fx.snapshot(store)
            XCTAssertEqual(after, expected(Fx.storedOrder, removing: [target.id]), "deleting \(target.id)")
            var counts = Fx.countsById
            counts[target.deviceId, default: 0] -= 1
            let countsAfter = try await Fx.countsById(store)
            XCTAssertEqual(countsAfter, counts, "after deleting \(target.id)")
            let listed = await h.weighIns.readings(.weight)
            XCTAssertEqual(listed, expected(Fx.weightHistory, removing: [target.id]))
            XCTAssertTrue(listed.contains(other), "deleting \(target.id): the other reading stays")
        }
    }

    /// Pins ruling A10: a weigh-in saved onto an instant that holds a conflict lands on the active
    /// id's row and leaves the conflicting row byte-identical. With an active id that holds no row
    /// there the save is refused and nothing at all changes.
    func testWeighInSaveLandingOnAConflictUpdatesOnlyTheActiveIdsRow() async throws {
        let store = try await Fx.seededStore()
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)

        let saved = try await h.weighIns.save(weight: 98.3, waist: nil, unitSystem: .metric, takenAt: Fx.date(Fx.t3))

        var f8 = Fx.f8
        f8.value = 98.3
        XCTAssertEqual(saved, [f8])
        let after = try await Fx.snapshot(store)
        XCTAssertEqual(after, expected(Fx.storedOrder, replacing: [f8]), "F3 keeps 98.0 and every other column")
        let countsAfter = try await Fx.countsById(store)
        XCTAssertEqual(countsAfter, Fx.countsById)
        let listed = await h.weighIns.readings(.weight)
        XCTAssertEqual(listed, expected(Fx.weightHistory, replacing: [f8]))

        // Active id A holds no row at that instant.
        let other = try await Fx.seededStore()
        let ha = try H.make(store: other, activeDeviceId: Fx.a, suites: &suites)
        await assertThrows(.instantOccupied) {
            _ = try await ha.weighIns.save(weight: 98.3, waist: nil, unitSystem: .metric, takenAt: Fx.date(Fx.t3))
        }
        let untouched = try await Fx.snapshot(other)
        XCTAssertEqual(untouched, Fx.storedOrder, "a refused save writes nothing")
        let cells = try await Fx.labBookCells(other)
        XCTAssertEqual(cells, Fx.cells)
    }

    // MARK: - Ruling A10: true copies stay in step, beside a conflict

    /// Pins ruling A10: a set of true copies behaves as one reading through a value edit, a date
    /// edit and a delete, and none of the three reaches the conflicting reading at the same instant.
    func testTrueCopiesStayInStepThroughAValueEditADateEditAndADeleteBesideAConflict() async throws {
        let conflict = Self.conflictAtT4

        // A value edit.
        let store = try await storeWithCopiesAndAConflictAtT4()
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        var before = try await Fx.snapshot(store)
        let edited = try await h.weighIns.edit(Fx.f4, value: 97.0, unitSystem: .metric, takenAt: Fx.date(Fx.t4))
        var f4 = Fx.f4, copy = Fx.f4CopyUnderB
        f4.value = 97.0
        copy.value = 97.0
        XCTAssertEqual(edited, f4)
        var after = try await Fx.snapshot(store)
        XCTAssertEqual(after, expected(before, replacing: [f4, copy]), "the value edit: both copies, nothing else")
        var counts = try await Fx.countsById(store)
        XCTAssertEqual(counts, Self.countsWithCopiesAndConflict, "after the value edit")
        var listed = await h.weighIns.readings(.weight)
        XCTAssertEqual(listed.filter { $0.takenAt == Fx.t4 }, [f4, conflict], "one line for the copies, one for the conflict")

        // A date edit of the same reading.
        before = after
        let moved = try await h.weighIns.edit(f4, value: 97.0, unitSystem: .metric, takenAt: Fx.date(Fx.t5))
        XCTAssertEqual(moved.takenAt, Fx.t5)
        XCTAssertEqual(moved.deviceId, Fx.n)
        XCTAssertEqual(moved.value, 97.0)
        after = try await Fx.snapshot(store)
        XCTAssertEqual(after, expected(before, removing: [f4.id, copy.id], adding: [moved]),
                       "the date edit: both old copies gone, one row at the new instant, the conflict as it was")
        counts = try await Fx.countsById(store)
        XCTAssertEqual(counts, [Fx.a: 1, Fx.b: 3, Fx.c: 3, Fx.d: 1, Fx.n: 3], "after the date edit")
        listed = await h.weighIns.readings(.weight)
        XCTAssertEqual(listed.filter { $0.takenAt >= Fx.t4 }, [conflict, moved])

        // A delete of a reading stored twice, on a fresh store.
        let second = try await storeWithCopiesAndAConflictAtT4()
        let h2 = try H.make(store: second, activeDeviceId: Fx.n, suites: &suites)
        before = try await Fx.snapshot(second)
        try await h2.weighIns.delete(Fx.f4)
        after = try await Fx.snapshot(second)
        XCTAssertEqual(after, expected(before, removing: [Fx.f4.id, Fx.f4CopyUnderB.id]),
                       "the delete: both copies gone, the conflict as it was")
        counts = try await Fx.countsById(second)
        XCTAssertEqual(counts, [Fx.a: 1, Fx.b: 3, Fx.c: 3, Fx.d: 1, Fx.n: 2], "after the delete")
        listed = await h2.weighIns.readings(.weight)
        XCTAssertEqual(listed.filter { $0.takenAt == Fx.t4 }, [conflict], "the deleted reading does not come back")
    }

    // MARK: - Ruling A10 on the Lab Book screen's writes (findings 1 and 3)

    /// Pins ruling A10 and review findings 1 and 3 for the Lab Book screen. Its save and its CSV
    /// import build each row with a fresh id under the active id and write through the owner-scope
    /// upsert. Onto the instant F3 and F8 share, with N active, that write lands on F8 alone: F3
    /// keeps its value, and the list, the weigh-in history and a later delete all still see two
    /// readings. Before the ruling both rows took the saved value and one delete removed both.
    func testLabBookSaveOntoAConflictChangesOnlyTheActiveIdsRowAndBothStayListed() async throws {
        let store = try await Fx.seededStore()
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        var draft = Fx.f8
        draft.id = "weight-\(Fx.t3)-\(UUID().uuidString.prefix(8))"
        draft.deviceId = h.repo.deviceId
        draft.value = 98.2

        let written = try await store.upsertOwnerLabMarkers([draft])

        XCTAssertEqual(written, 1, "one stored row, not both rows of the identity")
        var f8 = Fx.f8
        f8.value = 98.2
        let after = try await Fx.snapshot(store)
        XCTAssertEqual(after, expected(Fx.storedOrder, replacing: [f8]), "F3 keeps 98.0 and every other column")
        let counts = try await Fx.countsById(store)
        XCTAssertEqual(counts, Fx.countsById, "no row added under any id")
        let listed = await LabBookRows.all(store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(listed, expected(Fx.mergedWithNActive, replacing: [f8]), "both readings are listed")
        let history = await h.weighIns.readings(.weight)
        XCTAssertEqual(history, expected(Fx.weightHistory, replacing: [f8]))

        // Deleting the line just saved removes that reading alone.
        let deleted = try await store.deleteLabMarkerAndCopies(id: f8.id)
        XCTAssertEqual(deleted, [f8.id])
        let afterDelete = try await Fx.snapshot(store)
        XCTAssertEqual(afterDelete, expected(Fx.storedOrder, removing: [f8.id]), "F3 is still stored")
        let remaining = await LabBookRows.marker("weight", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(remaining, [Fx.f1, Fx.f2, Fx.f9, Fx.f3, Fx.f4])
    }

    /// Pins ruling A10 where the active id holds no row at the conflicting identity (A is active; F3
    /// is under C and F8 under N). Whatever the save does with the incoming reading, neither stored
    /// reading changes and both are still listed.
    func testLabBookSaveOntoAConflictHeldOnlyUnderOtherIdsChangesNeitherReading() async throws {
        let store = try await Fx.seededStore()
        let h = try H.make(store: store, activeDeviceId: Fx.a, suites: &suites)
        var draft = Fx.f8
        draft.id = "weight-\(Fx.t3)-\(UUID().uuidString.prefix(8))"
        draft.deviceId = h.repo.deviceId
        draft.value = 97.0

        do {
            try await store.upsertOwnerLabMarkers([draft])
        } catch {
            // Refusing the write is acceptable: the ruling fixes only what may not change.
        }

        let after = try await Fx.snapshot(store)
        for row in Fx.storedOrder {
            XCTAssertTrue(after.contains(row), "\(row.id) changed or went")
        }
        XCTAssertLessThanOrEqual(after.count, Fx.storedOrder.count + 1, "at most the incoming reading was added")
        for extra in after where !Fx.storedOrder.contains(where: { $0.id == extra.id }) {
            XCTAssertEqual(extra, draft, "a new row can only be the incoming reading, stored as given")
        }
        let listed = await LabBookRows.marker("weight", store: store, activeDeviceId: Fx.a)
        XCTAssertTrue(listed.contains(Fx.f3), "98.0 is still listed")
        XCTAssertTrue(listed.contains(Fx.f8), "98.4 is still listed")
    }

    // MARK: - Ruling A11: the repair at open (finding 2)

    /// Pins ruling A11 and review finding 2 at the step the repository runs after the store opens.
    /// The 2031-01-22 weight cell holds 98.0, F3's value, while F8 (98.4) has the greater id at the
    /// same instant. The cell holds a reading the owner entered, so the repair leaves it, and with
    /// nothing inserted or updated it logs nothing. A cell no row backs is kept the same way.
    func testRepairAtOpenLeavesACellHoldingAStoredReadingsValueAndLogsNothing() async throws {
        let store = try await Fx.seededStore()
        try await Fx.setCell(Fx.Cell(key: "weight", day: Fx.day3, value: 98.0), in: store)
        try await Fx.setCell(Fx.Cell(key: "weight", day: "2031-02-05", value: 97.5), in: store)
        let rowsBefore = try await Fx.snapshot(store)
        let cellsBefore = try await Fx.labBookCells(store)
        XCTAssertEqual(cellsBefore.first { $0.key == "weight" && $0.day == Fx.day3 }?.value, 98.0)
        let lines = Lines()

        for run in 1...2 {
            await Repository.repairLabBookProjection(afterOpening: store) { lines.all.append($0) }

            let cells = try await Fx.labBookCells(store)
            XCTAssertEqual(cells, cellsBefore, "run \(run): every cell is exactly as stored")
            XCTAssertEqual(lines.all, [], "run \(run): nothing was inserted or updated, so nothing is logged")
            let rows = try await Fx.snapshot(store)
            XCTAssertEqual(rows, rowsBefore, "run \(run): the repair writes derived cells only")
            let counts = try await Fx.countsById(store)
            XCTAssertEqual(counts, Fx.countsById, "run \(run)")
        }
    }

    // MARK: - Ruling A11: a write does not erase a cell no stored row backs

    /// Pins ruling A11 for the Lab Book screen's delete. The `fixture_note` cell of 2031-01-15 holds
    /// a number that no stored row backs (F10, the only reading of that marker and day, is text).
    /// Deleting F10 leaves the cell: it may be the last trace of an earlier reading. The repair at
    /// open then leaves it too and logs nothing.
    func testLabBookDeleteDoesNotEraseACellNoStoredRowBacks() async throws {
        let store = try await Fx.seededStore()
        let trace = Fx.Cell(key: "fixture_note", day: Fx.day2, value: 97.5)
        try await Fx.setCell(trace, in: store)
        let cellsBefore = try await Fx.labBookCells(store)
        XCTAssertEqual(cellsBefore, [trace] + Fx.cells)
        let countsBefore = try await Fx.countsById(store)
        XCTAssertEqual(countsBefore, Fx.countsById, "before")

        let deleted = try await store.deleteLabMarkerAndCopies(id: Fx.f10.id)

        XCTAssertEqual(deleted, [Fx.f10.id])
        let rows = try await Fx.snapshot(store)
        XCTAssertEqual(rows, expected(Fx.storedOrder, removing: [Fx.f10.id]), "the nine other rows are untouched")
        let countsAfter = try await Fx.countsById(store)
        XCTAssertEqual(countsAfter, [Fx.a: 1, Fx.b: 3, Fx.c: 1, Fx.d: 1, Fx.n: 3], "after")
        let cells = try await Fx.labBookCells(store)
        XCTAssertEqual(cells, cellsBefore, "the delete erased a cell no stored row backed")

        let lines = Lines()
        await Repository.repairLabBookProjection(afterOpening: store) { lines.all.append($0) }
        let afterRepair = try await Fx.labBookCells(store)
        XCTAssertEqual(afterRepair, cellsBefore)
        XCTAssertEqual(lines.all, [])
    }

    // MARK: - Ruling A11: true copies stored under different days (finding 5)

    /// Pins ruling A11 and review finding 5. One weigh-in is stored twice, under B with the day
    /// 2031-01-07 and under N with the day 2031-01-08. The history lists it once and two cells are
    /// projected. A weigh-in value edit keeps the copies in step and both cells; the repair at open
    /// finds nothing to do; and a Lab Book save landing on the reading keeps a cell on BOTH days.
    func testTrueCopiesStoredUnderDifferentDaysKeepBothDaysCells() async throws {
        let earlyDay = "2031-01-07"
        let old = Fx.row(id: "weight-1925622000-F00000B1", deviceId: Fx.b, markerKey: "weight",
                         category: "bodyMeasurement", day: earlyDay, takenAt: Fx.t1, value: 100.0, unit: "kg")
        let new = Fx.row(id: "weight-1925622000-F00000N1", deviceId: Fx.n, markerKey: "weight",
                         category: "bodyMeasurement", day: Fx.day1, takenAt: Fx.t1, value: 100.0, unit: "kg")
        let store = try await Fx.emptyStoreWithRegistry()
        try await store.upsertLabMarkers([old, new])
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        let cellsBefore = try await Fx.labBookCells(store)
        XCTAssertEqual(cellsBefore, [Fx.Cell(key: "weight", day: earlyDay, value: 100.0),
                                     Fx.Cell(key: "weight", day: Fx.day1, value: 100.0)],
                       "the premise: one cell per stored day")
        let listedBefore = await h.weighIns.readings(.weight)
        XCTAssertEqual(listedBefore, [new], "the premise: one line")

        // A weigh-in value edit.
        let edited = try await h.weighIns.edit(new, value: 99.5, unitSystem: .metric, takenAt: Fx.date(Fx.t1))
        var oldEdited = old, newEdited = new
        oldEdited.value = 99.5
        newEdited.value = 99.5
        XCTAssertEqual(edited, newEdited)
        var rows = try await Fx.snapshot(store)
        XCTAssertEqual(rows, [oldEdited, newEdited], "each copy took the value under its own id and its own day")
        var cells = try await Fx.labBookCells(store)
        XCTAssertEqual(cells, [Fx.Cell(key: "weight", day: earlyDay, value: 99.5),
                               Fx.Cell(key: "weight", day: Fx.day1, value: 99.5)], "both days keep their cell")
        let listed = await h.weighIns.readings(.weight)
        XCTAssertEqual(listed, [newEdited], "still one line")

        // The repair at open reports nothing to do.
        let lines = Lines()
        await Repository.repairLabBookProjection(afterOpening: store) { lines.all.append($0) }
        XCTAssertEqual(lines.all, [])
        let afterRepair = try await Fx.labBookCells(store)
        XCTAssertEqual(afterRepair, cells)

        // A Lab Book save landing on the reading: a fresh id under the active id.
        var draft = newEdited
        draft.id = "weight-\(Fx.t1)-\(UUID().uuidString.prefix(8))"
        draft.value = 99.0
        let written = try await store.upsertOwnerLabMarkers([draft])
        XCTAssertEqual(written, 2, "the row it lands on and its copy")
        rows = try await Fx.snapshot(store)
        XCTAssertEqual(rows.map(\.id), [old.id, new.id], "no row added, none removed")
        XCTAssertEqual(rows.map(\.deviceId), [Fx.b, Fx.n])
        XCTAssertEqual(rows.map(\.value), [99.0, 99.0], "the copies stay in step")
        cells = try await Fx.labBookCells(store)
        XCTAssertEqual(cells.filter { $0.key == "weight" }.count, 2, "a day lost its cell")
        let earlyCell = try await cellValue(store, "weight", earlyDay)
        XCTAssertNotNil(earlyCell, "the earlier day lost its cell")
        let lateCell = try await cellValue(store, "weight", Fx.day1)
        XCTAssertEqual(lateCell, 99.0)
    }
}
