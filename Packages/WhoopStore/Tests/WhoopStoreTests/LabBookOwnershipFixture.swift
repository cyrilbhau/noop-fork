import Foundation
import GRDB
import XCTest
@testable import WhoopStore

// API ASSUMED BY THESE TESTS
//
// This file is the shared fixture of the Lab Book ownership tests (specification
// docs/personal/superapp/specs/labbook-ownership.md §13). It calls NO declaration the change adds.
// Everything it uses exists today:
//
//   LabMarkerRow.init(id:deviceId:markerKey:category:day:takenAt:value:valueText:unit:source:note:referenceText:)
//   static func LabMarkerRow.decode(_ row: Row) -> LabMarkerRow                    (module-internal)
//   static func WhoopStore.inMemory() async throws -> WhoopStore
//   nonisolated var WhoopStore.registryWriter: any DatabaseWriter
//   static let WhoopStore.labBookSourceId: String                                   ("lab-book")
//   DeviceRegistryStore.init(dbQueue:), add(_:), setActive(_:)
//   PairedDevice.init(id:brand:model:nickname:peripheralId:sourceKind:capabilities:status:addedAt:lastSeenAt:)
//
// The fixture writes rows and projected cells with raw SQL on purpose. Seeding through
// `upsertLabMarkers` would make every expectation depend on the projection rule the change rewrites,
// and an upgrade is by definition a table the new build did not write.
//
// Synthetic values only: the one "Fixture Person" of stage 1 §13, spread over the device ids of
// labbook-ownership.md §13.

enum LabBookOwnershipFixture {

    // MARK: - Device ids (§13)

    /// A: registered, paired, brand WHOOP. The row every fresh store is seeded with.
    static let a = "my-whoop"
    /// B: registered, archived, brand WHOOP.
    static let b = "whoop-FIXTURE-OLD"
    /// C: no registry row.
    static let c = "whoop-FIXTURE-GONE"
    /// D: registered, paired, brand Oura.
    static let d = "oura-FIXTURE-RING"
    /// N: registered, active, brand WHOOP.
    static let n = "whoop-FIXTURE-NEW"
    /// Not in §13: the serial id the adoption tests re-point N onto. §13 names no serial id.
    static let serial = "whoop-FIXTURE-SERIAL"

    // MARK: - Instants (§13, epoch seconds, UTC)

    static let t1 = 1_925_622_000    // 2031-01-08 07:00
    static let t2 = 1_926_226_800    // 2031-01-15 07:00
    static let t3a = 1_926_828_000   // 2031-01-22 06:00, one hour before t3
    static let t3 = 1_926_831_600    // 2031-01-22 07:00
    static let t4 = 1_927_436_400    // 2031-01-29 07:00

    static let day1 = "2031-01-08"
    static let day2 = "2031-01-15"
    static let day3 = "2031-01-22"
    static let day4 = "2031-01-29"

    // MARK: - Rows (§13)

    static func row(
        id: String, deviceId: String, markerKey: String, category: String, day: String, takenAt: Int,
        value: Double?, valueText: String? = nil, unit: String, source: String = "manual",
        note: String? = nil, referenceText: String? = nil
    ) -> LabMarkerRow {
        LabMarkerRow(id: id, deviceId: deviceId, markerKey: markerKey, category: category, day: day,
                     takenAt: takenAt, value: value, valueText: valueText, unit: unit, source: source,
                     note: note, referenceText: referenceText)
    }

    static let f1 = row(id: "weight-1925622000-F0000001", deviceId: a, markerKey: "weight",
                        category: "bodyMeasurement", day: day1, takenAt: t1, value: 100.0, unit: "kg")
    static let f2 = row(id: "weight-1926226800-F0000002", deviceId: b, markerKey: "weight",
                        category: "bodyMeasurement", day: day2, takenAt: t2, value: 99.2, unit: "kg")
    static let f3 = row(id: "weight-1926831600-F0000003", deviceId: c, markerKey: "weight",
                        category: "bodyMeasurement", day: day3, takenAt: t3, value: 98.0, unit: "kg")
    static let f4 = row(id: "weight-1927436400-F0000004", deviceId: n, markerKey: "weight",
                        category: "bodyMeasurement", day: day4, takenAt: t4, value: 97.6, unit: "kg")
    static let f5 = row(id: "waist-1925622000-F0000005", deviceId: d, markerKey: "waist",
                        category: "bodyMeasurement", day: day1, takenAt: t1, value: 100.0, unit: "cm")
    static let f6 = row(id: "ldl-1926226800-F0000006", deviceId: b, markerKey: "ldl",
                        category: "bloodPanel", day: day2, takenAt: t2, value: 3.0, unit: "mmol/L",
                        source: "lab-csv", note: "fixture panel")
    static let f7 = row(id: "ldl-1926226800-F0000007", deviceId: n, markerKey: "ldl",
                        category: "bloodPanel", day: day2, takenAt: t2, value: 3.0, unit: "mmol/L",
                        source: "lab-csv", note: "fixture panel")
    static let f8 = row(id: "weight-1926831600-F0000008", deviceId: n, markerKey: "weight",
                        category: "bodyMeasurement", day: day3, takenAt: t3, value: 98.4, unit: "kg")
    static let f9 = row(id: "weight-1926828000-F0000009", deviceId: b, markerKey: "weight",
                        category: "bodyMeasurement", day: day3, takenAt: t3a, value: 98.2, unit: "kg")
    static let f10 = row(id: "fixture_note-1926226800-F0000010", deviceId: c, markerKey: "fixture_note",
                         category: "other", day: day2, takenAt: t2, value: nil, valueText: "clear",
                         unit: "text")

