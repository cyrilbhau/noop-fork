import Foundation
import GRDB

// MARK: - v17 store: Lab Book markers
//
// LabMarkerStore.swift — GRDB CRUD over the `labMarker` table (migration v17), the
// source-of-truth for the Health Records "Lab Book" pillar
// (spec 2026-06-19-v5-health-records-design.md §"New").
//
// The book is `labMarker` (one row per dated reading the user entered themselves);
// the daily `metricSeries` projection under source id `lab-book` is HOW the book talks
// to the rest of the app (Compare / Explore / correlation / Coach see it unchanged).
// On every write this store ALSO upserts that daily projection, exactly as the spec
// requires, so the two never drift.
//
// Mirrors the established `MetricSeriesStore` / `DeviceRegistryStore` idiom precisely:
// a plain Codable row struct, raw `Row` fetch + manual decode, idempotent upserts keyed
// by the natural key, all GRDB work via the actor's `syncWrite` / `syncRead` helpers.
//
// NON-CLINICAL: stores ONLY user-entered values + an OPTIONAL user-entered
// `referenceText` (their own report's range, verbatim). No reference-range tables, no
// normality judgement, ever.

/// One stored Lab Book reading. Natural key (deviceId, markerKey, takenAt, source) is
/// enforced by a UNIQUE index so re-importing the same reading is idempotent; `id` is a
/// stable client-generated identifier for edit/delete-by-id and backup round-trips.
public struct LabMarkerRow: Equatable, Codable, Sendable {
    public var id: String
    public var deviceId: String
    public var markerKey: String
    public var category: String
    /// Pre-derived yyyy-MM-dd day key (the projection key for this reading).
    public var day: String
    /// Precise instant the reading was taken (epoch seconds).
    public var takenAt: Int
    /// Numeric reading. Nil for a qualitative entry whose meaning is in `valueText`.
    public var value: Double?
    public var valueText: String?
    public var unit: String
    public var source: String
    public var note: String?
    /// User-entered reference range, shown back verbatim. NOOP ships none.
    public var referenceText: String?

    public init(
        id: String,
        deviceId: String,
        markerKey: String,
        category: String,
        day: String,
        takenAt: Int,
        value: Double?,
        valueText: String?,
        unit: String,
        source: String,
        note: String?,
        referenceText: String?
    ) {
        self.id = id
        self.deviceId = deviceId
        self.markerKey = markerKey
        self.category = category
        self.day = day
        self.takenAt = takenAt
        self.value = value
        self.valueText = valueText
        self.unit = unit
        self.source = source
        self.note = note
        self.referenceText = referenceText
    }

    /// Decode a GRDB row (raw-Row idiom, matching DeviceRegistryStore.decode).
    static func decode(_ row: Row) -> LabMarkerRow {
        LabMarkerRow(
            id: row["id"],
            deviceId: row["deviceId"],
            markerKey: row["markerKey"],
            category: row["category"],
            day: row["day"],
            takenAt: row["takenAt"],
            value: row["value"],
            valueText: row["valueText"],
            unit: row["unit"],
            source: row["source"],
            note: row["note"],
            referenceText: row["referenceText"]
        )
    }
}

extension WhoopStore {

    /// The constant device-id the daily marker projection is written under, so Compare/
    /// Explore/Coach see markers as a single-source series (spec §"Cross-platform plan").
    public static let labBookSourceId = "lab-book"

    // MARK: - Upsert (idempotent by natural key) + project to metricSeries

