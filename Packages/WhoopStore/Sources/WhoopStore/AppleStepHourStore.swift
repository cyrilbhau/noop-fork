import Foundation
import GRDB

// MARK: - v38 store: hourly Apple Health step counts
// Mirrors OuraRawStore: an idempotent ON CONFLICT upsert keyed by the natural key (deviceId, ts), and
// a range read — all GRDB work via syncWrite/syncRead. `appleDaily.steps` already answers "how many
// steps that day"; this table answers "which HOURS were recorded", so the UI can show retroactively
// when the iPhone was off/dead/left behind (e.g. mid-hike) instead of a single flattened daily total.

extension WhoopStore {

    /// Import step totals without replacing unrelated Apple Health columns. The personal iPhone
    /// activity-only reader uses this instead of a full daily upsert. Both display stores commit together.
    @discardableResult
    public func upsertAppleDailySteps(_ rows: [(day: String, steps: Int)], deviceId: String) async throws -> Int {
        try syncWrite { db in
            var changed = 0
            for row in rows {
                try db.execute(sql: """
                    INSERT INTO appleDaily (deviceId, day, steps) VALUES (?, ?, ?)
                    ON CONFLICT(deviceId, day) DO UPDATE SET steps = excluded.steps
                    """, arguments: [deviceId, row.day, row.steps])
                changed += db.changesCount
            }
            try Self.upsertMetricSeries(rows.map {
                MetricPoint(day: $0.day, key: "steps", value: Double($0.steps))
            }, deviceId: deviceId, in: db)
            return changed
        }
    }

    /// Upsert hourly Apple Health step counts. Idempotent by (deviceId, ts): re-importing the same
    /// hour overwrites its count rather than duplicating. Returns rows changed.
    @discardableResult
    public func upsertAppleStepHours(_ rows: [(ts: Int, steps: Int)], deviceId: String) async throws -> Int {
        try syncWrite { db in
            var n = 0
            for r in rows {
                try db.execute(sql: """
                    INSERT INTO appleStepHour (deviceId, ts, steps)
                    VALUES (?, ?, ?)
                    ON CONFLICT(deviceId, ts) DO UPDATE SET
                        steps = excluded.steps
                    """, arguments: [deviceId, r.ts, r.steps])
                n += db.changesCount
            }
            return n
        }
    }

    /// Hourly step counts for a device over `[fromTs, toTs]` inclusive, oldest hour first.
    public func appleStepHours(deviceId: String, fromTs: Int, toTs: Int) async throws -> [(ts: Int, steps: Int)] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, steps FROM appleStepHour
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC
                """, arguments: [deviceId, fromTs, toTs])
                .map { (ts: $0["ts"], steps: $0["steps"]) }
        }
    }
}
