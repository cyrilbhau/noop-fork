import XCTest
import GRDB
@testable import WhoopStore

// Stage 1 (weigh-in and scorecard), specification §9.1 and §12.2.
//
// A weigh-in is one or two `labMarker` rows and the stage adds NO store function: `WeighInStore` (app
// target) drives `upsertLabMarkers`, `labMarkers(deviceId:markerKey:)` and `deleteLabMarker(id:)` as
// they are today. Every test in this file therefore passes BEFORE the stage's implementation exists.
// Each one pins a piece of existing store behaviour that the weigh-in flow is built on, and says which.
// If one of them starts failing, the store changed under the weigh-in flow, not the other way round.
//
// Synthetic values only: the "Fixture Person" of specification §13.
final class WeighInLabMarkerTests: XCTestCase {

    // MARK: - Fixture

    private let active = "my-whoop"
    private let earlier = "whoop-earlier"

    // Wednesdays at 07:00 UTC, as §13.1.
    private let week1 = 1_925_622_000   // 2031-01-08
    private let week2 = 1_926_226_800   // 2031-01-15
    private let week3 = 1_926_831_600   // 2031-01-22

    /// A row shaped exactly as the table in §9.1 says `WeighInStore` writes it.
    private func weighIn(_ key: String, id: String? = nil, deviceId: String? = nil, day: String,
                         takenAt: Int, value: Double, source: String = "manual") -> LabMarkerRow {
        LabMarkerRow(id: id ?? "\(key)-\(takenAt)-0A1B2C3D", deviceId: deviceId ?? active, markerKey: key,
                     category: "bodyMeasurement", day: day, takenAt: takenAt, value: value,
                     valueText: nil, unit: key == "weight" ? "kg" : "cm", source: source,
                     note: nil, referenceText: nil)
    }

    private func projection(_ store: WhoopStore, _ key: String) async throws -> [MetricPoint] {
        try await store.metricSeries(deviceId: WhoopStore.labBookSourceId, key: key,
                                     from: "0000-01-01", to: "9999-12-31")
    }

