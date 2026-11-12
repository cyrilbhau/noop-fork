import XCTest
@testable import WhoopStore

// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/labbook-ownership.md §6.1, in the new file
// Packages/WhoopStore/Sources/WhoopStore/LabMarkerOwnership.swift:
//
//   public enum LabMarkerUnion {
//       public struct ReadingKey: Hashable, Sendable {
//           public let markerKey: String
//           public let takenAt: Int
//           public let source: String
//       }
//       public static func key(_ row: LabMarkerRow) -> ReadingKey
//       public static func isCopy(_ a: LabMarkerRow, _ b: LabMarkerRow) -> Bool
//       public static func merged(_ rows: [LabMarkerRow], activeDeviceId: String) -> [LabMarkerRow]
//       public static func copies(of row: LabMarkerRow, in rows: [LabMarkerRow]) -> [LabMarkerRow]
//       public static func conflictingKeys(_ rows: [LabMarkerRow]) -> [ReadingKey]
//   }
//
// No initialiser of `ReadingKey` is called: keys are obtained from `key(_:)` and read field by field.
// Existing API used: `LabMarkerRow` and its memberwise initialiser.
//
// Specification §7.1 (the rules), §12.1 (cases 1 to 15), §12.8 (faults F5 to F9) and §13 (fixture).
// Synthetic values only.

final class LabMarkerUnionTests: XCTestCase {

    private typealias Fx = LabBookOwnershipFixture

    // MARK: - Helpers

    /// A further row at the identity of F6 and F7 (`ldl`, t2, `lab-csv`), equal to them in content
    /// unless a field is overridden.
    private func ldlRow(id: String, deviceId: String, value: Double? = 3.0, note: String? = "fixture panel",
                        day: String = Fx.day2) -> LabMarkerRow {
        Fx.row(id: id, deviceId: deviceId, markerKey: "ldl", category: "bloodPanel", day: day,
               takenAt: Fx.t2, value: value, unit: "mmol/L", source: "lab-csv", note: note)
    }

    /// F7 with one change applied.
    private func f7(_ change: (inout LabMarkerRow) -> Void) -> LabMarkerRow {
        var row = Fx.f7
        change(&row)
        return row
    }

    /// Asserts that `a` and `b` are different readings in both argument orders and that a merge keeps
    /// both, whichever id is active.
    private func assertBothKept(_ a: LabMarkerRow, _ b: LabMarkerRow, _ message: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(LabMarkerUnion.isCopy(a, b), message, file: file, line: line)
        XCTAssertFalse(LabMarkerUnion.isCopy(b, a), message, file: file, line: line)
        let expected = [a, b].sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
        for active in [a.deviceId, b.deviceId, "no-such-device"] {
            XCTAssertEqual(LabMarkerUnion.merged([a, b], activeDeviceId: active), expected, message,
                           file: file, line: line)
            XCTAssertEqual(LabMarkerUnion.merged([b, a], activeDeviceId: active), expected, message,
                           file: file, line: line)
        }
    }

    /// The copy rule of §7.1 written out a second time, as the oracle of the generated-input check.
    private func oracleIsCopy(_ a: LabMarkerRow, _ b: LabMarkerRow) -> Bool {
        a.markerKey == b.markerKey && a.takenAt == b.takenAt && a.source == b.source
            && a.category == b.category && a.value == b.value && a.valueText == b.valueText
            && a.unit == b.unit && a.note == b.note && a.referenceText == b.referenceText
    }

    /// `merged` of §7.1 computed the long way: group into copy classes, take each class's
    /// representative, order by (`takenAt`, `id`).
    private func oracleMerged(_ rows: [LabMarkerRow], active: String) -> [LabMarkerRow] {
        var classes: [[LabMarkerRow]] = []
        for row in rows {
            if let i = classes.firstIndex(where: { oracleIsCopy($0[0], row) }) {
                classes[i].append(row)
            } else {
                classes.append([row])
            }
        }
        let representatives = classes.map { members -> LabMarkerRow in
            members.min { x, y in
                let xActive = x.deviceId == active, yActive = y.deviceId == active
                if xActive != yActive { return xActive }
                if x.deviceId != y.deviceId { return x.deviceId < y.deviceId }
                return x.id < y.id
            }!
        }
        return representatives.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
    }