    /// The ten rows in table order, F1 to F10.
    static let all: [LabMarkerRow] = [f1, f2, f3, f4, f5, f6, f7, f8, f9, f10]

    /// The ten rows ordered by (`takenAt`, `id`) ascending: what `allLabMarkers()` returns.
    /// Derived by hand: at t1 "waist-…" sorts before "weight-…"; at t2 "fixture_note-…" < "ldl-…06" <
    /// "ldl-…07" < "weight-…"; then t3a, then t3 with …03 before …08, then t4.
    static let storedOrder: [LabMarkerRow] = [f5, f1, f10, f6, f7, f2, f9, f3, f8, f4]

    /// §13: `merged` over all ten with N active. F7 stands for the pair F6 and F7.
    static let mergedWithNActive: [LabMarkerRow] = [f5, f1, f10, f7, f2, f9, f3, f8, f4]

    /// Rows per device id: A holds F1; B holds F2, F6, F9; C holds F3, F10; D holds F5; N holds F4, F7, F8.
    static let countsById: [String: Int] = [a: 1, b: 3, c: 2, d: 1, n: 3]

    /// A single-id install: every reading under A. F7 and F3 are left out because the unique index
    /// (deviceId, markerKey, takenAt, source) cannot hold them beside F6 and F8 under one id.
    static let singleIdRows: [LabMarkerRow] = [f5, f1, f10, f6, f2, f9, f8, f4].map { row in
        var moved = row
        moved.deviceId = a
        return moved
    }

    // MARK: - Projected cells

    /// One `metricSeries` row.
    struct Cell: Hashable, CustomStringConvertible {
        let deviceId: String
        let key: String
        let day: String
        let value: Double

        var description: String { "\(deviceId)/\(key)/\(day)=\(value)" }
    }

    static func cell(_ key: String, _ day: String, _ value: Double) -> Cell {
        Cell(deviceId: WhoopStore.labBookSourceId, key: key, day: day, value: value)
    }

    /// §13: the six cells under `lab-book`, ordered by (key, day). No cell for `fixture_note`.
    /// The 2031-01-22 weight is 98.4: F3 and F8 share the latest instant and F8 has the greater id.
    static let cells: [Cell] = [
        cell("ldl", day2, 3.0),
        cell("waist", day1, 100.0),
        cell("weight", day1, 100.0),
        cell("weight", day2, 99.2),
        cell("weight", day3, 98.4),
        cell("weight", day4, 97.6),
    ]

    // MARK: - Stores

    /// An in-memory store holding the §13 registry and no Lab Book row: A paired, B archived, D paired
    /// (brand Oura), N active, and no row for C.
    static func emptyStoreWithRegistry() async throws -> WhoopStore {
        let store = try await WhoopStore.inMemory()
        let registry = DeviceRegistryStore(dbQueue: store.registryWriter)
        try registry.add(PairedDevice(id: b, brand: "WHOOP", model: "WHOOP 4.0", sourceKind: .liveBLE,
                                      capabilities: [.hr], status: .archived, addedAt: 2, lastSeenAt: 2))
        try registry.add(PairedDevice(id: d, brand: "Oura", model: "Oura Ring 3", sourceKind: .oura,
                                      capabilities: [.hr, .sleep], status: .paired, addedAt: 3, lastSeenAt: 3))
        try registry.add(PairedDevice(id: n, brand: "WHOOP", model: "WHOOP 4.0", sourceKind: .liveBLE,
                                      capabilities: [.hr], status: .paired, addedAt: 4, lastSeenAt: 4))
        try registry.setActive(n)
        return store
    }

    /// The §13 state: the registry, the ten rows and the six correctly projected cells, all written
    /// with raw SQL so that nothing here depends on the code under test.
    static func seededStore() async throws -> WhoopStore {
        let store = try await emptyStoreWithRegistry()
        try insertRaw(all, into: store)
        for c in cells { try setCell(c, in: store) }
        return store
    }

    // MARK: - Raw writes

    static func insertRaw(_ rows: [LabMarkerRow], into store: WhoopStore) throws {
        try insertRaw(rows, writer: store.registryWriter)
    }

