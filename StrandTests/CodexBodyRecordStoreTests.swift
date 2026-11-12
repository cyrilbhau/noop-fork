// API ASSUMED BY THESE TESTS
// Stage 4 §§7.6–7.8, 9.1–9.2, 12.4; rulings A10–A15 override older §9.2 prose.
// BodyRecordStore(repository:provider:timeZone:now:) exposes scans(), save(_:replacing:),
// delete(_:), benchmarkReadings(key:), benchmarkKeysPresent(), saveBenchmark(key:value:unit:
// takenAt:note:), deleteBenchmark(_:). BodyScan, BodyScanDraft and BodyRecordError are exactly
// the types declared in §9.1. No extra test seam is required.
// Save validates the whole draft before writing; date moves and deletes affect all true copies;
// conflicting readings survive unrelated edits and are both visible. These are behavioural tests
// against an in-memory store, authored before implementation. C5 only parse-checks this file.
import XCTest
import WhoopStore
import StrandImport
import StrandAnalytics
@testable import Strand

@MainActor
final class CodexBodyRecordStoreTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let later = Date(timeIntervalSince1970: 1_956_528_000) // 2032-01-01; Lab Book only.
    private let gone = "whoop-FIXTURE-GONE"

    private func harness(zone: TimeZone? = nil, now: Date? = nil) async throws
        -> (WhoopStore, Repository, BodyRecordStore) {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let zone = zone ?? utc
        let now = now ?? later
        return (store, repo, BodyRecordStore(repository: repo, provider: nil, timeZone: { zone }, now: { now }))
    }

    // Fixture Person scan A, stage 4 §13.1. Missing values are absent dictionary keys.
    private func draft(day: String = "2031-01-08") -> BodyScanDraft {
        BodyScanDraft(day: day, values: ["weight": 100, "body_fat": 30,
            "scan_fat_mass": 30, "scan_lean_mass": 67, "scan_bone_mass": 3], note: "Fixture note")
    }

    private func all(_ store: WhoopStore, deviceIds: [String] = ["my-whoop", "whoop-FIXTURE-GONE"])
        async throws -> [LabMarkerRow] {
        var result: [LabMarkerRow] = []
        for id in deviceIds {
            for category in ["bodyMeasurement", "imaging", "other"] {
                result += try await store.labMarkers(deviceId: id, category: category)
            }
        }
        return result.sorted { $0.id < $1.id }
    }

    private func copies(of scan: BodyScan, in store: WhoopStore) async throws {
        let rows = scan.rows.values.flatMap { $0 }.map { row -> LabMarkerRow in
            var copy = row
            copy.id = "gone-\(row.id)"
            copy.deviceId = gone
            return copy
        }
        try await store.upsertLabMarkers(rows)
    }

    private func assertRefused(_ error: BodyRecordError, draft: BodyScanDraft,
                               replacing: BodyScan? = nil,
                               h: (WhoopStore, Repository, BodyRecordStore),
                               file: StaticString = #filePath, line: UInt = #line) async throws {
        let before = try await all(h.0)
        do {
            _ = try await h.2.save(draft, replacing: replacing)
            XCTFail("Expected \(error)", file: file, line: line)
        } catch let actual as BodyRecordError {
            XCTAssertEqual(actual, error, file: file, line: line)
        }
        let after = try await all(h.0)
        XCTAssertEqual(after, before, "Refusal must leave every row intact", file: file, line: line)
    }

    func testSaveKeepsTotalInTheExistingWeightRowAndOmitsMissingFields() async throws {
        let h = try await harness()
        let saved = try await h.2.save(draft(), replacing: nil)
        XCTAssertEqual(saved.source, MarkerCatalog.scanSource)
        XCTAssertEqual(saved.day, "2031-01-08")
        XCTAssertEqual(saved.takenAt, 1_925_640_000)
        XCTAssertEqual(saved.values["weight"], 100)
        XCTAssertNil(saved.values["scan_visceral_fat_area"])
        let rows = try await all(h.0)
        XCTAssertEqual(rows.count, 6) // five numeric rows and one note
        let weight = try XCTUnwrap(rows.first { $0.markerKey == "weight" })
        XCTAssertEqual(weight.category, "bodyMeasurement")
        XCTAssertEqual(weight.unit, "kg")
        XCTAssertEqual(weight.value, 100)
        XCTAssertFalse(rows.contains { $0.markerKey == "scan_total_mass" })
        XCTAssertFalse(rows.contains { $0.markerKey == "scan_visceral_fat_area" })
    }

    func testEveryInvalidFieldIsValidatedBeforeAnyWrite() async throws {
        let h = try await harness()
        for value in [Double.nan, .infinity, -.infinity, 0.999, 200.001] {
            var invalid = draft()
            invalid.values["scan_fat_mass"] = value
            try await assertRefused(.outOfRange(key: "scan_fat_mass"), draft: invalid, h: h)
        }
    }

    func testInclusiveBoundsAndMeasuredVisceralZeroAreStored() async throws {
        let h = try await harness()
        for (index, value) in [1.0, 200.0].enumerated() {
            let saved = try await h.2.save(BodyScanDraft(day: "2031-01-0\(8 + index)",
                values: ["scan_fat_mass": value, "scan_visceral_fat_mass": 0], note: nil), replacing: nil)
            XCTAssertEqual(saved.values["scan_fat_mass"], value)
            XCTAssertEqual(saved.values["scan_visceral_fat_mass"], 0)
        }
    }

    func testWeightAndNoteAloneDoNotCreateAScan() async throws {
        let h = try await harness()
        try await assertRefused(.nothingToSave,
            draft: BodyScanDraft(day: "2031-01-08", values: ["weight": 100], note: "Fixture note"), h: h)
        try await assertRefused(.nothingToSave,
            draft: BodyScanDraft(day: "2031-01-08", values: [:], note: "Fixture note"), h: h)
    }

    func testInvalidAndFutureDaysWriteNothing() async throws {
        let h = try await harness()
        for day in ["2031-1-08", "2031-02-29", "garbage", "0000-01-01"] {
            try await assertRefused(.invalidDay, draft: draft(day: day), h: h)
        }
        try await assertRefused(.futureDay, draft: draft(day: "2032-01-02"), h: h)
    }

    func testNoteLengthBoundaryIsCheckedBeforeWriting() async throws {
        let h = try await harness()
        var value = draft()
        value.note = String(repeating: "é", count: 501)
        try await assertRefused(.noteTooLong, draft: value, h: h)
        value.note = String(repeating: "é", count: 500)
        let saved = try await h.2.save(value, replacing: nil)
        XCTAssertEqual(saved.note, value.note)
    }

    func testSaveBeforeLocalNoonUsesNow() async throws {
        let morning = Date(timeIntervalSince1970: 1_925_622_000) // 2031-01-08 07:00 UTC.
        let h = try await harness(now: morning)
        let saved = try await h.2.save(draft(), replacing: nil)
        XCTAssertEqual(saved.takenAt, Int(morning.timeIntervalSince1970))
        XCTAssertEqual(saved.day, "2031-01-08")
    }

    func testLocalNoonUsesTheInjectedZone() async throws {
        let h = try await harness(zone: TimeZone(secondsFromGMT: 19800)!)
        let saved = try await h.2.save(draft(), replacing: nil)
        XCTAssertEqual(saved.takenAt, 1_925_620_200) // 12:00 IST is 06:30 UTC.
        XCTAssertEqual(saved.day, "2031-01-08")
    }

    func testSameDayEditKeepsIdentityAndUneditedMetadata() async throws {
        let h = try await harness()
        let original = try await h.2.save(draft(), replacing: nil)
        var changed = draft()
        changed.values["scan_fat_mass"] = 29
        let updated = try await h.2.save(changed, replacing: original)
        for key in original.rows.keys {
            let before = try XCTUnwrap(original.rows[key]?.first)
            let after = try XCTUnwrap(updated.rows[key]?.first)
            XCTAssertEqual(after.id, before.id)
            XCTAssertEqual(after.deviceId, before.deviceId)
            XCTAssertEqual(after.takenAt, before.takenAt)
            XCTAssertEqual(after.day, before.day)
            XCTAssertEqual(after.category, before.category)
            XCTAssertEqual(after.note, before.note)
            XCTAssertEqual(after.referenceText, before.referenceText)
        }
        XCTAssertEqual(updated.values["scan_fat_mass"], 29)
    }

    func testRemovingAFieldRemovesItsCopiesButLeavesOtherFields() async throws {
        let h = try await harness()
        let original = try await h.2.save(draft(), replacing: nil)
        try await copies(of: original, in: h.0)
        var changed = draft()
        changed.values.removeValue(forKey: "scan_fat_mass")
        _ = try await h.2.save(changed, replacing: original)
        let remaining = try await all(h.0)
        XCTAssertFalse(remaining.contains { $0.markerKey == "scan_fat_mass" })
        XCTAssertTrue(remaining.contains { $0.markerKey == "weight" && $0.deviceId == gone })
    }

    func testDateEditLeavesNoOldRowOrCopyBehind() async throws {
        let h = try await harness()
        let original = try await h.2.save(draft(), replacing: nil)
        try await copies(of: original, in: h.0)
        let moved = try await h.2.save(draft(day: "2031-01-15"), replacing: original)
        XCTAssertEqual(moved.day, "2031-01-15")
        let remaining = try await all(h.0)
        XCTAssertEqual(remaining.count, 6)
        XCTAssertTrue(remaining.allSatisfy { $0.day == "2031-01-15" && $0.takenAt != original.takenAt })
        let scans = await h.2.scans()
        XCTAssertEqual(scans.count, 1)
    }

    func testOccupancyUnderAnUnregisteredIdRefusesTheWholeEdit() async throws {
        let h = try await harness()
        let original = try await h.2.save(draft(), replacing: nil)
        let occupied = LabMarkerRow(id: "fixture-occupied", deviceId: gone, markerKey: "scan_bone_mass",
            category: "imaging", day: "2031-01-15", takenAt: 1_926_244_800, value: 3,
            valueText: nil, unit: "kg", source: MarkerCatalog.scanSource, note: nil, referenceText: nil)
        try await h.0.upsertLabMarkers([occupied])
        try await assertRefused(.instantOccupied, draft: draft(day: "2031-01-15"), replacing: original, h: h)
    }

    func testNewSaveOntoAnOccupiedInstantWritesNothing() async throws {
        let h = try await harness()
        _ = try await h.2.save(draft(), replacing: nil)
        try await assertRefused(.instantOccupied, draft: draft(), h: h)
    }

    func testDeleteRemovesAllCopiesAndCannotResurrectAScan() async throws {
        let h = try await harness()
        let original = try await h.2.save(draft(), replacing: nil)
        try await copies(of: original, in: h.0)
        try await h.2.delete(original)
        let remaining = try await all(h.0)
        let scans = await h.2.scans()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(scans.isEmpty)
    }

    func testConflictingMembersStayVisibleAreNotNumbersAndPreventEditing() async throws {
        let h = try await harness()
        let original = try await h.2.save(draft(), replacing: nil)
        var conflict = try XCTUnwrap(original.rows["scan_fat_mass"]?.first)
        conflict.id = "fixture-conflict"
        conflict.deviceId = gone
        conflict.value = 31
        try await h.0.upsertLabMarkers([conflict])
        let scans = await h.2.scans()
        let scan = try XCTUnwrap(scans.first)
        XCTAssertEqual(scan.conflictingKeys, ["scan_fat_mass"])
        XCTAssertEqual(scan.rows["scan_fat_mass"]?.count, 2)
        XCTAssertNil(scan.values["scan_fat_mass"])
        XCTAssertFalse(scan.isEditable)
        XCTAssertTrue(scan.isDeletable)
        try await assertRefused(.notEditable, draft: draft(), replacing: scan, h: h)
        try await h.2.delete(scan)
        let remaining = try await all(h.0)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testTrueCopiesUnderGoneIdAreOneMember() async throws {
        let h = try await harness()
        let original = try await h.2.save(draft(), replacing: nil)
        try await copies(of: original, in: h.0)
        let scans = await h.2.scans()
        let scan = try XCTUnwrap(scans.first)
        XCTAssertEqual(scans.count, 1)
        XCTAssertTrue(scan.conflictingKeys.isEmpty)
        XCTAssertTrue(scan.rows.values.allSatisfy { $0.count == 1 })
        XCTAssertEqual(scan.values, original.values)
    }

    func testUnreadableUnitIsReportedWithoutBecomingZero() async throws {
        let h = try await harness()
        let row = LabMarkerRow(id: "fixture-unit", deviceId: gone, markerKey: "scan_lean_mass",
            category: "imaging", day: "2031-01-08", takenAt: 1_925_640_000, value: 67,
            valueText: nil, unit: "unknown-unit", source: MarkerCatalog.scanSource, note: nil, referenceText: nil)
        try await h.0.upsertLabMarkers([row])
        let scans = await h.2.scans()
        let scan = try XCTUnwrap(scans.first)
        XCTAssertEqual(scan.unreadableKeys, ["scan_lean_mass"])
        XCTAssertNil(scan.values["scan_lean_mass"])
    }

    func testImportedScanRetainsStoredDayAndCannotBeEditedOrDeleted() async throws {
        let h = try await harness(zone: TimeZone(secondsFromGMT: -43200)!)
        let row = LabMarkerRow(id: "fixture-import", deviceId: gone, markerKey: "scan_lean_mass",
            category: "imaging", day: "2031-01-08", takenAt: 1_925_640_000, value: 67,
            valueText: nil, unit: "kg", source: "csv", note: nil, referenceText: nil)
        try await h.0.upsertLabMarkers([row])
        let scans = await h.2.scans()
        let scan = try XCTUnwrap(scans.first)
        XCTAssertEqual(scan.day, "2031-01-08")
        XCTAssertFalse(scan.isEditable)
        XCTAssertFalse(scan.isDeletable)
        try await assertRefused(.notEditable, draft: draft(), replacing: scan, h: h)
        do { try await h.2.delete(scan); XCTFail("Expected notEditable") }
        catch let error as BodyRecordError { XCTAssertEqual(error, .notEditable) }
        let after = try await all(h.0)
        XCTAssertEqual(after, [row])
    }

    func testScansSortByInstantRatherThanEntryOrder() async throws {
        let h = try await harness()
        for day in ["2031-01-08", "2031-05-28", "2031-04-09"] {
            var value = draft(day: day)
            if day != "2031-01-08" {
                value.values["weight"] = day == "2031-04-09" ? 95 : 94
                value.values["scan_fat_mass"] = day == "2031-04-09" ? 26 : 25
                value.values["scan_lean_mass"] = 66
                value.values.removeValue(forKey: "body_fat")
                value.note = nil
            }
            _ = try await h.2.save(value, replacing: nil)
        }
        let scans = await h.2.scans()
        XCTAssertEqual(scans.map(\.day), ["2031-01-08", "2031-04-09", "2031-05-28"])
    }

    func testBenchmarkWholeRepsAndCopyDeletion() async throws {
        let h = try await harness()
        let instant = Date(timeIntervalSince1970: 1_925_449_200) // Fixture Monday 2031-01-06 07:00 UTC.
        let saved = try await h.2.saveBenchmark(key: "bench_pushup_reps", value: 10, unit: "reps",
                                              takenAt: instant, note: "Fixture benchmark")
        var copy = saved
        copy.id = "fixture-benchmark-copy"
        copy.deviceId = gone
        try await h.0.upsertLabMarkers([copy])
        let readings = await h.2.benchmarkReadings(key: "bench_pushup_reps")
        XCTAssertEqual(readings.count, 1)
        do {
            _ = try await h.2.saveBenchmark(key: "bench_pushup_reps", value: 10.5, unit: "reps",
                                           takenAt: instant, note: nil)
            XCTFail("Fractional reps must be refused")
        } catch let error as BodyRecordError { XCTAssertEqual(error, .outOfRange(key: "bench_pushup_reps")) }
        try await h.2.deleteBenchmark(saved)
        let remaining = await h.2.benchmarkReadings(key: "bench_pushup_reps")
        XCTAssertTrue(remaining.isEmpty)
    }
}