    /// Every permutation of `items`, by Heap's algorithm.
    private func permutations<T>(_ items: [T]) -> [[T]] {
        var out: [[T]] = []
        var work = items
        func heap(_ k: Int) {
            if k <= 1 { out.append(work); return }
            for i in 0..<k {
                heap(k - 1)
                work.swapAt(k % 2 == 0 ? i : 0, k - 1)
            }
        }
        heap(work.count)
        return out
    }

    // MARK: - §12.1 case 1

    /// Protects: no reading is dropped when every identity is distinct, and the result is ordered by
    /// (`takenAt`, `id`), not by the order the merge walks the rows in. Fault F9 (the final sort
    /// dropped) is visible at t1: with A active the walk meets F1 (A) before F5 (D), and with N active
    /// it meets F1 before F5 as well ("my-whoop" < "oura-…"), while the result must list F5 first
    /// ("waist-…" < "weight-…").
    func testRowsWithDistinctIdentitiesAllSurviveMergeInInstantOrder() {
        let input = [Fx.f4, Fx.f9, Fx.f2, Fx.f10, Fx.f1, Fx.f5]
        let expected = [Fx.f5, Fx.f1, Fx.f10, Fx.f2, Fx.f9, Fx.f4]
        XCTAssertEqual(LabMarkerUnion.merged(input, activeDeviceId: Fx.a), expected)
        XCTAssertEqual(LabMarkerUnion.merged(input, activeDeviceId: Fx.n), expected)
        XCTAssertEqual(LabMarkerUnion.merged(input, activeDeviceId: "no-such-device"), expected)
    }

    /// Protects: the §13 expectation for the whole fixture with N active, nine readings.
    func testMergeOfTheWholeFixtureWithNActiveListsNineReadingsInInstantOrder() {
        let merged = LabMarkerUnion.merged(Fx.all, activeDeviceId: Fx.n)
        XCTAssertEqual(merged, Fx.mergedWithNActive)
        XCTAssertEqual(merged.count, 9)
    }

    // MARK: - §12.1 cases 2 to 4

    /// Protects: of two copies the active id's row is the one listed (fault F8).
    func testCopiesUnderTwoIdsCollapseToTheActiveIdsRow() {
        XCTAssertTrue(LabMarkerUnion.isCopy(Fx.f6, Fx.f7))
        XCTAssertTrue(LabMarkerUnion.isCopy(Fx.f7, Fx.f6))
        // N active: F7 is N's row.
        XCTAssertEqual(LabMarkerUnion.merged([Fx.f6, Fx.f7], activeDeviceId: Fx.n), [Fx.f7])
        XCTAssertEqual(LabMarkerUnion.merged([Fx.f7, Fx.f6], activeDeviceId: Fx.n), [Fx.f7])
        // B active: F6 is B's row, although "whoop-FIXTURE-OLD" sorts after "whoop-FIXTURE-NEW".
        XCTAssertEqual(LabMarkerUnion.merged([Fx.f6, Fx.f7], activeDeviceId: Fx.b), [Fx.f6])
        XCTAssertEqual(LabMarkerUnion.merged([Fx.f7, Fx.f6], activeDeviceId: Fx.b), [Fx.f6])
    }

    /// Protects: with no copy under the active id the representative is the smallest device id, and
    /// only then the smallest id. F6 has the smaller id and the greater device id, so a rule that
    /// looked at `id` first would pick it.
    func testCopiesWithNoActiveRowCollapseToTheSmallestDeviceIdThenSmallestId() {
        for active in [Fx.a, Fx.c, Fx.d, "", "no-such-device"] {
            XCTAssertEqual(LabMarkerUnion.merged([Fx.f6, Fx.f7], activeDeviceId: active), [Fx.f7],
                           "active \(active): whoop-FIXTURE-NEW sorts before whoop-FIXTURE-OLD")
        }
        // The same device id on both: the smaller id is kept.
        let lower = ldlRow(id: "ldl-1926226800-F0000011", deviceId: Fx.c)
        let higher = ldlRow(id: "ldl-1926226800-F0000012", deviceId: Fx.c)
        XCTAssertEqual(LabMarkerUnion.merged([higher, lower], activeDeviceId: Fx.n), [lower])
        XCTAssertEqual(LabMarkerUnion.merged([lower, higher], activeDeviceId: Fx.n), [lower])
    }