    static func insertRaw(_ rows: [LabMarkerRow], writer: any DatabaseWriter) throws {
        try writer.write { db in
            for r in rows {
                try db.execute(sql: """
                    INSERT INTO labMarker
                        (id, deviceId, markerKey, category, day, takenAt,
                         value, valueText, unit, source, note, referenceText)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        r.id, r.deviceId, r.markerKey, r.category, r.day, r.takenAt,
                        r.value, r.valueText, r.unit, r.source, r.note, r.referenceText,
                    ])
            }
        }
    }

    /// Insert or replace one `metricSeries` row, under whichever device id the cell names.
    static func setCell(_ c: Cell, in store: WhoopStore) throws {
        try setCell(c, writer: store.registryWriter)
    }

    static func setCell(_ c: Cell, writer: any DatabaseWriter) throws {
        try writer.write { db in
            try db.execute(sql: """
                INSERT INTO metricSeries (deviceId, day, key, value) VALUES (?, ?, ?, ?)
                ON CONFLICT(deviceId, day, key) DO UPDATE SET value = excluded.value
                """, arguments: [c.deviceId, c.day, c.key, c.value])
        }
    }

    static func removeLabBookCell(_ key: String, _ day: String, in store: WhoopStore) throws {
        try store.registryWriter.write { db in
            try db.execute(sql: "DELETE FROM metricSeries WHERE deviceId = ? AND day = ? AND key = ?",
                           arguments: [WhoopStore.labBookSourceId, day, key])
        }
    }

    // MARK: - Raw reads

    /// Every `labMarker` row under any device id, ordered by (`takenAt`, `id`).
    static func rows(_ store: WhoopStore) throws -> [LabMarkerRow] {
        try store.registryWriter.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM labMarker ORDER BY takenAt ASC, id ASC")
                .map(LabMarkerRow.decode)
        }
    }

    /// One line per stored `labMarker` row, in rowid order, carrying the rowid, every column, the bit
    /// pattern of `value` and the difference between NULL and an empty string. Two equal dumps mean
    /// that no row was deleted, re-inserted, moved to another id or changed in any column.
    static func storageDump(_ store: WhoopStore) throws -> [String] {
        try storageDump(writer: store.registryWriter)
    }

    static func storageDump(writer: any DatabaseWriter) throws -> [String] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT rowid AS rid, * FROM labMarker ORDER BY rowid ASC").map { row in
                let r = LabMarkerRow.decode(row)
                let rid: Int64 = row["rid"]
                func text(_ s: String?) -> String { s.map { "'\($0)'" } ?? "NULL" }
                let bits = r.value.map { String($0.bitPattern, radix: 16) } ?? "NULL"
                return [
                    String(rid), r.id, r.deviceId, r.markerKey, r.category, r.day, String(r.takenAt),
                    bits, text(r.valueText), r.unit, r.source, text(r.note), text(r.referenceText),
                ].joined(separator: "|")
            }
        }
    }

    /// Stored row count per device id.
    static func countsById(_ store: WhoopStore) throws -> [String: Int] {
        try store.registryWriter.read { db in
            var counts: [String: Int] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT deviceId, COUNT(*) AS c FROM labMarker GROUP BY deviceId") {
                counts[row["deviceId"]] = row["c"]
            }
            return counts
        }
    }

    /// The `metricSeries` rows under `lab-book`, ordered by (key, day).
    static func labBookCells(_ store: WhoopStore) throws -> [Cell] {
        try allSeries(store).filter { $0.deviceId == WhoopStore.labBookSourceId }
    }

    /// Every `metricSeries` row, ordered by (deviceId, key, day).
    static func allSeries(_ store: WhoopStore) throws -> [Cell] {
        try allSeries(writer: store.registryWriter)
    }

    static func allSeries(writer: any DatabaseWriter) throws -> [Cell] {
        try writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT deviceId, key, day, value FROM metricSeries ORDER BY deviceId ASC, key ASC, day ASC
                """).map { Cell(deviceId: $0["deviceId"], key: $0["key"], day: $0["day"], value: $0["value"]) }
        }
    }

    /// Ids of the `pairedDevice` rows, ascending.
    static func registryIds(_ store: WhoopStore) throws -> [String] {
        try store.registryWriter.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM pairedDevice ORDER BY id ASC")
        }
    }

    // MARK: - Assertions

    /// Per-id row counts, asserted before and after every operation in the store tests.
    static func assertCounts(_ store: WhoopStore, _ expected: [String: Int], _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try countsById(store), expected, message, file: file, line: line)
    }

    // MARK: - Generated input

    /// SplitMix64 with a fixed seed: the same sequence on every run and every machine.
    struct Generator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// A value in `0..<bound`. `bound` must be positive.
        mutating func below(_ bound: Int) -> Int {
            Int(next() % UInt64(bound))
        }

        mutating func pick<T>(_ items: [T]) -> T {
            items[below(items.count)]
        }

        /// Fisher-Yates, driven by this generator.
        mutating func shuffled<T>(_ items: [T]) -> [T] {
            var out = items
            guard out.count > 1 else { return out }
            for i in stride(from: out.count - 1, to: 0, by: -1) {
                out.swapAt(i, below(i + 1))
            }
            return out
        }
    }
}
