import Foundation
import GRDB

// LabMarkerOwnership.swift — Lab Book readings at OWNER scope.
//
// Personal fork, stage 1 ruling R42 (docs/personal/superapp/specs/labbook-ownership.md): a Lab Book
// reading is the owner's, whichever strap was active when it was entered. A strap being
// disconnected, removed, forgotten or re-keyed never deletes or hides one. Nothing stored is moved:
// rows stay under the device id they were written with, and this file is how they are read and
// written without regard to that id.
//
//   - `LabMarkerUnion`: the pure rules for which stored rows are one reading.
//   - `allLabMarkers…`: reads across EVERY device id present in the table. Not a list built from the
//     registry: a registry-built list is what hid the readings under a forgotten strap.
//   - `upsertOwnerLabMarkers`, `deleteLabMarkerAndCopies`: writes that act on a reading wherever it
//     is stored. They are the in-transaction steps of `LabMarkerStore.swift` plus one projection.
//
// No Kotlin twin, by the owner's decision (stage 1 ruling R43). On Android the Lab Book still reads
// and writes one device id, so a database from the iPhone shows a subset of its readings there.

/// Pure merge rules for Lab Book rows stored under several device ids. Nothing here stores, moves or
/// deletes a row.
/// No Kotlin twin, by the owner's decision (stage 1 ruling R43).
public enum LabMarkerUnion {

    /// A reading's identity at owner scope: the store's natural key without the device id.
    public struct ReadingKey: Hashable, Sendable {
        public let markerKey: String
        public let takenAt: Int
        public let source: String

        public init(markerKey: String, takenAt: Int, source: String) {
            self.markerKey = markerKey
            self.takenAt = takenAt
            self.source = source
        }
    }

    public static func key(_ row: LabMarkerRow) -> ReadingKey {
        ReadingKey(markerKey: row.markerKey, takenAt: row.takenAt, source: row.source)
    }

    /// The same reading stored twice: equal in every column except `id`, `deviceId` and `day`.
    /// `day` is left out because it is derived from the instant and the zone of the write. Optionals
    /// compare with `==` (a nil equals only nil), so a value that is not a number equals nothing and
    /// two rows holding one are never collapsed.
    public static func isCopy(_ a: LabMarkerRow, _ b: LabMarkerRow) -> Bool {
        a.markerKey == b.markerKey && a.takenAt == b.takenAt && a.source == b.source
            && a.category == b.category && a.value == b.value && a.valueText == b.valueText
            && a.unit == b.unit && a.note == b.note && a.referenceText == b.referenceText
    }

    /// One row per distinct reading, ordered by (`takenAt`, `id`) ascending. Only rows equal in
    /// content collapse; rows that share an identity and differ are different readings and are all
    /// kept. A set of copies is represented by the active id's row when there is one, else by the
    /// row with the smallest `deviceId`, then the smallest `id`.
    public static func merged(_ rows: [LabMarkerRow], activeDeviceId: String) -> [LabMarkerRow] {
        let ordered = rows.sorted { x, y in
            if x.takenAt != y.takenAt { return x.takenAt < y.takenAt }
            let xActive = x.deviceId == activeDeviceId, yActive = y.deviceId == activeDeviceId
            if xActive != yActive { return xActive }
            if x.deviceId != y.deviceId { return x.deviceId < y.deviceId }
            return x.id < y.id
        }
        // Copies share an identity, so a row is only ever compared with the kept rows of its own.
        var keptByKey: [ReadingKey: [LabMarkerRow]] = [:]
        var kept: [LabMarkerRow] = []
        for row in ordered {
            let k = key(row)
            if let held = keptByKey[k], held.contains(where: { isCopy($0, row) }) { continue }
            keptByKey[k, default: []].append(row)
            kept.append(row)
        }
        return kept.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
    }

    /// `row` and every copy of it found in `rows`, ordered by (`deviceId`, `id`).
    public static func copies(of row: LabMarkerRow, in rows: [LabMarkerRow]) -> [LabMarkerRow] {
        rows.filter { isCopy($0, row) }
            .sorted { ($0.deviceId, $0.id) < ($1.deviceId, $1.id) }
    }

    /// Identities held by two or more rows that are not copies of each other, ordered by
    /// (`takenAt`, `markerKey`, `source`).
    public static func conflictingKeys(_ rows: [LabMarkerRow]) -> [ReadingKey] {
        var first: [ReadingKey: LabMarkerRow] = [:]
        var conflicting: Set<ReadingKey> = []
        for row in rows {
            let k = key(row)
            if let seen = first[k] {
                if !isCopy(seen, row) { conflicting.insert(k) }
            } else {
                first[k] = row
            }
        }
        return conflicting.sorted {
            ($0.takenAt, $0.markerKey, $0.source) < ($1.takenAt, $1.markerKey, $1.source)
        }
    }
}

extension WhoopStore {

    // MARK: - Reads across every device id

    /// Every stored Lab Book row, under any device id, registered or not. Ordered by
    /// (`takenAt`, `id`) ascending. Unmerged: copies and conflicting rows are all returned.
    public func allLabMarkers() async throws -> [LabMarkerRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM labMarker
                ORDER BY takenAt ASC, id ASC
                """).map(LabMarkerRow.decode)
        }
    }

    /// Every stored row of one category, under any device id. Ordered by (`takenAt`, `id`) ascending.
    public func allLabMarkers(category: String) async throws -> [LabMarkerRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM labMarker
                WHERE category = ?
                ORDER BY takenAt ASC, id ASC
                """, arguments: [category]).map(LabMarkerRow.decode)
        }
    }

    /// Every stored row of one marker, under any device id. Ordered by (`takenAt`, `id`) ascending.
    public func allLabMarkers(markerKey: String) async throws -> [LabMarkerRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM labMarker
                WHERE markerKey = ?
                ORDER BY takenAt ASC, id ASC
                """, arguments: [markerKey]).map(LabMarkerRow.decode)
        }
    }

    /// Distinct device ids that hold at least one Lab Book row, ascending. Read from the table, not
    /// from the registry.
    public func labMarkerDeviceIds() async throws -> [String] {
        try syncRead { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT deviceId FROM labMarker
                ORDER BY deviceId ASC
                """)
        }
    }

    // MARK: - Owner-scope writes

    /// Upsert readings at owner scope, then recompute every touched projection cell, in one
    /// transaction. A reading already stored at the same (`markerKey`, `takenAt`, `source`) under ANY
    /// device id is updated where it is, keeping its `id` and `deviceId`; otherwise the row is
    /// inserted as given. So re-importing a file after the active strap changed updates and does not
    /// double. Returns the number of stored rows inserted or updated.
    @discardableResult
    public func upsertOwnerLabMarkers(_ rows: [LabMarkerRow]) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        return try syncWrite { db in
            let step = try ownerUpsert(db, rows: rows)
            try reprojectCells(db, cells: step.touched)
            return step.written
        }
    }

    /// Delete one reading and every stored copy of it, under whichever device ids they sit, then
    /// recompute their projection cells, in one transaction. The list shows a set of copies once, so
    /// deleting only the listed row would let the reading reappear from its copy. A row at the same
    /// instant that differs in content is a different reading and stays. Returns the ids deleted,
    /// ascending; empty when `id` is not stored.
    @discardableResult
    public func deleteLabMarkerAndCopies(id: String) async throws -> [String] {
        try syncWrite { db in
            let step = try deleteWithCopies(db, id: id)
            try reprojectCells(db, cells: step.touched)
            return step.deleted
        }
    }
}