    /// Protects: any number of copies is one reading.
    func testThreeCopiesCollapseToOne() {
        let third = ldlRow(id: "ldl-1926226800-F0000011", deviceId: Fx.a)
        let rows = [Fx.f6, Fx.f7, third]
        XCTAssertEqual(LabMarkerUnion.merged(rows, activeDeviceId: Fx.n), [Fx.f7])
        XCTAssertEqual(LabMarkerUnion.merged(rows, activeDeviceId: Fx.b), [Fx.f6])
        XCTAssertEqual(LabMarkerUnion.merged(rows, activeDeviceId: Fx.a), [third])
        // No active copy: "my-whoop" is the smallest device id of the three.
        XCTAssertEqual(LabMarkerUnion.merged(rows, activeDeviceId: Fx.c), [third])
    }

    // MARK: - §12.1 cases 5 and 6 (faults F5, F7)

    /// Protects: two readings at one identity with different values are both listed (ruling R42,
    /// decision D3). Fault F5 collapses them. The value is compared exactly: one unit in the last
    /// place either side of 98.4 is a different reading, 98.4 itself is the same one.
    func testRowsDifferingInValueAtOneIdentityAreBothKept() {
        assertBothKept(Fx.f3, Fx.f8, "98.0 and 98.4 at one instant are two readings")
        XCTAssertEqual(LabMarkerUnion.merged(Fx.all, activeDeviceId: Fx.n).filter { $0.takenAt == Fx.t3 },
                       [Fx.f3, Fx.f8])

        var twin = Fx.f3
        twin.value = 98.4
        XCTAssertTrue(LabMarkerUnion.isCopy(twin, Fx.f8), "equal values at one identity are one reading")
        XCTAssertEqual(LabMarkerUnion.merged([twin, Fx.f8], activeDeviceId: Fx.n), [Fx.f8])
        twin.value = (98.4).nextUp
        assertBothKept(twin, Fx.f8, "one unit in the last place above")
        twin.value = (98.4).nextDown
        assertBothKept(twin, Fx.f8, "one unit in the last place below")
    }

    /// Protects: `unit` is part of what makes two rows the same reading.
    func testRowsDifferingOnlyInUnitAreBothKept() {
        assertBothKept(Fx.f6, f7 { $0.unit = "mg/dL" }, "another unit")
        assertBothKept(Fx.f6, f7 { $0.unit = "" }, "an empty unit")
    }

    /// Protects: `note` is part of what makes two rows the same reading (fault F7), and a missing note
    /// equals only a missing note.
    func testRowsDifferingOnlyInNoteAreBothKept() {
        assertBothKept(Fx.f6, f7 { $0.note = "fixture panel, repeat" }, "another note")
        assertBothKept(Fx.f6, f7 { $0.note = nil }, "a note against none")
        assertBothKept(f7 { $0.note = nil }, ldlRow(id: "ldl-1926226800-F0000011", deviceId: Fx.b, note: ""),
                       "nil against an empty string")
    }

    /// Protects: `referenceText` is part of what makes two rows the same reading.
    func testRowsDifferingOnlyInReferenceTextAreBothKept() {
        assertBothKept(Fx.f6, f7 { $0.referenceText = "fixture range" }, "a range against none")
        assertBothKept(f7 { $0.referenceText = "fixture range" },
                       { var r = Fx.f6; r.referenceText = "fixture range 2"; return r }(), "two ranges")
        assertBothKept(Fx.f6, f7 { $0.referenceText = "" }, "nil against an empty string")
    }

    /// Protects: `valueText` is part of what makes two rows the same reading.
    func testRowsDifferingOnlyInValueTextAreBothKept() {
        assertBothKept(Fx.f6, f7 { $0.valueText = "clear" }, "text against none")
        assertBothKept(Fx.f6, f7 { $0.valueText = "" }, "nil against an empty string")
        var other = Fx.f10
        other.id = "fixture_note-1926226800-F0000011"
        other.deviceId = Fx.n
        other.valueText = "cloudy"
        assertBothKept(Fx.f10, other, "two texts")
    }

    /// Protects: `category` is part of what makes two rows the same reading.
    func testRowsDifferingOnlyInCategoryAreBothKept() {
        assertBothKept(Fx.f6, f7 { $0.category = "other" }, "another category")
    }

    // MARK: - §12.1 cases 7 to 9