    /// Upsert lab-marker rows, then re-project the affected (markerKey, day) cells into
    /// `metricSeries` under `lab-book`. Idempotent: re-upserting the same
    /// (deviceId, markerKey, takenAt, source) updates that reading in place (UNIQUE
    /// index `idx_labMarker_natural`) and the projection reflects the new value.
    ///
    /// The daily projection rule is LATEST-per-day: the reading with the greatest
    /// `takenAt` (then the greatest `id`) for a (markerKey, day) wins, among the rows under
    /// EVERY device id — byte-identical to `LabBookProjection.project(.latest)` fed in
    /// (`takenAt`, `id`) order. Only NUMERIC readings project (a REAL-only `metricSeries`
    /// cell can't carry `valueText`).
    ///
    /// Returns the number of marker rows written/updated.
    @discardableResult
    public func upsertLabMarkers(_ rows: [LabMarkerRow]) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        return try syncWrite { db in
            var written = 0
            // Track which (markerKey, day) cells need re-projecting. A cell carries no device id:
            // the projection is computed across every id (labbook-ownership.md §7.2).
            var touched: Set<LabBookDayCell> = []
            for r in rows {
                // Upsert keyed on the natural index, NOT on the `id` PK: a re-import of the
                // "same reading" (same deviceId+markerKey+takenAt+source) must update, not
                // duplicate, even if the caller minted a fresh id.
                try db.execute(sql: """
                    INSERT INTO labMarker
                        (id, deviceId, markerKey, category, day, takenAt,
                         value, valueText, unit, source, note, referenceText)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(deviceId, markerKey, takenAt, source) DO UPDATE SET
                        category = excluded.category,
                        day = excluded.day,
                        value = excluded.value,
                        valueText = excluded.valueText,
                        unit = excluded.unit,
                        note = excluded.note,
                        referenceText = excluded.referenceText
                    """, arguments: [
                        r.id, r.deviceId, r.markerKey, r.category, r.day, r.takenAt,
                        r.value, r.valueText, r.unit, r.source, r.note, r.referenceText,
                    ])
                written += db.changesCount
                touched.insert(LabBookDayCell(markerKey: r.markerKey, day: r.day))
            }
            try reprojectCells(db, cells: touched)
            return written
        }
    }

    // MARK: - Reads

    /// All readings in a category, oldest first (by takenAt). Served by
    /// `idx_labMarker_device_category` + the takenAt index.
    public func labMarkers(deviceId: String, category: String) async throws -> [LabMarkerRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM labMarker
                WHERE deviceId = ? AND category = ?
                ORDER BY takenAt ASC
                """, arguments: [deviceId, category]).map(LabMarkerRow.decode)
        }
    }

    /// Full reading history for one marker, oldest first (by takenAt). Served
    /// index-only by `idx_labMarker_device_marker_takenAt`.
    public func labMarkers(deviceId: String, markerKey: String) async throws -> [LabMarkerRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM labMarker
                WHERE deviceId = ? AND markerKey = ?
                ORDER BY takenAt ASC
                """, arguments: [deviceId, markerKey]).map(LabMarkerRow.decode)
        }
    }

    /// Distinct marker keys present for a device, sorted ascending.
    public func markerKeysPresent(deviceId: String) async throws -> [String] {
        try syncRead { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT markerKey FROM labMarker
                WHERE deviceId = ?
                ORDER BY markerKey ASC
                """, arguments: [deviceId])
        }
    }

    // MARK: - Delete (removes the row AND its now-orphaned projected day)

    /// Delete one reading by `id`. If that was the last numeric reading for its
    /// (markerKey, day) cell, the projected `metricSeries` day is removed too; otherwise
    /// the projection is recomputed from the remaining same-day readings. Returns true if
    /// a row was deleted.
    @discardableResult
    public func deleteLabMarker(id: String) async throws -> Bool {
        try syncWrite { db in
            // Capture the cell so we can re-project after the delete.
            guard let row = try Row.fetchOne(db, sql:
                "SELECT * FROM labMarker WHERE id = ?", arguments: [id]).map(LabMarkerRow.decode) else {
                return false
            }
            try db.execute(sql: "DELETE FROM labMarker WHERE id = ?", arguments: [id])
            try reprojectCells(db, cells: [LabBookDayCell(markerKey: row.markerKey, day: row.day)])
            return true
        }
    }

    // MARK: - Owner-scope write steps (module-internal)
    //
    // Personal fork, stage 1 ruling R42 (docs/personal/superapp/specs/labbook-ownership.md §6.1,
    // §7.2, §7.4). A Lab Book reading is the owner's, whichever strap was active when it was entered,
    // so "this same reading again" is decided WITHOUT the device id.
    //
    // The three steps below run inside a transaction the caller already holds:
    //   - none of them opens a transaction, and none calls another;
    //   - `ownerUpsert` and `deleteWithCopies` never write `metricSeries`, they only report `touched`;
    //   - `reprojectCells` runs once, last, over the union of every `touched` set the transaction
    //     collected, so each cell is computed from the rows as they stand after every write.
    //
    // No Kotlin twin, by the owner's decision (stage 1 ruling R43): Android's Lab Book still upserts,
    // deletes and projects per device id.

    /// One projected `lab-book` cell. It carries no device id: the projection is computed across
    /// every id that holds a reading of the marker on the day.
    struct LabBookDayCell: Hashable {
        let markerKey: String
        let day: String
    }

    /// Owner-scope upsert, without the projection step. For each incoming row, in list order: with no
    /// stored row at its (`markerKey`, `takenAt`, `source`) under ANY device id the row is inserted as
    /// given; otherwise every stored row at that identity is updated in place, taking the incoming
    /// `category`, `day`, `value`, `valueText`, `unit`, `note` and `referenceText` and keeping its own
    /// `id` and `deviceId`. No row is ever moved to another device id and none is deleted.
    ///
    /// `written` is the number of stored rows inserted or updated (a stored row that already held the
    /// incoming content counts as updated). `touched` holds every cell to recompute, the old day of
    /// an updated row included.
    func ownerUpsert(_ db: Database, rows: [LabMarkerRow]) throws -> (written: Int, touched: Set<LabBookDayCell>) {
        var written = 0
        var touched: Set<LabBookDayCell> = []
        for r in rows {
            // The days the reading is stored under today, one per stored row at the identity. Read
            // inside the loop so a second incoming row with the same identity sees the first one.
            let storedDays = try String.fetchAll(db, sql: """
                SELECT day FROM labMarker
                WHERE markerKey = ? AND takenAt = ? AND source = ?
                """, arguments: [r.markerKey, r.takenAt, r.source])
            if storedDays.isEmpty {
                try db.execute(sql: """
                    INSERT INTO labMarker
                        (id, deviceId, markerKey, category, day, takenAt,
                         value, valueText, unit, source, note, referenceText)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        r.id, r.deviceId, r.markerKey, r.category, r.day, r.takenAt,
                        r.value, r.valueText, r.unit, r.source, r.note, r.referenceText,
                    ])
            } else {
                try db.execute(sql: """
                    UPDATE labMarker SET
                        category = ?, day = ?, value = ?, valueText = ?,
                        unit = ?, note = ?, referenceText = ?
                    WHERE markerKey = ? AND takenAt = ? AND source = ?
                    """, arguments: [
                        r.category, r.day, r.value, r.valueText, r.unit, r.note, r.referenceText,
                        r.markerKey, r.takenAt, r.source,
                    ])
                for day in storedDays {
                    touched.insert(LabBookDayCell(markerKey: r.markerKey, day: day))
                }
            }
            written += db.changesCount
            touched.insert(LabBookDayCell(markerKey: r.markerKey, day: r.day))
        }
        return (written, touched)
    }

    /// Delete of a row and its copies, without the projection step. Loads the row named by `id`, then
    /// every stored row at its (`markerKey`, `takenAt`, `source`) under any device id, and deletes
    /// those for which `LabMarkerUnion.isCopy` holds, the row itself included. A row at the same
    /// identity that differs in content is a different reading and is NOT deleted.
    ///
    /// Each row is removed by its own `id`: this and `deleteLabMarker(id:)` are the only statements
    /// in the store that delete a `labMarker` row, and neither selects by device id.
    ///
    /// `deleted` is ascending. An `id` that is not stored (never was, or already removed as a copy
    /// earlier in the same transaction) returns an empty `deleted` and an empty `touched`; it is not
    /// an error.
    func deleteWithCopies(_ db: Database, id: String) throws -> (deleted: [String], touched: Set<LabBookDayCell>) {
        guard let row = try Row.fetchOne(db, sql:
            "SELECT * FROM labMarker WHERE id = ?", arguments: [id]).map(LabMarkerRow.decode) else {
            return ([], [])
        }
        let sameIdentity = try Row.fetchAll(db, sql: """
            SELECT * FROM labMarker
            WHERE markerKey = ? AND takenAt = ? AND source = ?
            """, arguments: [row.markerKey, row.takenAt, row.source]).map(LabMarkerRow.decode)
        // The named row is always removed, whatever `isCopy` says of a row compared with itself.
        let doomed = sameIdentity.filter { $0.id == row.id || LabMarkerUnion.isCopy(row, $0) }
        var touched: Set<LabBookDayCell> = []
        for copy in doomed {
            try db.execute(sql: "DELETE FROM labMarker WHERE id = ?", arguments: [copy.id])
            touched.insert(LabBookDayCell(markerKey: copy.markerKey, day: copy.day))
        }
        return (doomed.map(\.id).sorted(), touched)
    }

    /// Recompute the `metricSeries` projection (under `lab-book`) for each touched cell
    /// from the CURRENT `labMarker` rows under EVERY device id. The reading with the greatest
    /// `takenAt`, then the greatest `id`, among the numeric readings of the marker and day wins; if
    /// no numeric reading remains for a cell under any id, its projected day is deleted (so a
    /// removed/last reading never leaves a stale projected value behind).
    ///
    /// It takes no device id on purpose. Choosing within one id let a strap's older reading replace
    /// a later one entered under another id, and let the delete of one id's last reading of a day
    /// drop a cell another id still backed.
    func reprojectCells(_ db: Database, cells: Set<LabBookDayCell>) throws {
        for cell in cells {
            // Latest NUMERIC reading for this (markerKey, day) under any device id: greatest takenAt,
            // then greatest id, with a non-null value. Matches LabBookProjection.project(.latest) on
            // numeric rows fed in (takenAt, id) order, and the body-measurement resolver's same-day rule.
            let latest = try Double.fetchOne(db, sql: """
                SELECT value FROM labMarker
                WHERE markerKey = ? AND day = ? AND value IS NOT NULL
                ORDER BY takenAt DESC, id DESC
                LIMIT 1
                """, arguments: [cell.markerKey, cell.day])

            if let v = latest {
                try db.execute(sql: """
                    INSERT INTO metricSeries (deviceId, day, key, value)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(deviceId, day, key) DO UPDATE SET value = excluded.value
                    """, arguments: [WhoopStore.labBookSourceId, cell.day, cell.markerKey, v])
            } else {
                // No numeric reading remains for this cell → drop the projected day.
                try db.execute(sql: """
                    DELETE FROM metricSeries
                    WHERE deviceId = ? AND day = ? AND key = ?
                    """, arguments: [WhoopStore.labBookSourceId, cell.day, cell.markerKey])
            }
        }
    }

    // MARK: - Projection repair

    /// Bring the stored `lab-book` cells into line with the all-id projection rule, WITHOUT removing
    /// any cell and without touching a `labMarker` row. One write transaction; idempotent (a second
    /// run reports `inserted == 0` and `updated == 0`).
    ///
    /// For each cell the rule expects (the latest numeric reading of a marker and day across every
    /// device id): a missing cell is inserted; an equal one is left; a different one is replaced ONLY
    /// when the stored value is the value of some existing reading of that marker and day, that is
    /// when it is provably the wrong one of the day's readings. A stored cell whose value no existing
    /// reading holds, or whose marker and day have no numeric reading at all, is left exactly as
    /// stored: it may be the last trace of a reading an earlier strap delete or adoption removed.
    ///
    /// Not a migration: it rewrites derived cells only and must also run on a database restored
    /// later, so the repository runs it once after each store open.
    /// No Kotlin twin, by the owner's decision (stage 1 ruling R43).
    @discardableResult
    public func repairLabBookProjection() async throws -> LabBookProjectionRepair {
        try syncWrite { db in
            struct Expected {
                var value: Double
                var held: Set<Double>
            }
            // Fold in (takenAt, id) order: the last numeric row of a cell is the projected one.
            var expected: [LabBookDayCell: Expected] = [:]
            let numeric = try Row.fetchAll(db, sql: """
                SELECT markerKey, day, value FROM labMarker
                WHERE value IS NOT NULL
                ORDER BY takenAt ASC, id ASC
                """)
            for row in numeric {
                let cell = LabBookDayCell(markerKey: row["markerKey"], day: row["day"])
                let value: Double = row["value"]
                expected[cell, default: Expected(value: value, held: [])].value = value
                expected[cell]?.held.insert(value)
            }

            var stored: [LabBookDayCell: Double] = [:]
            let series = try Row.fetchAll(db, sql: """
                SELECT day, key, value FROM metricSeries WHERE deviceId = ?
                """, arguments: [WhoopStore.labBookSourceId])
            for row in series {
                stored[LabBookDayCell(markerKey: row["key"], day: row["day"])] = row["value"]
            }

            var inserted = 0, updated = 0, unchanged = 0, unbackedKept = 0
            for (cell, want) in expected {
                guard let have = stored[cell] else {
                    try db.execute(sql: """
                        INSERT INTO metricSeries (deviceId, day, key, value) VALUES (?, ?, ?, ?)
                        """, arguments: [WhoopStore.labBookSourceId, cell.day, cell.markerKey, want.value])
                    inserted += 1
                    continue
                }
                if have == want.value {
                    unchanged += 1
                } else if want.held.contains(have) {
                    try db.execute(sql: """
                        UPDATE metricSeries SET value = ?
                        WHERE deviceId = ? AND day = ? AND key = ?
                        """, arguments: [want.value, WhoopStore.labBookSourceId, cell.day, cell.markerKey])
                    updated += 1
                } else {
                    unbackedKept += 1
                }
            }
            // Stored cells no numeric reading backs at all: kept, counted, never deleted.
            unbackedKept += stored.keys.filter { expected[$0] == nil }.count

            return LabBookProjectionRepair(inserted: inserted, updated: updated,
                                           unchanged: unchanged, unbackedKept: unbackedKept)
        }
    }
}

/// What one run of `WhoopStore.repairLabBookProjection()` did, as counts only.
/// No Kotlin twin, by the owner's decision (stage 1 ruling R43).
public struct LabBookProjectionRepair: Equatable, Sendable {
    /// Cells that were missing and were inserted.
    public let inserted: Int
    /// Cells that held another of the day's readings and were replaced by the correct value.
    public let updated: Int
    /// Cells that were already correct.
    public let unchanged: Int
    /// Cells left exactly as stored because no existing reading holds their value.
    public let unbackedKept: Int

    public init(inserted: Int, updated: Int, unchanged: Int, unbackedKept: Int) {
        self.inserted = inserted
        self.updated = updated
        self.unchanged = unchanged
        self.unbackedKept = unbackedKept
    }
}