    /// Every `labMarker` row in the database, whatever its device id, in a stable order.
    private func allRows(_ store: WhoopStore) throws -> [LabMarkerRow] {
        try store.registryWriter.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM labMarker ORDER BY deviceId, markerKey, takenAt, id")
                .map(LabMarkerRow.decode)
        }
    }

    // MARK: - §12.2 named cases

    /// Pins: a row with the §9.1 columns is stored and read back unchanged, including the nil text
    /// columns and an unrounded value.
    func testWeighInRowRoundTrips() async throws {
        let store = try await WhoopStore.inMemory()
        let row = weighIn("weight", day: "2031-01-08", takenAt: week1, value: 99.9537)
        let written = try await store.upsertLabMarkers([row])
        XCTAssertEqual(written, 1)

        let back = try await store.labMarkers(deviceId: active, markerKey: "weight")
        XCTAssertEqual(back, [row], "every column round-trips, the value unrounded")
        XCTAssertEqual(back.first?.category, "bodyMeasurement")
        XCTAssertEqual(back.first?.source, "manual")
        XCTAssertEqual(back.first?.unit, "kg")
        XCTAssertNil(back.first?.valueText)
        XCTAssertNil(back.first?.note)
        XCTAssertNil(back.first?.referenceText)
    }

    /// Pins: §9.1 "Edit the value" — an upsert with the same id, instant and source updates the one row.
    func testEditingValueWithSameInstantUpdatesInPlace() async throws {
        let store = try await WhoopStore.inMemory()
        let original = weighIn("weight", day: "2031-01-08", takenAt: week1, value: 100.0)
        try await store.upsertLabMarkers([original])

        var edited = original
        edited.value = 99.6
        try await store.upsertLabMarkers([edited])

        let rows = try await store.labMarkers(deviceId: active, markerKey: "weight")
        XCTAssertEqual(rows, [edited], "one row, same id, new value")
        let proj = try await projection(store, "weight")
        XCTAssertEqual(proj.map(\.day), ["2031-01-08"])
        XCTAssertEqual(proj.map(\.value), [99.6], "the projected day follows the edit")
    }

    /// Pins: §9.1 "Edit the date" — insert the new row, then delete the old id. Between the two steps
    /// both readings exist; afterwards only the new one does, and the projection has moved with it.
    func testInsertThenDeleteMovesAReadingToAnotherDay() async throws {
        let store = try await WhoopStore.inMemory()
        let old = weighIn("weight", id: "weight-\(week1)-AAAAAAAA", day: "2031-01-08", takenAt: week1, value: 100.0)
        try await store.upsertLabMarkers([old])

        let moved = weighIn("weight", id: "weight-\(week2)-BBBBBBBB", day: "2031-01-15", takenAt: week2, value: 100.0)
        try await store.upsertLabMarkers([moved])
        let between = try await store.labMarkers(deviceId: active, markerKey: "weight")
        XCTAssertEqual(between, [old, moved], "after the insert and before the delete there are two readings, never none")

        let deleted = try await store.deleteLabMarker(id: old.id)
        XCTAssertTrue(deleted)
        let after = try await store.labMarkers(deviceId: active, markerKey: "weight")
        XCTAssertEqual(after, [moved])
        let proj = try await projection(store, "weight")
        XCTAssertEqual(proj.map(\.day), ["2031-01-15"], "the old day's projection is gone and the new day's exists")
    }

    /// Pins correction C4: the store cannot edit an instant. Re-inserting an existing id with another
    /// `takenAt` misses the natural-key conflict and violates the primary key, and the original row
    /// is left as it was. This is why a date edit is insert-then-delete.
    func testReinsertingAnIdWithANewInstantFails() async throws {
        let store = try await WhoopStore.inMemory()
        let original = weighIn("weight", day: "2031-01-08", takenAt: week1, value: 100.0)
        try await store.upsertLabMarkers([original])

        var retimed = original
        retimed.takenAt = week2
        retimed.day = "2031-01-15"
        do {
            try await store.upsertLabMarkers([retimed])
            XCTFail("re-inserting an id with a new instant must fail on the primary key")
        } catch {
            // expected
        }
        let rows = try await store.labMarkers(deviceId: active, markerKey: "weight")
        XCTAssertEqual(rows, [original], "the failed write changed nothing")
    }

    /// Pins: §9.1 "Delete" — the row goes and so does its projected day.
    func testDeleteRemovesTheRowAndItsProjectedDay() async throws {
        let store = try await WhoopStore.inMemory()
        let row = weighIn("waist", day: "2031-01-08", takenAt: week1, value: 100.0)
        try await store.upsertLabMarkers([row])
        let before = try await projection(store, "waist")
        XCTAssertEqual(before.count, 1)

        let deleted = try await store.deleteLabMarker(id: row.id)
        XCTAssertTrue(deleted)
        let rows = try await store.labMarkers(deviceId: active, markerKey: "waist")
        XCTAssertTrue(rows.isEmpty)
        let after = try await projection(store, "waist")
        XCTAssertTrue(after.isEmpty, "no stale projected day is left behind")
    }

    /// Pins: the store's rule for several readings on one day is the latest instant, which is the rule
    /// §7.1 item 4 relies on when it picks the latest reading of a week.
    func testTwoReadingsOnOneDayProjectTheLatest() async throws {
        let store = try await WhoopStore.inMemory()
        let morning = weighIn("weight", id: "weight-\(week1)-AAAAAAAA", day: "2031-01-08", takenAt: week1, value: 100.4)
        let evening = weighIn("weight", id: "weight-\(week1 + 3600)-BBBBBBBB", day: "2031-01-08",
                              takenAt: week1 + 3600, value: 100.0)
        // Inserted newest first, so the result cannot depend on insertion order.
        try await store.upsertLabMarkers([evening, morning])

        let rows = try await store.labMarkers(deviceId: active, markerKey: "weight")
        XCTAssertEqual(rows.map(\.id), [morning.id, evening.id], "both readings are kept, oldest first")
        let proj = try await projection(store, "weight")
        XCTAssertEqual(proj.map(\.value), [100.0], "the later instant represents the day")
    }

    /// Pins: a deleted reading is gone from the per-marker history the weekly series is built from.
    func testDeletedReadingIsAbsentFromTheMarkerHistory() async throws {
        let store = try await WhoopStore.inMemory()
        let first = weighIn("weight", day: "2031-01-08", takenAt: week1, value: 100.0)
        let second = weighIn("weight", day: "2031-01-15", takenAt: week2, value: 99.2)
        let third = weighIn("weight", day: "2031-01-22", takenAt: week3, value: 98.4)
        try await store.upsertLabMarkers([first, second, third])

        _ = try await store.deleteLabMarker(id: second.id)

        let rows = try await store.labMarkers(deviceId: active, markerKey: "weight")
        XCTAssertEqual(rows, [first, third], "the other readings are untouched and still ordered")
        let proj = try await projection(store, "weight")
        XCTAssertEqual(proj.map(\.day), ["2031-01-08", "2031-01-22"])
    }

    /// Pins: the natural key includes the marker, so a weight and a waist saved at one instant are two
    /// rows and neither overwrites the other.
    func testWeightAndWaistAtTheSameInstantAreSeparateRows() async throws {
        let store = try await WhoopStore.inMemory()
        let weight = weighIn("weight", day: "2031-01-08", takenAt: week1, value: 100.0)
        let waist = weighIn("waist", day: "2031-01-08", takenAt: week1, value: 100.0)
        let written = try await store.upsertLabMarkers([weight, waist])
        XCTAssertEqual(written, 2)

        let weights = try await store.labMarkers(deviceId: active, markerKey: "weight")
        let waists = try await store.labMarkers(deviceId: active, markerKey: "waist")
        XCTAssertEqual(weights, [weight])
        XCTAssertEqual(waists, [waist])
        let body = try await store.labMarkers(deviceId: active, category: "bodyMeasurement")
        XCTAssertEqual(body.count, 2)
    }

    // MARK: - Cases the plan does not name

    /// Pins: §9.1 "Save" — two saves in the same second for the same marker update one row. The row
    /// keeps the FIRST id (the conflict clause does not rewrite `id`), so an id handed to the history
    /// list stays valid after a double tap.
    func testSecondSaveInTheSameSecondUpdatesOneRowAndKeepsItsId() async throws {
        let store = try await WhoopStore.inMemory()
        let first = weighIn("weight", id: "weight-\(week1)-AAAAAAAA", day: "2031-01-08", takenAt: week1, value: 100.0)
        let second = weighIn("weight", id: "weight-\(week1)-BBBBBBBB", day: "2031-01-08", takenAt: week1, value: 99.8)
        try await store.upsertLabMarkers([first])
        try await store.upsertLabMarkers([second])

        let rows = try await store.labMarkers(deviceId: active, markerKey: "weight")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, first.id, "the stored id is the first one")
        XCTAssertEqual(rows.first?.value, 99.8, "the value is the second one")
        let deletedByLaterId = try await store.deleteLabMarker(id: second.id)
        XCTAssertFalse(deletedByLaterId, "the id minted by the second save never existed in the table")
    }

    /// Pins the precondition of ruling R25: every store read is scoped to ONE device id. A reading
    /// saved under an earlier strap id is not returned for the active id, so the union over ids has to
    /// be made by the caller (`WeighInStore` and `BodyMeasurementProvider`), and it stays where it is.
    func testReadingsAreScopedToTheDeviceIdTheyWereWrittenUnder() async throws {
        let store = try await WhoopStore.inMemory()
        let old = weighIn("weight", deviceId: earlier, day: "2031-01-08", takenAt: week1, value: 100.0)
        let new = weighIn("weight", deviceId: active, day: "2031-01-15", takenAt: week2, value: 99.2)
        try await store.upsertLabMarkers([old, new])

        let underActive = try await store.labMarkers(deviceId: active, markerKey: "weight")
        let underEarlier = try await store.labMarkers(deviceId: earlier, markerKey: "weight")
        XCTAssertEqual(underActive, [new])
        XCTAssertEqual(underEarlier, [old], "the earlier id's reading is still stored, under its own id")
    }

    /// Pins the other half of R25: the natural key includes the device id, so the same marker, instant
    /// and source under two ids are two rows with two ids. The caller de-duplicates; the store keeps both.
    func testSameReadingUnderTwoDeviceIdsIsTwoRows() async throws {
        let store = try await WhoopStore.inMemory()
        let underEarlier = weighIn("weight", id: "weight-\(week1)-AAAAAAAA", deviceId: earlier,
                                   day: "2031-01-08", takenAt: week1, value: 100.0)
        let underActive = weighIn("weight", id: "weight-\(week1)-BBBBBBBB", deviceId: active,
                                  day: "2031-01-08", takenAt: week1, value: 99.9)
        try await store.upsertLabMarkers([underEarlier, underActive])
        XCTAssertEqual(try allRows(store).count, 2)

        // Deleting by id removes only the row under the id it was stored under.
        let deleted = try await store.deleteLabMarker(id: underActive.id)
        XCTAssertTrue(deleted)
        XCTAssertEqual(try allRows(store), [underEarlier], "the other id's copy is byte-identical")
    }

    /// Pins: a value edit addressed to a row under an earlier id (same device id, marker, instant and
    /// source) updates that row in place and creates nothing under the active id.
    func testValueEditUnderAnEarlierDeviceIdStaysUnderThatId() async throws {
        let store = try await WhoopStore.inMemory()
        let old = weighIn("weight", deviceId: earlier, day: "2031-01-08", takenAt: week1, value: 100.0)
        try await store.upsertLabMarkers([old])

        var edited = old
        edited.value = 99.5
        try await store.upsertLabMarkers([edited])

        XCTAssertEqual(try allRows(store), [edited], "one row, still under the earlier id")
    }

    /// Pins: deleting an id that does not exist reports false and removes nothing.
    func testDeletingAnUnknownIdReturnsFalseAndChangesNothing() async throws {
        let store = try await WhoopStore.inMemory()
        let row = weighIn("weight", day: "2031-01-08", takenAt: week1, value: 100.0)
        try await store.upsertLabMarkers([row])
        let before = try allRows(store)

        let deleted = try await store.deleteLabMarker(id: "weight-0-FFFFFFFF")

        XCTAssertFalse(deleted)
        XCTAssertEqual(try allRows(store), before)
    }

    /// Data safety. Pins: saving, value-editing, date-editing and deleting weigh-in rows through the
    /// store calls of §9.1 leaves every other Lab Book row byte-identical — other markers, other
    /// sources of the same marker, qualitative rows, and rows under another device id.
    func testOtherLabBookRowsAreByteIdenticalAfterWeighInWrites() async throws {
        let store = try await WhoopStore.inMemory()
        let bystanders: [LabMarkerRow] = [
            LabMarkerRow(id: "ldl-1", deviceId: active, markerKey: "ldl", category: "bloodPanel",
                         day: "2031-01-08", takenAt: week1, value: 3.1, valueText: nil, unit: "mmol/L",
                         source: "manual", note: "fasted", referenceText: "< 3.0"),
            LabMarkerRow(id: "bf-1", deviceId: active, markerKey: "body_fat", category: "bodyMeasurement",
                         day: "2031-01-08", takenAt: week1, value: 24.5, valueText: nil, unit: "%",
                         source: "manual", note: nil, referenceText: nil),
            LabMarkerRow(id: "height-1", deviceId: active, markerKey: "height", category: "bodyMeasurement",
                         day: "2031-01-08", takenAt: week1, value: 180.0, valueText: nil, unit: "cm",
                         source: "manual", note: nil, referenceText: nil),
            // The same marker and instant from another source: a separate row by the natural key.
            LabMarkerRow(id: "weight-csv-1", deviceId: active, markerKey: "weight", category: "bodyMeasurement",
                         day: "2031-01-08", takenAt: week1, value: 220.5, valueText: nil, unit: "lb",
                         source: "csv", note: "imported", referenceText: nil),
            LabMarkerRow(id: "note-1", deviceId: active, markerKey: "appointment", category: "appointmentNote",
                         day: "2031-01-08", takenAt: week1, value: nil, valueText: "fixture note", unit: "",
                         source: "manual", note: nil, referenceText: nil),
            LabMarkerRow(id: "weight-old-1", deviceId: earlier, markerKey: "weight", category: "bodyMeasurement",
                         day: "2030-12-25", takenAt: week1 - 14 * 86_400, value: 101.0, valueText: nil,
                         unit: "kg", source: "manual", note: nil, referenceText: nil),
        ]
        try await store.upsertLabMarkers(bystanders)
        func others() throws -> [LabMarkerRow] {
            try allRows(store).filter { row in bystanders.contains { $0.id == row.id } }
        }
        let before = try others()
        XCTAssertEqual(before.count, bystanders.count)

        // Save.
        let weight = weighIn("weight", id: "weight-\(week1)-AAAAAAAA", day: "2031-01-08", takenAt: week1, value: 100.0)
        let waist = weighIn("waist", id: "waist-\(week1)-AAAAAAAA", day: "2031-01-08", takenAt: week1, value: 100.0)
        try await store.upsertLabMarkers([weight, waist])
        XCTAssertEqual(try others(), before, "save")

        // Edit the value.
        var edited = weight
        edited.value = 99.7
        try await store.upsertLabMarkers([edited])
        XCTAssertEqual(try others(), before, "value edit")

        // Edit the date: insert, then delete.
        let moved = weighIn("weight", id: "weight-\(week2)-BBBBBBBB", day: "2031-01-15", takenAt: week2, value: 99.7)
        try await store.upsertLabMarkers([moved])
        _ = try await store.deleteLabMarker(id: weight.id)
        XCTAssertEqual(try others(), before, "date edit")

        // Delete.
        _ = try await store.deleteLabMarker(id: moved.id)
        _ = try await store.deleteLabMarker(id: waist.id)
        XCTAssertEqual(try others(), before, "delete")
        XCTAssertEqual(try allRows(store).count, bystanders.count, "only the weigh-in rows came and went")
    }
}