    /// Protects: `day` is derived from the instant and the zone of the write, so it does not make two
    /// rows different readings (fault F6, ruling R39). `id` and `deviceId` do not either.
    func testRowsDifferingOnlyInDayAreCopies() {
        let otherDay = f7 { $0.day = "2031-01-14" }
        XCTAssertTrue(LabMarkerUnion.isCopy(Fx.f6, otherDay))
        XCTAssertTrue(LabMarkerUnion.isCopy(otherDay, Fx.f6))
        XCTAssertEqual(LabMarkerUnion.merged([Fx.f6, otherDay], activeDeviceId: Fx.n), [otherDay])
        XCTAssertEqual(LabMarkerUnion.merged([Fx.f6, otherDay], activeDeviceId: Fx.b), [Fx.f6])
        XCTAssertTrue(LabMarkerUnion.isCopy(Fx.f6, Fx.f6), "a row is a copy of itself")
    }

    /// Protects: `source` is part of the identity. The same marker and instant from another source is
    /// another reading even when every other column is equal.
    func testRowsDifferingInSourceAreDifferentReadings() {
        let manual = f7 { $0.source = "manual" }
        assertBothKept(Fx.f6, manual, "lab-csv and manual")
        XCTAssertNotEqual(LabMarkerUnion.key(Fx.f6), LabMarkerUnion.key(manual))
        XCTAssertEqual(LabMarkerUnion.conflictingKeys([Fx.f6, manual]).count, 0,
                       "two identities, so no identity holds a conflict")
    }

    /// Protects: `markerKey` is part of the identity.
    func testRowsDifferingInMarkerAreDifferentReadings() {
        let other = f7 { $0.markerKey = "hdl" }
        assertBothKept(Fx.f6, other, "another marker")
        XCTAssertNotEqual(LabMarkerUnion.key(Fx.f6), LabMarkerUnion.key(other))
    }

    /// Protects: the instant is compared to the second. One second either side of t2 is another
    /// reading; t2 itself is the same one.
    func testRowsOneSecondEitherSideOfAnInstantAreDifferentReadings() {
        let same = f7 { _ in }
        XCTAssertTrue(LabMarkerUnion.isCopy(Fx.f6, same))
        XCTAssertEqual(LabMarkerUnion.key(Fx.f6), LabMarkerUnion.key(same))

        let later = f7 { $0.takenAt = Fx.t2 + 1 }
        assertBothKept(Fx.f6, later, "one second later")
        XCTAssertNotEqual(LabMarkerUnion.key(Fx.f6), LabMarkerUnion.key(later))

        let earlier = f7 { $0.takenAt = Fx.t2 - 1 }
        assertBothKept(earlier, Fx.f6, "one second earlier")
        XCTAssertNotEqual(LabMarkerUnion.key(Fx.f6), LabMarkerUnion.key(earlier))
    }

    /// Protects: "not measured" is never zero. A row with no number is not a copy of a row holding 0.
    func testNilAndZeroValuesAreNotCopies() {
        var zero = Fx.f10
        zero.id = "fixture_note-1926226800-F0000011"
        zero.deviceId = Fx.n
        zero.value = 0.0
        assertBothKept(Fx.f10, zero, "nil against 0.0")

        var alsoNil = zero
        alsoNil.value = nil
        XCTAssertTrue(LabMarkerUnion.isCopy(Fx.f10, alsoNil), "nil equals nil")
        XCTAssertEqual(LabMarkerUnion.merged([Fx.f10, alsoNil], activeDeviceId: Fx.n), [alsoNil])
    }

    /// Protects: a non-finite value never causes a reading to be hidden.
    // SPEC-AMBIGUITY: §7.1 says optionals compare with `==` and says nothing about a value that is not
    // a number. Under `==` a NaN equals nothing, itself included, so two rows holding NaN are not
    // copies and both are listed. That is also the reading the rulings favour (nothing hidden). The
    // store cannot hold such a row (SQLite stores NaN as NULL), so this is a rule of the pure function.
    func testRowsHoldingNotANumberAreNeverCollapsed() {
        var x = Fx.f6
        x.value = .nan
        var y = Fx.f7
        y.value = .nan
        XCTAssertFalse(LabMarkerUnion.isCopy(x, y))
        XCTAssertEqual(LabMarkerUnion.merged([x, y], activeDeviceId: Fx.n).map(\.id), [x.id, y.id])
        XCTAssertEqual(LabMarkerUnion.merged([y, x], activeDeviceId: Fx.b).map(\.id), [x.id, y.id])

        // Infinity is an ordinary value under `==`: equal to itself, different from a finite number.
        x.value = .infinity
        y.value = .infinity
        XCTAssertTrue(LabMarkerUnion.isCopy(x, y))
        y.value = 3.0
        XCTAssertFalse(LabMarkerUnion.isCopy(x, y))
        XCTAssertEqual(LabMarkerUnion.merged([x, y], activeDeviceId: Fx.n).count, 2)
    }

