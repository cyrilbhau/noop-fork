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

    /// Upsert lab-marker rows, then re-derive the projected cell of each reading written into
    /// `metricSeries` under `lab-book`. Idempotent: re-upserting the same
    /// (deviceId, markerKey, takenAt, source) updates that reading in place (UNIQUE
    /// index `idx_labMarker_natural`) and the projection reflects the new value.
    ///
    /// The daily projection rule is LATEST-per-day: the reading with the greatest
    /// `takenAt` (then the greatest `id`) for a (markerKey, day) wins, among the rows under
    /// EVERY device id — byte-identical to `LabBookProjection.project(.latest)` fed in
    /// (`takenAt`, `id`) order. Only NUMERIC readings project (a REAL-only `metricSeries`
    /// cell can't carry `valueText`). Only the cell of a reading this call wrote is re-derived
    /// (ruling A11, see `projectionTouches`).
    ///
    /// Returns the number of marker rows written/updated.
    @discardableResult
    public func upsertLabMarkers(_ rows: [LabMarkerRow]) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        return try syncWrite { db in
            var written = 0
            // Which cells need re-deriving. A cell carries no device id: the projection is computed
            // across every id (labbook-ownership.md §7.2).
            var touched: Set<LabBookDayCell> = []
            for r in rows {
                // The row this write lands on, as stored before it: the projection step needs the
                // day and value it had.
                let before = try Row.fetchOne(db, sql: """
                    SELECT * FROM labMarker
                    WHERE deviceId = ? AND markerKey = ? AND takenAt = ? AND source = ?
                    """, arguments: [r.deviceId, r.markerKey, r.takenAt, r.source]).map(LabMarkerRow.decode)
                // Upsert keyed on the natural index, NOT on the `id` PK: a re-import of the
                // "same reading" (same deviceId+markerKey+takenAt+source) must update, not
                // duplicate, even if the caller minted a fresh id. The key holds the device id, so
                // a different reading at the same instant under another id is never reached.
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
                var after = r
                after.id = before?.id ?? r.id
                touched.formUnion(try projectionTouches(db, before: before, after: after))
            }
            try reprojectCells(db, cells: touched)
            return written
        }
    }

    /// In one transaction: delete the rows with these ids and every copy of each, upsert `rows` by
    /// the owner-scope rule, then re-project every touched (markerKey, day) cell over all device ids.
    /// An id that is not stored is skipped. Returns the number of stored rows inserted or updated by
    /// the upsert. If anything throws, nothing is changed.
    ///
    /// Stage 4 (body record, docs/personal/superapp/specs/stage-4.md §9.2): a scan's rows must appear,
    /// move and disappear together, so an edit or a delete is this one call. It is composed only of
    /// the ownership steps `deleteWithCopies`, `ownerUpsert` and `reprojectCells` and writes no SQL of
    /// its own. The deletes run first, so the upserts are evaluated against the table they left.
    /// No Kotlin twin, by ruling R43 of the stage 1 specification.
    @discardableResult
    public func replaceLabMarkers(deleteIds: [String], upsert rows: [LabMarkerRow]) async throws -> Int {
        guard !deleteIds.isEmpty || !rows.isEmpty else { return 0 }
        return try syncWrite { db in
            var touched: Set<LabBookDayCell> = []
            for id in deleteIds {
                touched.formUnion(try deleteWithCopies(db, id: id).touched)
            }
            let step = try ownerUpsert(db, rows: rows)
            touched.formUnion(step.touched)
            try reprojectCells(db, cells: touched)
            return step.written
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

    /// Delete one reading by `id`. If the projected `metricSeries` day held this reading's value it
    /// is re-derived from the remaining same-day readings, and removed when none is numeric. A cell
    /// that held another value is left as stored (ruling A11). Returns true if a row was deleted.
    @discardableResult
    public func deleteLabMarker(id: String) async throws -> Bool {
        try syncWrite { db in
            // Capture the cell so we can re-project after the delete.
            guard let row = try Row.fetchOne(db, sql:
                "SELECT * FROM labMarker WHERE id = ?", arguments: [id]).map(LabMarkerRow.decode) else {
                return false
            }
            try db.execute(sql: "DELETE FROM labMarker WHERE id = ?", arguments: [id])
            try reprojectCells(db, cells: try projectionTouches(db, before: row, after: nil))
            return true
        }
    }

    // MARK: - Owner-scope write steps (module-internal)
    //
    // Personal fork, stage 1 ruling R42 (docs/personal/superapp/specs/labbook-ownership.md §6.1,
    // §7.2, §7.4). A Lab Book reading is the owner's, whichever strap was active when it was entered,
    // so "this same reading again" is decided WITHOUT the device id.
    //
    // The steps below run inside a transaction the caller already holds:
    //   - none of them opens a transaction, and none calls another write step;
    //   - `ownerUpsert` and `deleteWithCopies` never write `metricSeries`, they only report `touched`;
    //   - `reprojectCells` runs once, last, over the union of every `touched` set the transaction
    //     collected, so each cell is computed from the rows as they stand after every write.
    //
    // Rulings A10 and A11 (docs/personal/superapp/specs/RULINGS-ADDENDUM.md) bind them:
    //   - A10: two rows at one identity that differ in content are two readings. A write selects
    //     its rows by `id`: the row the owner acted on and that row's copies, never a conflicting row.
    //   - A11: the projection is never a reason to lose information. Only the cell of a reading
    //     being written is re-derived, and a cell is erased only when it still holds the value of a
    //     reading the same transaction removed.
    //
    // No Kotlin twin, by the owner's decision (stage 1 ruling R43): Android's Lab Book still upserts,
    // deletes and projects per device id.

    /// One projected `lab-book` cell to re-derive. It carries no device id: the projection is
    /// computed across every id that holds a reading of the marker on the day.
    ///
    /// `vacated` is a number the transaction took out of the cell (a reading deleted, moved to
    /// another day, or given another value). `reprojectCells` erases a cell only while it still holds
    /// such a number, so a cell no stored row backs is never erased (ruling A11).
    struct LabBookDayCell: Hashable {
        let markerKey: String
        let day: String
        var vacated: Double? = nil
    }

    /// The cells one written reading asks `reprojectCells` to re-derive (ruling A11). `before` is
    /// the stored row as it was (nil for an insert), `after` the row as now stored (nil for a
    /// delete). Call it after the row is written; it reads the still unprojected `metricSeries`.
    ///
    /// - Day and value both as they were: nothing, unless the reading's cell is missing.
    /// - A number that left a cell (delete, another day, another value, or no longer a number): the
    ///   cell, when it is missing or holds that number. A cell holding anything else did not project
    ///   this reading and is left as stored. The number has NOT left a cell that holds it while
    ///   another stored reading of the marker and day still holds it (ruling A14): that cell is left
    ///   as stored too, so removing a reading that merely shares the number of the projected one
    ///   never flips a conflict day's cell to the other reading. The exception is the reading that
    ///   was the latest of its marker and day: a cell holding its number projected THAT reading, so
    ///   the cell is re-derived and follows the reading that is the latest now.
    /// - A number that arrived in a cell: the cell, when it is missing or this reading is now the
    ///   latest of its marker and day (§7.2). An earlier reading of the day does not disturb the
    ///   cell, so a cell holding one of two conflicting readings keeps the value already there.
    func projectionTouches(_ db: Database, before: LabMarkerRow?, after: LabMarkerRow?) throws -> Set<LabBookDayCell> {
        func stored(_ markerKey: String, _ day: String) throws -> Double? {
            try Double.fetchOne(db, sql: """
                SELECT value FROM metricSeries WHERE deviceId = ? AND day = ? AND key = ?
                """, arguments: [WhoopStore.labBookSourceId, day, markerKey])
        }
        var touched: Set<LabBookDayCell> = []
        if let before, let after, before.day == after.day, before.value == after.value {
            if after.value != nil, try stored(after.markerKey, after.day) == nil {
                touched.insert(LabBookDayCell(markerKey: after.markerKey, day: after.day))
            }
            return touched
        }
        if let before, let gone = before.value {
            let have = try stored(before.markerKey, before.day)
            // Both read after the write: the reading itself no longer holds `gone` on that day.
            // Ruling A14: another reading of the marker and day still holds the number.
            let stillHeld = try have == gone && Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM labMarker WHERE markerKey = ? AND day = ? AND value = ?)
                """, arguments: [before.markerKey, before.day, gone]) == true
            // No other numeric reading of the marker and day came after this one (§7.2 order), so
            // this was the reading a cell holding its number projected.
            let wasLatest = try stillHeld && Bool.fetchOne(db, sql: """
                SELECT NOT EXISTS(
                    SELECT 1 FROM labMarker
                    WHERE markerKey = ? AND day = ? AND value IS NOT NULL AND id <> ?
                      AND (takenAt > ? OR (takenAt = ? AND id > ?)))
                """, arguments: [before.markerKey, before.day, before.id,
                                 before.takenAt, before.takenAt, before.id]) == true
            if have == nil || (have == gone && (!stillHeld || wasLatest)) {
                touched.insert(LabBookDayCell(markerKey: before.markerKey, day: before.day, vacated: gone))
            }
        }
        if let after, after.value != nil {
            var derive = try stored(after.markerKey, after.day) == nil
            if !derive {
                let latest = try String.fetchOne(db, sql: """
                    SELECT id FROM labMarker
                    WHERE markerKey = ? AND day = ? AND value IS NOT NULL
                    ORDER BY takenAt DESC, id DESC
                    LIMIT 1
                    """, arguments: [after.markerKey, after.day])
                derive = latest == after.id
            }
            if derive { touched.insert(LabBookDayCell(markerKey: after.markerKey, day: after.day)) }
        }
        return touched
    }

    /// Owner-scope upsert, without the projection step (ruling A10). For each incoming row, in list
    /// order, with the stored rows at its (`markerKey`, `takenAt`, `source`) under ANY device id:
    ///
    /// - None: the row is inserted as given.
    /// - Otherwise the row it LANDS ON is the stored row with the incoming `id` (an edit names its
    ///   row), else the one under the incoming `deviceId` (a save or an import under the active id),
    ///   else, when every stored row at the identity is a copy of the others and so one reading, that
    ///   reading. The landed row and its copies (`LabMarkerUnion.isCopy`) take the incoming
    ///   `category`, `value`, `valueText`, `unit`, `note` and `referenceText`, each selected by its
    ///   own `id` and keeping its `id` and `deviceId`. The landed row takes the incoming `day`; so
    ///   does a copy stored under the same day, while a copy stored under another day keeps it
    ///   (ruling A11: both days keep their cell).
    /// - The identity holds different readings and none is under the incoming `id` or `deviceId`:
    ///   no stored row is the owner's target, so none is changed. An incoming row equal to one of
    ///   them writes nothing; any other is inserted as given, as one more reading at that instant.
    ///
    /// A stored row that differs in content from the landed row is never updated, no row is moved to
    /// another device id and none is deleted.
    ///
    /// `written` is the number of stored rows inserted or updated (a stored row that already held the
    /// incoming content counts as updated). `touched` holds the cells to re-derive
    /// (`projectionTouches`).
    func ownerUpsert(_ db: Database, rows: [LabMarkerRow]) throws -> (written: Int, touched: Set<LabBookDayCell>) {
        var written = 0
        var touched: Set<LabBookDayCell> = []
        for r in rows {
            // Read inside the loop so a second incoming row with the same identity sees the first.
            let stored = try Row.fetchAll(db, sql: """
                SELECT * FROM labMarker
                WHERE markerKey = ? AND takenAt = ? AND source = ?
                ORDER BY deviceId ASC, id ASC
                """, arguments: [r.markerKey, r.takenAt, r.source]).map(LabMarkerRow.decode)
            let oneReading = stored.dropFirst().allSatisfy { LabMarkerUnion.isCopy(stored[0], $0) }
            let landed = stored.first { $0.id == r.id }
                ?? stored.first { $0.deviceId == r.deviceId }
                ?? (oneReading ? stored.first : nil)

            guard let landed else {
                // No stored row, or different readings none of which the owner acted on.
                if stored.contains(where: { LabMarkerUnion.isCopy($0, r) }) { continue }
                try db.execute(sql: """
                    INSERT INTO labMarker
                        (id, deviceId, markerKey, category, day, takenAt,
                         value, valueText, unit, source, note, referenceText)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        r.id, r.deviceId, r.markerKey, r.category, r.day, r.takenAt,
                        r.value, r.valueText, r.unit, r.source, r.note, r.referenceText,
                    ])
                written += 1
                touched.formUnion(try projectionTouches(db, before: nil, after: r))
                continue
            }
            // The landed row is always written, whatever `isCopy` says of a row compared with itself.
            for target in stored where target.id == landed.id || LabMarkerUnion.isCopy(landed, target) {
                var after = r
                after.id = target.id
                after.deviceId = target.deviceId
                after.day = target.day == landed.day ? r.day : target.day
                try db.execute(sql: """
                    UPDATE labMarker SET
                        category = ?, day = ?, value = ?, valueText = ?,
                        unit = ?, note = ?, referenceText = ?
                    WHERE id = ?
                    """, arguments: [
                        after.category, after.day, after.value, after.valueText, after.unit, after.note,
                        after.referenceText, target.id,
                    ])
                written += 1
                touched.formUnion(try projectionTouches(db, before: target, after: after))
            }
        }
        return (written, touched)
    }

    /// Delete of a row and its copies, without the projection step. Loads the row named by `id`, then
    /// every stored row at its (`markerKey`, `takenAt`, `source`) under any device id, and deletes
    /// those for which `LabMarkerUnion.isCopy` holds, the row itself included. A row at the same
    /// identity that differs in content is a different reading and is NOT deleted (ruling A10).
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
            touched.formUnion(try projectionTouches(db, before: copy, after: nil))
        }
        return (doomed.map(\.id).sorted(), touched)
    }

    /// Re-derive the `metricSeries` projection (under `lab-book`) for each touched cell from the
    /// CURRENT `labMarker` rows under EVERY device id. The reading with the greatest `takenAt`, then
    /// the greatest `id`, among the numeric readings of the marker and day wins. That is also the
    /// reading the Lab Book history, newest first, shows first.
    ///
    /// With no numeric reading left for a cell, the projected day is deleted ONLY while it still
    /// holds a number the transaction took out of that cell (`LabBookDayCell.vacated`), so a removed
    /// last reading leaves no stale value behind and a cell no stored row backs is never erased
    /// (ruling A11): it may be the last trace of a reading an earlier strap delete removed.
    ///
    /// It takes no device id on purpose. Choosing within one id let a strap's older reading replace
    /// a later one entered under another id, and let the delete of one id's last reading of a day
    /// drop a cell another id still backed.
    func reprojectCells(_ db: Database, cells: Set<LabBookDayCell>) throws {
        var vacatedByCell: [LabBookDayCell: [Double]] = [:]
        for cell in cells {
            let key = LabBookDayCell(markerKey: cell.markerKey, day: cell.day)
            vacatedByCell[key, default: []] += cell.vacated.map { [$0] } ?? []
        }
        for (cell, vacated) in vacatedByCell {
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
                // No numeric reading remains: drop the projected day while it holds a removed
                // reading's number, and only then.
                for gone in vacated {
                    try db.execute(sql: """
                        DELETE FROM metricSeries
                        WHERE deviceId = ? AND day = ? AND key = ? AND value = ?
                        """, arguments: [WhoopStore.labBookSourceId, cell.day, cell.markerKey, gone])
                }
            }
        }
    }

    // MARK: - Projection repair

    /// Fill in the `lab-book` cells that are missing, WITHOUT replacing or removing any stored cell
    /// and without touching a `labMarker` row (ruling A11: the projection is never a reason to lose
    /// information). One write transaction; idempotent (a second run reports `inserted == 0`).
    ///
    /// For each marker and day that has a numeric reading under any device id:
    /// - no cell stored: it is inserted with the day's latest reading (greatest `takenAt`, then
    ///   greatest `id`, the reading the Lab Book history shows first);
    /// - a cell holding the value of ANY stored reading of that marker and day: left as stored. It
    ///   is a number the owner entered, and where two ids hold different readings the repair cannot
    ///   know which was entered last;
    /// - a cell holding a value no stored reading holds: left as stored. It may be the last trace
    ///   of a reading an earlier strap delete or adoption removed.
    /// A stored cell whose marker and day have no numeric reading at all is left as stored too.
    /// Where copies of one reading are stored under different days, each day keeps its cell.
    ///
    /// Not a migration: it writes derived cells only and must also run on a database restored
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

            // The only statement here that writes is the INSERT of a missing cell.
            var inserted = 0, unchanged = 0, unbackedKept = 0
            for (cell, want) in expected {
                guard let have = stored[cell] else {
                    try db.execute(sql: """
                        INSERT INTO metricSeries (deviceId, day, key, value) VALUES (?, ?, ?, ?)
                        """, arguments: [WhoopStore.labBookSourceId, cell.day, cell.markerKey, want.value])
                    inserted += 1
                    continue
                }
                if want.held.contains(have) {
                    unchanged += 1
                } else {
                    unbackedKept += 1
                }
            }
            // Stored cells no numeric reading backs at all: kept, counted, never deleted.
            unbackedKept += stored.keys.filter { expected[$0] == nil }.count

            return LabBookProjectionRepair(inserted: inserted, updated: 0,
                                           unchanged: unchanged, unbackedKept: unbackedKept)
        }
    }
}

/// What one run of `WhoopStore.repairLabBookProjection()` did, as counts only.
/// No Kotlin twin, by the owner's decision (stage 1 ruling R43).
public struct LabBookProjectionRepair: Equatable, Sendable {
    /// Cells that were missing and were inserted.
    public let inserted: Int
    /// Always 0 since ruling A11: the repair replaces no stored cell. Kept so the log line and
    /// callers that read the four counts are unchanged.
    public let updated: Int
    /// Cells left as stored that hold the value of a stored reading of their marker and day.
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