    // MARK: - §12.1 cases 10 to 12

    /// Protects: an empty list is a valid input to every function.
    func testMergeOfAnEmptyListIsEmpty() {
        XCTAssertEqual(LabMarkerUnion.merged([], activeDeviceId: Fx.n), [])
        XCTAssertEqual(LabMarkerUnion.merged([], activeDeviceId: ""), [])
        XCTAssertEqual(LabMarkerUnion.conflictingKeys([]).count, 0)
    }

    /// Protects: the result does not depend on the order the store returned the rows in (fault F9).
    ///
    /// Not every permutation of all ten rows is tried: that is 3,628,800 merges, minutes in a debug
    /// build. Instead: every permutation (5,040) of the seven rows that share an instant with another
    /// row (t2: F2, F6, F7, F10; t3 and t3a: F3, F8, F9) with the other three placed first and then
    /// last; plus the ten rows reversed, in every rotation, and in 2,000 fixed-seed shuffles.
    func testMergeIsIndependentOfInputOrder() {
        let expected = Fx.mergedWithNActive
        let crowded = [Fx.f2, Fx.f6, Fx.f7, Fx.f10, Fx.f3, Fx.f8, Fx.f9]
        let rest = [Fx.f1, Fx.f5, Fx.f4]
        var tried = 0
        for permutation in permutations(crowded) {
            XCTAssertEqual(LabMarkerUnion.merged(rest + permutation, activeDeviceId: Fx.n), expected)
            XCTAssertEqual(LabMarkerUnion.merged(permutation + rest.reversed(), activeDeviceId: Fx.n), expected)
            tried += 1
        }
        XCTAssertEqual(tried, 5_040)

        XCTAssertEqual(LabMarkerUnion.merged(Fx.all.reversed(), activeDeviceId: Fx.n), expected)
        for shift in 0..<Fx.all.count {
            let rotated = Array(Fx.all[shift...] + Fx.all[..<shift])
            XCTAssertEqual(LabMarkerUnion.merged(rotated, activeDeviceId: Fx.n), expected, "rotation \(shift)")
        }
        var generator = Fx.Generator(seed: 0x1AB0_0C0F_F1CE_0001)
        for round in 0..<2_000 {
            let shuffled = generator.shuffled(Fx.all)
            XCTAssertEqual(LabMarkerUnion.merged(shuffled, activeDeviceId: Fx.n), expected, "shuffle \(round)")
        }
    }

    /// Protects: an install whose rows all sit under one id gets back exactly those rows (§8.5), with
    /// that id active or not.
    func testMergeOfSingleIdRowsReturnsThemUnchanged() {
        let rows = Fx.singleIdRows
        XCTAssertEqual(rows.count, 8)
        XCTAssertEqual(LabMarkerUnion.merged(rows, activeDeviceId: Fx.a), rows)
        XCTAssertEqual(LabMarkerUnion.merged(rows, activeDeviceId: Fx.n), rows)
        XCTAssertEqual(LabMarkerUnion.merged(rows.reversed(), activeDeviceId: Fx.a), rows,
                       "unchanged apart from order")
        XCTAssertEqual(LabMarkerUnion.conflictingKeys(rows).count, 0)
    }

    /// Protects: the same input gives the same output on every call, and the input is not changed.
    func testMergeIsDeterministic() {
        let input = Fx.all
        let first = LabMarkerUnion.merged(input, activeDeviceId: Fx.n)
        for _ in 0..<20 {
            XCTAssertEqual(LabMarkerUnion.merged(input, activeDeviceId: Fx.n), first)
        }
        XCTAssertEqual(input, Fx.all)
        XCTAssertEqual(LabMarkerUnion.conflictingKeys(input), LabMarkerUnion.conflictingKeys(input))
        XCTAssertEqual(LabMarkerUnion.copies(of: Fx.f7, in: input), LabMarkerUnion.copies(of: Fx.f7, in: input))
    }

    /// Protects: §13, the representative of the `ldl` pair for each active id.
    func testRepresentativeOfTheLdlPairFollowsTheActiveId() {
        func ldl(_ active: String) -> [String] {
            LabMarkerUnion.merged(Fx.all, activeDeviceId: active).filter { $0.markerKey == "ldl" }.map(\.id)
        }
        XCTAssertEqual(ldl(Fx.n), [Fx.f7.id])
        XCTAssertEqual(ldl(Fx.b), [Fx.f6.id])
        XCTAssertEqual(ldl(Fx.a), [Fx.f7.id])
        XCTAssertEqual(ldl(Fx.c), [Fx.f7.id])
        XCTAssertEqual(ldl(Fx.d), [Fx.f7.id])
        // Whichever id is active, nine readings are listed and only F6 or F7 is the one left out.
        for active in [Fx.a, Fx.b, Fx.c, Fx.d, Fx.n] {
            let merged = LabMarkerUnion.merged(Fx.all, activeDeviceId: active)
            XCTAssertEqual(merged.count, 9, "active \(active)")
            let missing = Set(Fx.all.map(\.id)).subtracting(merged.map(\.id))
            XCTAssertEqual(missing, [active == Fx.b ? Fx.f7.id : Fx.f6.id], "active \(active)")
        }
    }

    // MARK: - §12.1 cases 13 to 15

    /// Protects: `copies(of:in:)` is what a delete acts on. It returns the row and its copies and
    /// nothing else, ordered by (`deviceId`, `id`); a conflicting row at the same identity is not one.
    func testCopiesOfReturnsTheRowAndItsCopiesOnly() {
        // "whoop-FIXTURE-NEW" (F7) sorts before "whoop-FIXTURE-OLD" (F6).
        XCTAssertEqual(LabMarkerUnion.copies(of: Fx.f7, in: Fx.all), [Fx.f7, Fx.f6])
        XCTAssertEqual(LabMarkerUnion.copies(of: Fx.f6, in: Fx.all), [Fx.f7, Fx.f6])
        XCTAssertEqual(LabMarkerUnion.copies(of: Fx.f6, in: Fx.all.reversed()), [Fx.f7, Fx.f6])
        // F3 conflicts with F8: neither is a copy of the other.
        XCTAssertEqual(LabMarkerUnion.copies(of: Fx.f8, in: Fx.all), [Fx.f8])
        XCTAssertEqual(LabMarkerUnion.copies(of: Fx.f3, in: Fx.all), [Fx.f3])
        XCTAssertEqual(LabMarkerUnion.copies(of: Fx.f1, in: Fx.all), [Fx.f1])
        XCTAssertEqual(LabMarkerUnion.copies(of: Fx.f10, in: Fx.all), [Fx.f10])

        // Within one device id the order is by id.
        let third = ldlRow(id: "ldl-1926226800-F0000005", deviceId: Fx.n)
        XCTAssertEqual(LabMarkerUnion.copies(of: Fx.f6, in: Fx.all + [third]), [third, Fx.f7, Fx.f6])
    }

    /// Protects: a conflict is reported for an identity only when it holds rows that are not copies of
    /// each other, and the report is ordered by (`takenAt`, `markerKey`, `source`).
    func testConflictingKeysNamesOnlyIdentitiesWithNonCopies() {
        // §13: the one identity (weight, t3, manual).
        let keys = LabMarkerUnion.conflictingKeys(Fx.all)
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys.first?.markerKey, "weight")
        XCTAssertEqual(keys.first?.takenAt, Fx.t3)
        XCTAssertEqual(keys.first?.source, "manual")
        XCTAssertEqual(keys, [LabMarkerUnion.key(Fx.f3)])
        XCTAssertEqual(LabMarkerUnion.key(Fx.f3), LabMarkerUnion.key(Fx.f8))

        // Copies alone are not a conflict; nor is a single row.
        XCTAssertEqual(LabMarkerUnion.conflictingKeys([Fx.f6, Fx.f7]).count, 0)
        XCTAssertEqual(LabMarkerUnion.conflictingKeys([Fx.f1]).count, 0)

        // Four more conflicts, added out of order, come back sorted.
        func other(_ base: LabMarkerRow, id: String, deviceId: String, _ change: (inout LabMarkerRow) -> Void)
            -> LabMarkerRow {
            var row = base
            row.id = id
            row.deviceId = deviceId
            change(&row)
            return row
        }
        let waistConflict = other(Fx.f5, id: "waist-1925622000-F0000011", deviceId: Fx.n) { $0.value = 98.0 }
        let ldlConflict = other(Fx.f6, id: "ldl-1926226800-F0000012", deviceId: Fx.c) { $0.note = nil }
        let weightCsv1 = other(Fx.f3, id: "weight-1926831600-F0000013", deviceId: Fx.a) { $0.source = "lab-csv" }
        let weightCsv2 = other(Fx.f3, id: "weight-1926831600-F0000014", deviceId: Fx.b) {
            $0.source = "lab-csv"; $0.value = 98.2
        }
        let ldlLate1 = other(Fx.f6, id: "ldl-1926831600-F0000015", deviceId: Fx.a) {
            $0.takenAt = Fx.t3; $0.source = "manual"
        }
        let ldlLate2 = other(Fx.f6, id: "ldl-1926831600-F0000016", deviceId: Fx.d) {
            $0.takenAt = Fx.t3; $0.source = "manual"; $0.value = 90.0
        }
        let input = [weightCsv2, ldlLate2, waistConflict, weightCsv1, ldlConflict, ldlLate1] + Fx.all
        let sorted = LabMarkerUnion.conflictingKeys(input)
        XCTAssertEqual(sorted.map(\.takenAt), [Fx.t1, Fx.t2, Fx.t3, Fx.t3, Fx.t3])
        XCTAssertEqual(sorted.map(\.markerKey), ["waist", "ldl", "ldl", "weight", "weight"])
        XCTAssertEqual(sorted.map(\.source), ["manual", "lab-csv", "manual", "lab-csv", "manual"])
        XCTAssertEqual(LabMarkerUnion.conflictingKeys(input.reversed()), sorted, "independent of input order")
    }

    /// Protects: copies and a conflict at one identity together. Two copies and one conflicting row
    /// are two readings (fault F5 lists one), and the identity is named once as a conflict.
    func testTwoCopiesPlusOneConflictListTwoReadings() {
        let conflict = ldlRow(id: "ldl-1926226800-F0000012", deviceId: Fx.c, value: 90.0)
        let rows = [conflict, Fx.f6, Fx.f7]
        XCTAssertEqual(LabMarkerUnion.merged(rows, activeDeviceId: Fx.n), [Fx.f7, conflict])
        XCTAssertEqual(LabMarkerUnion.merged(rows, activeDeviceId: Fx.b), [Fx.f6, conflict])
        XCTAssertEqual(LabMarkerUnion.merged(rows, activeDeviceId: Fx.c), [Fx.f7, conflict])
        XCTAssertEqual(LabMarkerUnion.conflictingKeys(rows), [LabMarkerUnion.key(Fx.f6)])
        XCTAssertEqual(LabMarkerUnion.copies(of: conflict, in: rows), [conflict])
        XCTAssertEqual(LabMarkerUnion.copies(of: Fx.f6, in: rows), [Fx.f7, Fx.f6])
    }

    // MARK: - Identity

    /// Protects: the identity is the store's natural key without the device id, and nothing else.
    func testKeyIsMarkerInstantAndSourceWithoutTheDeviceId() {
        let key = LabMarkerUnion.key(Fx.f6)
        XCTAssertEqual(key.markerKey, "ldl")
        XCTAssertEqual(key.takenAt, Fx.t2)
        XCTAssertEqual(key.source, "lab-csv")
        XCTAssertEqual(key, LabMarkerUnion.key(Fx.f7), "another id and device id, the same identity")
        XCTAssertEqual(key.hashValue, LabMarkerUnion.key(Fx.f7).hashValue)
        // Content does not enter the identity.
        XCTAssertEqual(key, LabMarkerUnion.key(f7 {
            $0.value = 90.0; $0.note = nil; $0.unit = "mg/dL"; $0.day = "2031-01-14"; $0.category = "other"
        }))
        XCTAssertEqual(Set(Fx.all.map(LabMarkerUnion.key)).count, 8, "ten rows, eight identities")
    }

    // MARK: - Generated input

    /// Protects, over 400 generated row sets from a fixed seed: nothing is hidden except a copy of a
    /// listed row; no two listed rows are copies; the listed row of a set of copies is the active
    /// id's, else the smallest (`deviceId`, `id`); the order is (`takenAt`, `id`); the result does not
    /// depend on input order; `copies` and `conflictingKeys` agree with the rule written out by hand.
    func testGeneratedRowSetsNeverHideAReadingThatIsNotACopy() {
        var generator = Fx.Generator(seed: 0x1AB0_0C0F_F1CE_0002)
        let devices = [Fx.a, Fx.b, Fx.c, Fx.d, Fx.n]
        var collapses = 0, conflicts = 0

        for round in 0..<400 {
            let count = generator.below(15)
            var rows: [LabMarkerRow] = []
            for index in 0..<count {
                // A small space, so that copies and conflicts are both common.
                let marker = generator.below(4) == 0 ? "ldl" : "weight"
                let takenAt = Fx.t2 + generator.below(3) - 1
                let source = generator.below(5) == 0 ? "lab-csv" : "manual"
                let value: Double? = [98.0, 98.0, 98.0, 98.4, nil][generator.below(5)]
                // The id's leading characters are random, so id order is unrelated to creation order.
                let id = "g\(generator.below(90) + 10)-\(round)-\(index)"
                rows.append(LabMarkerRow(
                    id: id, deviceId: generator.pick(devices), markerKey: marker,
                    category: generator.below(8) == 0 ? "other" : "bodyMeasurement",
                    day: generator.below(6) == 0 ? "2031-01-14" : Fx.day2, takenAt: takenAt, value: value,
                    valueText: generator.below(8) == 0 ? "clear" : nil,
                    unit: generator.below(8) == 0 ? "lb" : "kg", source: source,
                    note: generator.below(8) == 0 ? "fixture panel" : nil,
                    referenceText: generator.below(10) == 0 ? "fixture range" : nil))
            }
            let active = generator.pick(devices + ["no-such-device"])
            let merged = LabMarkerUnion.merged(rows, activeDeviceId: active)
            let context = "round \(round), active \(active)"

            XCTAssertEqual(merged, oracleMerged(rows, active: active), context)
            XCTAssertEqual(LabMarkerUnion.merged(generator.shuffled(rows), activeDeviceId: active), merged, context)

            let listed = Set(merged.map(\.id))
            XCTAssertEqual(listed.count, merged.count, "\(context): a row listed twice")
            for row in rows {
                XCTAssertTrue(rows.contains(row))
                if !listed.contains(row.id) {
                    XCTAssertTrue(merged.contains { oracleIsCopy($0, row) },
                                  "\(context): \(row.id) is hidden and no listed row is a copy of it")
                }
                // `isCopy` agrees with the rule, in both argument orders.
                for other in rows {
                    XCTAssertEqual(LabMarkerUnion.isCopy(row, other), oracleIsCopy(row, other), context)
                }
                let expectedCopies = rows.filter { oracleIsCopy($0, row) }
                    .sorted { ($0.deviceId, $0.id) < ($1.deviceId, $1.id) }
                XCTAssertEqual(LabMarkerUnion.copies(of: row, in: rows), expectedCopies, context)
            }
            for (i, x) in merged.enumerated() {
                XCTAssertTrue(rows.contains(x), "\(context): a listed row that was not in the input")
                for y in merged[(i + 1)...] {
                    XCTAssertFalse(oracleIsCopy(x, y), "\(context): \(x.id) and \(y.id) are copies, both listed")
                    XCTAssertTrue((x.takenAt, x.id) < (y.takenAt, y.id), "\(context): order")
                }
            }

            // Conflicts: identities held by at least two rows that are not copies of each other.
            var expectedConflicts: [(Int, String, String)] = []
            for key in Set(rows.map { [$0.markerKey, String($0.takenAt), $0.source] }) {
                let members = rows.filter { [$0.markerKey, String($0.takenAt), $0.source] == key }
                if members.contains(where: { !oracleIsCopy($0, members[0]) }) {
                    expectedConflicts.append((members[0].takenAt, members[0].markerKey, members[0].source))
                }
            }
            expectedConflicts.sort { $0 < $1 }
            let reported = LabMarkerUnion.conflictingKeys(rows)
            XCTAssertEqual(reported.map(\.takenAt), expectedConflicts.map { $0.0 }, context)
            XCTAssertEqual(reported.map(\.markerKey), expectedConflicts.map { $0.1 }, context)
            XCTAssertEqual(reported.map(\.source), expectedConflicts.map { $0.2 }, context)

            if merged.count < rows.count { collapses += 1 }
            if !expectedConflicts.isEmpty { conflicts += 1 }
        }
        // The generator must actually reach both situations, or the check above proves nothing.
        XCTAssertGreaterThan(collapses, 50, "too few generated sets held copies")
        XCTAssertGreaterThan(conflicts, 50, "too few generated sets held conflicts")
    }
}
