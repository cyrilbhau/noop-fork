// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/stage-4.md §7.6, §7.7, §7.8 and §9.1, declared in full at the
// top of BodyRecordTestSupport.swift. This file calls:
//
//     struct BodyScan                 (id, source, takenAt, day, values, rows, note, unreadableKeys,
//                                      conflictingKeys, isEditable, isDeletable)
//     struct BodyScanDraft            BodyScanDraft(day:values:note:), values in stored units
//     enum BodyRecordError            nothingToSave, outOfRange(key:), noteTooLong, invalidDay,
//                                     futureDay, instantOccupied, scanNotFound, notEditable
//     @MainActor final class BodyRecordStore
//         init(repository:provider:timeZone:now:)
//         func scans() async -> [BodyScan]
//         func save(_:replacing:) async throws -> BodyScan
//         func delete(_:) async throws
//         func benchmarkReadings(key:) async -> [LabMarkerRow]
//         func benchmarkKeysPresent() async -> [String]
//         func saveBenchmark(key:value:unit:takenAt:note:) async throws -> LabMarkerRow
//         func deleteBenchmark(_:) async throws
//
// Behaviour pinned here, as the specification decides it:
//
//  1. A save writes one row per entered field (§9.1): source `MarkerCatalog.scanSource`, the
//     scan's `takenAt` and `day` on every row, the stored unit, the value unrounded, category
//     `imaging` for a scan-only key and `bodyMeasurement` for `weight` and `body_fat`, `note` and
//     `referenceText` nil, every new row under the ACTIVE id (`repo.deviceId`), ids of the form
//     "<markerKey>-<takenAt>-<8 hex>". The note is a `scan_note` row with a nil value, the trimmed
//     text in `valueText` and an empty unit.
//  2. Validation happens before any write, and a refused save, edit or delete writes nothing at all.
//  3. The instant (§7.8): 12:00 local in the injected zone, or now if that is earlier; an edit that
//     keeps the day keeps `takenAt` exactly; `day` is the local day key of `takenAt`, stored once.
//  4. Occupancy (§9.1) reads the stored rows under every device id: any `body-scan` row of a §7.7
//     key at the target instant refuses the save. A row of another source does not occupy it.
//  5. An edit is one `replaceLabMarkers` call: same day updates members and their copies in place,
//     a removed key deletes its member and copies, another day moves every row under the active id.
//  6. Reads go through `LabBookRows` (§7.6): every id present, copies once, conflicting rows both
//     kept and the key named; a scan is every `(source, takenAt)` holding a scan-only key.
//  7. Benchmark validation (§7.7): reps 0…1000 whole, s 0…86400, `bench_grip_kg` 1…150. Which
//     `BodyRecordError` case a refused benchmark throws is not specified and not pinned: only that
//     it throws one and writes nothing.
//
// The failure-injection tests use a file-backed store and a second SQLite connection: a trigger makes
// every insert fail after a write's deletes have run, and a renamed table makes every read fail.
//
// Synthetic values only: the Fixture Person (stage 1 §13, stage 4 §13). Lab Book rows only, so the
// fixed 2031 fixture applies (stage 1 ruling R31).

import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

@MainActor
final class BodyRecordStoreTests: XCTestCase {
    private typealias F = BodyRecordFixture
    private typealias Fx = LabBookOwnershipAppFixture
    private let suites = BodyRecordSuites()
    private let directories = BodyRecordTempDirectories()

    override func tearDown() {
        suites.removeAll()
        directories.removeAll()
        super.tearDown()
    }

    // MARK: - Harness

    /// The ownership fixture's ten rows stored as bystanders: every store operation below must
    /// leave each of them byte-identical.
    private func seeded(deviceId: String = F.active, now: Date = F.later, zone: TimeZone = F.utc,
                        onDisk: Bool = false) async throws -> BodyRecordHarness {
        let h = try await BodyRecordHarness.make(suites: suites, deviceId: deviceId, now: now, zone: zone,
                                                 onDiskIn: onDisk ? try directories.make() : nil)
        try await Fx.seed(Fx.all, into: h.store)
        return h
    }

    private func empty(deviceId: String = F.active, now: Date = F.later,
                       zone: TimeZone = F.utc) async throws -> BodyRecordHarness {
        try await BodyRecordHarness.make(suites: suites, deviceId: deviceId, now: now, zone: zone)
    }

    /// Fails unless every bystander row is still stored exactly as seeded.
    private func assertBystandersUntouched(_ h: BodyRecordHarness, file: StaticString = #filePath,
                                           line: UInt = #line) async throws {
        let stored = try await h.rowsById()
        for row in Fx.all {
            XCTAssertEqual(stored[row.id], row, "bystander \(row.id) changed", file: file, line: line)
        }
    }

    private func rows(_ h: BodyRecordHarness, source: String = MarkerCatalog.scanSource,
                      takenAt: Int) async throws -> [LabMarkerRow] {
        try await h.everyRow().filter { $0.source == source && $0.takenAt == takenAt }
    }

    private func assertRefused(_ expected: BodyRecordError, _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line,
                               _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected), nothing was thrown. \(message)", file: file, line: line)
        } catch let error as BodyRecordError {
            XCTAssertEqual(error, expected, message, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error). \(message)", file: file, line: line)
        }
    }

    private func assertRefusedWithSomeError(_ message: String, file: StaticString = #filePath,
                                            line: UInt = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected a BodyRecordError, nothing was thrown. \(message)", file: file, line: line)
        } catch is BodyRecordError {
        } catch {
            XCTFail("expected a BodyRecordError, got \(error). \(message)", file: file, line: line)
        }
    }

    private func copy(_ row: LabMarkerRow, to deviceId: String, suffix: String, value: Double? = nil) -> LabMarkerRow {
        var out = row
        out.id = "\(row.markerKey)-\(row.takenAt)-\(suffix)"
        out.deviceId = deviceId
        if let value { out.value = value }
        return out
    }

    // MARK: - Writing

    /// §9.1. Fault F47: the total-mass row written with the weigh-in's source.
    func testSaveWritesOneRowPerEnteredFieldWithTheScanSource() async throws {
        let h = try await seeded()
        let countsBefore = try await h.countsById()
        let scan = try await h.save(F.draftA)

        let written = try await rows(h, takenAt: F.noonA)
        XCTAssertEqual(written.count, F.scanA.count + 1, "one row per entered field, plus the note row")
        XCTAssertEqual(Set(written.map(\.markerKey)), Set(F.scanA.keys).union(["scan_note"]))
        let idPattern = try NSRegularExpression(pattern: "^[a-z_]+-\(F.noonA)-[0-9a-fA-F]{8}$")
        for row in written {
            XCTAssertEqual(row.source, MarkerCatalog.scanSource, row.markerKey)
            XCTAssertEqual(row.takenAt, F.noonA, row.markerKey)
            XCTAssertEqual(row.day, F.dayA, row.markerKey)
            XCTAssertEqual(row.deviceId, F.active, row.markerKey)
            XCTAssertEqual(row.category, F.category(row.markerKey), row.markerKey)
            XCTAssertEqual(row.unit, F.storedUnit[row.markerKey], row.markerKey)
            XCTAssertNil(row.note, row.markerKey)
            XCTAssertNil(row.referenceText, row.markerKey)
            XCTAssertTrue(row.id.hasPrefix("\(row.markerKey)-\(F.noonA)-"), row.id)
            XCTAssertEqual(idPattern.numberOfMatches(in: row.id, range: NSRange(row.id.startIndex..., in: row.id)), 1, row.id)
            if row.markerKey == "scan_note" {
                XCTAssertNil(row.value)
                XCTAssertEqual(row.valueText, F.noteA)
            } else {
                XCTAssertEqual(row.value, F.scanA[row.markerKey], "stored unrounded: \(row.markerKey)")
                XCTAssertNil(row.valueText, row.markerKey)
            }
        }
        var countsAfter = countsBefore
        countsAfter[F.active, default: 0] += F.scanA.count + 1
        let counts = try await h.countsById()
        XCTAssertEqual(counts, countsAfter, "rows were written under the active id only")
        try await assertBystandersUntouched(h)

        XCTAssertEqual(scan.id, F.scanId(takenAt: F.noonA))
        XCTAssertEqual(scan.source, MarkerCatalog.scanSource)
        XCTAssertEqual(scan.takenAt, F.noonA)
        XCTAssertEqual(scan.day, F.dayA)
        XCTAssertEqual(scan.values, F.scanA, "the scan as stored is returned")
        XCTAssertEqual(scan.note, F.noteA)
        XCTAssertEqual(scan.unreadableKeys, [])
        XCTAssertEqual(scan.conflictingKeys, [])
    }

    /// §8.1, ruling R41. Fault F10: total mass written under a new key.
    func testSaveWritesTotalMassAsAWeightRow() async throws {
        let h = try await empty()
        try await h.save(F.draftA)
        let weight = try await rows(h, takenAt: F.noonA).filter { $0.markerKey == "weight" }
        XCTAssertEqual(weight.count, 1)
        XCTAssertEqual(weight.first?.value, 100.0)
        XCTAssertEqual(weight.first?.unit, "kg")
        XCTAssertEqual(weight.first?.category, "bodyMeasurement")
        XCTAssertEqual(BodyMeasurementKind(markerKey: try XCTUnwrap(weight.first).markerKey), .weight)
        let readings = await h.weighIns.readings(.weight)
        XCTAssertEqual(readings.map(\.value), [100.0], "the weigh-in store's read is how the total is read back")
        XCTAssertEqual(readings.first?.source, MarkerCatalog.scanSource)
    }

    func testSaveWritesBodyFatUnderTheExistingKey() async throws {
        let h = try await empty()
        try await h.save(F.draftA)
        let fat = try await rows(h, takenAt: F.noonA).filter { $0.markerKey == MarkerCatalog.scanBodyFatKey }
        XCTAssertEqual(fat.map(\.value), [30.0])
        XCTAssertEqual(fat.first?.unit, "%")
        XCTAssertEqual(fat.first?.category, "bodyMeasurement")
        let keys = Set(try await h.everyRow().map(\.markerKey))
        XCTAssertFalse(keys.contains { $0.contains("total") }, "no scan_total_mass or similar key: \(keys)")
    }

    func testNewRowsAreWrittenUnderTheActiveId() async throws {
        let h = try await empty(deviceId: F.old)
        try await h.save(F.draftC)
        let written = try await rows(h, takenAt: F.noonC)
        XCTAssertEqual(written.count, F.scanC.count)
        XCTAssertEqual(Set(written.map(\.deviceId)), [F.old],
                       "the repository's device id, whatever the registry calls active")
    }

    /// Fault F16: an empty field written as a zero row.
    func testEmptyFieldsWriteNoRow() async throws {
        let h = try await empty()
        try await h.save(F.draftC)
        let written = try await rows(h, takenAt: F.noonC)
        XCTAssertEqual(Set(written.map(\.markerKey)), Set(F.scanC.keys))
        XCTAssertFalse(written.contains { $0.value == 0 }, "no zero row for a field that was not entered")
        XCTAssertFalse(written.contains { $0.markerKey == "scan_note" }, "no note row without a note")
        let total = try await h.everyRow().count
        XCTAssertEqual(total, F.scanC.count)
    }

    /// §7.7: visceral fat mass and area admit a measured zero.
    func testTypedZeroVisceralFatIsStoredAsZero() async throws {
        let h = try await empty()
        let scan = try await h.save(BodyScanDraft(day: F.dayA, values: ["scan_fat_mass": 30.0,
                                                                         "scan_visceral_fat_mass": 0,
                                                                         "scan_visceral_fat_area": 0], note: nil))
        let written = try await rows(h, takenAt: F.noonA)
        XCTAssertEqual(written.first { $0.markerKey == "scan_visceral_fat_mass" }?.value, 0)
        XCTAssertEqual(written.first { $0.markerKey == "scan_visceral_fat_area" }?.value, 0)
        XCTAssertEqual(scan.values["scan_visceral_fat_mass"], 0, "a measured zero is read back as zero")
        XCTAssertEqual(scan.unreadableKeys, [])
    }

    /// H7, §9.1: at least one scan-only numeric value. Total mass, body fat and a note are not.
    func testOnlyTotalMassIsNothingToSave() async throws {
        let h = try await seeded()
        let before = try await h.everyRow()
        await assertRefused(.nothingToSave, "total mass alone") {
            _ = try await h.records.save(BodyScanDraft(day: F.dayA, values: ["weight": 100.0], note: nil), replacing: nil)
        }
        await assertRefused(.nothingToSave, "total mass and body fat") {
            _ = try await h.records.save(BodyScanDraft(day: F.dayA, values: ["weight": 100.0, "body_fat": 30.0],
                                                       note: nil), replacing: nil)
        }
        await assertRefused(.nothingToSave, "a note alone") {
            _ = try await h.records.save(BodyScanDraft(day: F.dayA, values: [:], note: F.noteA), replacing: nil)
        }
        let after = try await h.everyRow()
        XCTAssertEqual(after, before, "nothing was written")
    }

    /// §7.7 ranges, every value validated before anything is written.
    func testOutOfRangeValueWritesNothing() async throws {
        let h = try await seeded()
        let before = try await h.everyRow()
        var tooHeavy = F.scanA
        tooHeavy["weight"] = 250.1
        await assertRefused(.outOfRange(key: "weight")) {
            _ = try await h.records.save(BodyScanDraft(day: F.dayA, values: tooHeavy, note: nil), replacing: nil)
        }
        var fatTooHigh = F.scanA
        fatTooHigh["scan_fat_mass"] = 200.5
        await assertRefused(.outOfRange(key: "scan_fat_mass")) {
            _ = try await h.records.save(BodyScanDraft(day: F.dayA, values: fatTooHigh, note: nil), replacing: nil)
        }
        var negativeArea = F.scanB
        negativeArea["scan_visceral_fat_area"] = -1
        await assertRefused(.outOfRange(key: "scan_visceral_fat_area")) {
            _ = try await h.records.save(BodyScanDraft(day: F.dayB, values: negativeArea, note: nil), replacing: nil)
        }
        var notFinite = F.scanC
        notFinite["scan_lean_mass"] = .nan
        await assertRefused(.outOfRange(key: "scan_lean_mass")) {
            _ = try await h.records.save(BodyScanDraft(day: F.dayC, values: notFinite, note: nil), replacing: nil)
        }
        let after = try await h.everyRow()
        XCTAssertEqual(after, before)
    }

    /// The range bounds are inclusive (§7.7).
    func testRangeBoundsAreInclusive() async throws {
        let h = try await empty()
        let scan = try await h.save(BodyScanDraft(day: F.dayA, values: ["weight": 30, "scan_fat_mass": 200,
                                                                         "scan_bmd_t_score": -8, "scan_bmd_z_score": 8],
                                                  note: nil))
        XCTAssertEqual(scan.values, ["weight": 30, "scan_fat_mass": 200, "scan_bmd_t_score": -8, "scan_bmd_z_score": 8])
    }

    func testFutureDayIsRefused() async throws {
        // 2031-01-08 09:30 UTC: the 9th is in the future, the 8th is not.
        let h = try await empty(now: F.date(1_925_631_000))
        await assertRefused(.futureDay) {
            _ = try await h.records.save(BodyScanDraft(day: "2031-01-09", values: F.scanA, note: nil), replacing: nil)
        }
        let stored = try await h.everyRow()
        XCTAssertEqual(stored, [])
    }

    /// §7.8, stage 1 ruling R5: the shared canonical-day rule decides, through `invalidDay`.
    func testNonCanonicalDayIsRefusedAsInvalidDay() async throws {
        let h = try await empty()
        for day in ["2031-1-8", "2031-02-30", "08/01/2031", "", "2031-01-08T12:00"] {
            XCTAssertNil(CanonicalDay.number(day), "precondition: \(day) is not canonical")
            await assertRefused(.invalidDay, day) {
                _ = try await h.records.save(BodyScanDraft(day: day, values: F.scanA, note: nil), replacing: nil)
            }
        }
        let stored = try await h.everyRow()
        XCTAssertEqual(stored, [])
    }

    func testInstantIsLocalNoonOrNowWhicheverIsEarlier() async throws {
        // Saved at 09:30 UTC on the scan's own day: noon has not come, so the instant is now.
        let h = try await empty(now: F.date(1_925_631_000))
        let early = try await h.save(F.draftA)
        XCTAssertEqual(early.takenAt, 1_925_631_000)
        XCTAssertEqual(early.day, F.dayA)

        // Saved later: noon of the chosen day.
        h.now.value = F.later
        let late = try await h.save(F.draftB)
        XCTAssertEqual(late.takenAt, F.noonB)
        XCTAssertEqual(late.day, F.dayB)
        let stored = try await h.everyRow()
        XCTAssertEqual(Set(stored.map(\.takenAt)), [1_925_631_000, F.noonB])
    }

    /// §7.8: `day` is the local day of `takenAt` in the zone at saving, stored and never recomputed.
    func testDayIsTheLocalDayInTheGivenZoneAndSurvivesAZoneChange() async throws {
        let kiritimati = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        let h = try await empty(zone: kiritimati)
        let saved = try await h.save(F.draftA)
        XCTAssertEqual(saved.takenAt, 1_925_589_600, "12:00 on 2031-01-08 at UTC+14 is 22:00 UTC on the 7th")
        XCTAssertEqual(saved.day, F.dayA)

        h.zone.value = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let listed = await h.records.scans()
        XCTAssertEqual(listed.map(\.day), [F.dayA], "travel does not move a scan")
        XCTAssertEqual(listed.map(\.takenAt), [1_925_589_600])

        // An edit that keeps the day keeps the instant exactly, in the new zone too.
        var values = F.scanA
        values["scan_fat_mass"] = 29.0
        let edited = try await h.save(BodyScanDraft(day: F.dayA, values: values, note: F.noteA),
                                      replacing: try XCTUnwrap(listed.first))
        XCTAssertEqual(edited.takenAt, 1_925_589_600)
        XCTAssertEqual(edited.day, F.dayA)
        let stored = try await h.everyRow()
        XCTAssertEqual(Set(stored.map(\.day)), [F.dayA])
    }

    /// §7.8: local noon exists on every day in every zone, including the days clocks change.
    func testNoonExistsAcrossADaylightSavingChange() async throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let h = try await empty(zone: newYork)
        let spring = try await h.save(BodyScanDraft(day: "2031-03-09", values: F.scanC, note: nil))
        XCTAssertEqual(spring.takenAt, 1_930_838_400, "12:00 EDT on the day clocks go forward")
        XCTAssertEqual(spring.day, "2031-03-09")

        h.zone.value = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let autumn = try await h.save(BodyScanDraft(day: "2031-10-26", values: F.scanC, note: nil))
        XCTAssertEqual(autumn.takenAt, 1_950_782_400, "12:00 GMT on the day clocks go back")
        XCTAssertEqual(autumn.day, "2031-10-26")
    }

    /// Fault F15: the occupied-instant check removed.
    func testSecondScanAtTheSameInstantIsRefused() async throws {
        let h = try await seeded()
        try await h.save(F.draftA)
        let before = try await h.everyRow()
        var other = F.scanC
        other["scan_fat_mass"] = 31.0
        await assertRefused(.instantOccupied) {
            _ = try await h.records.save(BodyScanDraft(day: F.dayA, values: other, note: nil), replacing: nil)
        }
        let after = try await h.everyRow()
        XCTAssertEqual(after, before, "nothing was written or overwritten")
        let listed = await h.records.scans()
        XCTAssertEqual(listed.map(\.values), [F.scanA])
    }

    /// V14, fault F40: occupancy spans every id present, registered or not, any brand.
    func testOccupancySpansUnregisteredAndOtherBrandIds() async throws {
        for holder in [F.gone, F.ring] {
            let h = try await seeded()
            try await h.seed([F.scanRow("scan_bmd", value: 1.2, deviceId: holder, day: F.dayA, takenAt: F.noonA)])
            let before = try await h.everyRow()
            let countsBefore = try await h.countsById()
            await assertRefused(.instantOccupied, "a body-scan row at the instant under \(holder)") {
                _ = try await h.records.save(F.draftA, replacing: nil)
            }
            let after = try await h.everyRow()
            XCTAssertEqual(after, before, holder)
            let countsAfter = try await h.countsById()
            XCTAssertEqual(countsAfter, countsBefore, holder)
        }
    }

    /// §9.1: only a `body-scan` row occupies an instant. A manual weight at that instant is another
    /// reading, and the scan's own weight row sits beside it.
    func testAManualReadingAtTheInstantDoesNotOccupyIt() async throws {
        let h = try await empty()
        try await h.seed([LabMarkerRow(id: "weight-\(F.noonA)-0A1B2C3D", deviceId: F.active, markerKey: "weight",
                                       category: "bodyMeasurement", day: F.dayA, takenAt: F.noonA, value: 101.0,
                                       valueText: nil, unit: "kg", source: "manual", note: nil, referenceText: nil)])
        try await h.save(F.draftA)
        let weights = try await h.everyRow().filter { $0.markerKey == "weight" && $0.takenAt == F.noonA }
        XCTAssertEqual(weights.map(\.source).sorted(), [MarkerCatalog.scanSource, "manual"].sorted())
        XCTAssertEqual(Set(weights.compactMap(\.value)), [100.0, 101.0])
    }

    func testEditSameDayKeepsRowIdsAndInstant() async throws {
        let h = try await seeded()
        let original = try await h.save(F.draftA)
        let idsBefore = try await rows(h, takenAt: F.noonA).reduce(into: [String: String]()) { $0[$1.markerKey] = $1.id }
        let countsBefore = try await h.countsById()

        var values = F.scanA
        values["scan_fat_mass"] = 29.0
        values["weight"] = 99.0
        let edited = try await h.save(BodyScanDraft(day: F.dayA, values: values, note: F.noteA), replacing: original)

        let after = try await rows(h, takenAt: F.noonA)
        let idsAfter = after.reduce(into: [String: String]()) { $0[$1.markerKey] = $1.id }
        XCTAssertEqual(idsAfter, idsBefore, "every row keeps its id")
        XCTAssertEqual(after.first { $0.markerKey == "scan_fat_mass" }?.value, 29.0)
        XCTAssertEqual(after.first { $0.markerKey == "weight" }?.value, 99.0)
        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.takenAt, F.noonA)
        XCTAssertEqual(edited.values, values)
        let countsAfter = try await h.countsById()
        XCTAssertEqual(countsAfter, countsBefore, "an edit in place adds and removes no row")
        try await assertBystandersUntouched(h)
    }

    /// V13 shape, §9.1: a member copied under another id takes the new value there too.
    func testEditSameDayUpdatesCopiesInPlaceUnderTheirOwnIds() async throws {
        let h = try await seeded()
        try await h.save(F.draftA)
        let fat = try await h.storedRow("scan_fat_mass", takenAt: F.noonA)
        let fatCopy = copy(fat, to: F.old, suffix: "C0FFEE01")
        try await h.seed([fatCopy])
        let scan = try await h.firstScan()
        XCTAssertEqual(scan.rows["scan_fat_mass"]?.count, 1, "the copy is one reading")

        var values = F.scanA
        values["scan_fat_mass"] = 29.0
        try await h.save(BodyScanDraft(day: F.dayA, values: values, note: F.noteA), replacing: scan)

        let stored = try await h.rowsById()
        XCTAssertEqual(stored[fat.id]?.value, 29.0)
        XCTAssertEqual(stored[fat.id]?.deviceId, F.active)
        XCTAssertEqual(stored[fatCopy.id]?.value, 29.0, "the copy follows")
        XCTAssertEqual(stored[fatCopy.id]?.deviceId, F.old, "and keeps its own id")
        XCTAssertEqual(stored.values.filter { $0.markerKey == "scan_fat_mass" }.count, 2)
        try await assertBystandersUntouched(h)
    }

    func testEditRemovingAFieldDeletesItsRowAndItsCopies() async throws {
        let h = try await seeded()
        try await h.save(F.draftA)
        let trunk = try await h.storedRow("scan_trunk_lean_mass", takenAt: F.noonA)
        try await h.seed([copy(trunk, to: F.gone, suffix: "C0FFEE02")])
        let scan = try await h.firstScan()
        let countsBefore = try await h.countsById()

        var values = F.scanA
        values.removeValue(forKey: "scan_trunk_lean_mass")
        let edited = try await h.save(BodyScanDraft(day: F.dayA, values: values, note: F.noteA), replacing: scan)

        let trunks = try await h.everyRow().filter { $0.markerKey == "scan_trunk_lean_mass" }
        XCTAssertEqual(trunks, [], "the member and its copy under the unregistered id are both gone")
        XCTAssertNil(edited.values["scan_trunk_lean_mass"])
        var expected = countsBefore
        expected[F.active, default: 0] -= 1
        expected[F.gone, default: 0] -= 1
        let countsAfter = try await h.countsById()
        XCTAssertEqual(countsAfter, expected)
        try await assertBystandersUntouched(h)
    }

    /// §9.1, fault F13: an edit to another day is one transaction. A failure injected into its
    /// inserts leaves the old scan whole.
    func testEditToAnotherDayMovesEveryRowInOneTransaction() async throws {
        let h = try await seeded(onDisk: true)
        let original = try await h.save(F.draftA)
        let countsBefore = try await h.countsById()

        let moved = try await h.save(BodyScanDraft(day: "2031-01-09", values: F.scanA, note: F.noteA), replacing: original)
        XCTAssertEqual(moved.takenAt, 1_925_726_400, "noon of the new day")
        XCTAssertEqual(moved.day, "2031-01-09")
        XCTAssertEqual(moved.values, F.scanA)
        let oldRows = try await rows(h, takenAt: F.noonA)
        XCTAssertEqual(oldRows, [], "no row is left at the old instant")
        let newRows = try await rows(h, takenAt: 1_925_726_400)
        XCTAssertEqual(newRows.count, F.scanA.count + 1)
        XCTAssertEqual(Set(newRows.map(\.day)), ["2031-01-09"])
        XCTAssertEqual(Set(newRows.map(\.deviceId)), [F.active])
        let countsAfter = try await h.countsById()
        XCTAssertEqual(countsAfter, countsBefore)
        try await assertBystandersUntouched(h)

        // The same move with every insert failing: the deletes inside the transaction roll back.
        let snapshot = try await h.everyRow()
        try h.failEveryInsert()
        do {
            _ = try await h.records.save(BodyScanDraft(day: "2031-01-10", values: F.scanA, note: F.noteA),
                                         replacing: moved)
            XCTFail("the injected failure must surface")
        } catch {}
        let afterFailure = try await h.everyRow()
        XCTAssertEqual(afterFailure, snapshot, "the old scan is whole: no half-moved scan exists")
    }

    /// §9.1: every member's id is deleted with its copies, so nothing brings a figure back.
    func testEditToAnotherDayLeavesNoCopyBehind() async throws {
        let h = try await empty()
        let original = try await h.save(F.draftA)
        let copies = try await rows(h, takenAt: F.noonA).enumerated().map { index, row in
            copy(row, to: F.gone, suffix: String(format: "C0FF%04X", index))
        }
        try await h.seed(copies)
        let listed = try await h.firstScan()
        XCTAssertEqual(listed.conflictingKeys, [], "copies are one reading each")

        try await h.save(BodyScanDraft(day: "2031-01-09", values: F.scanA, note: F.noteA), replacing: original)
        let left = try await h.everyRow().filter { $0.takenAt == F.noonA }
        XCTAssertEqual(left, [], "no copy under any id is left at the old instant")
        let scans = await h.records.scans()
        XCTAssertEqual(scans.map(\.takenAt), [1_925_726_400], "one scan, at the new instant")
    }

    /// V12.
    func testEditOntoAnOccupiedInstantWritesNothing() async throws {
        let h = try await seeded()
        try await h.save(F.draftA)
        let b = try await h.save(F.draftB)
        let before = try await h.everyRow()
        await assertRefused(.instantOccupied, "scan B moved onto scan A's day") {
            _ = try await h.records.save(BodyScanDraft(day: F.dayA, values: F.scanB, note: nil), replacing: b)
        }
        let after = try await h.everyRow()
        XCTAssertEqual(after, before)
        let listed = await h.records.scans()
        XCTAssertEqual(listed.map(\.values), [F.scanA, F.scanB], "scan B is unchanged")
    }

    func testEditOfAScanThatIsGoneIsScanNotFound() async throws {
        let h = try await empty()
        let a = try await h.save(F.draftA)
        try await h.records.delete(a)
        await assertRefused(.scanNotFound) {
            _ = try await h.records.save(F.draftA, replacing: a)
        }
        let stored = try await h.everyRow()
        XCTAssertEqual(stored, [])
    }

    func testDeleteRemovesEveryRowIncludingTheWeightRow() async throws {
        let h = try await seeded()
        let countsBefore = try await h.countsById()
        let a = try await h.save(F.draftA)
        try await h.save(F.draftB)
        let weightCell = try await h.cell("weight", F.dayA)
        XCTAssertNotNil(weightCell, "precondition: the scan's weight is projected")

        try await h.records.delete(a)
        let left = try await rows(h, takenAt: F.noonA)
        XCTAssertEqual(left, [], "the weight row and the note row go with the scan")
        let scans = await h.records.scans()
        XCTAssertEqual(scans.map(\.id), [F.scanId(takenAt: F.noonB)])
        var expected = countsBefore
        expected[F.active, default: 0] += F.scanB.count
        let countsAfter = try await h.countsById()
        XCTAssertEqual(countsAfter, expected)
        // The fixture's own manual weight on 2031-01-08 (F1, 100.0) backs the cell again.
        let cellAfter = try await h.cell("weight", F.dayA)
        XCTAssertEqual(cellAfter, 100.0)
        let fatCell = try await h.cell("scan_fat_mass", F.dayA)
        XCTAssertNil(fatCell, "a cell no row backs is gone")
        try await assertBystandersUntouched(h)
    }

    /// Fault F33.
    func testDeleteRemovesCopiesUnderEveryIdSoTheScanCannotReappear() async throws {
        let h = try await seeded()
        let a = try await h.save(F.draftA)
        let copies = try await rows(h, takenAt: F.noonA).enumerated().map { index, row in
            copy(row, to: F.gone, suffix: String(format: "C0FF%04X", index))
        }
        try await h.seed(copies)
        let listed = await h.records.scans()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.values, F.scanA)

        try await h.records.delete(a)
        let scans = await h.records.scans()
        XCTAssertEqual(scans, [], "the scan cannot reappear from its copies")
        let left = try await h.everyRow().filter { $0.takenAt == F.noonA }
        XCTAssertEqual(left, [], "no stored row of the scan remains under any id")
        try await assertBystandersUntouched(h)
    }

    /// V16: deleting a scan with a conflicting key removes every member, both conflicting rows included.
    func testDeleteOfAConflictingScanRemovesEveryMember() async throws {
        let h = try await seeded()
        try await h.save(F.draftA)
        let fat = try await h.storedRow("scan_fat_mass", takenAt: F.noonA)
        try await h.seed([copy(fat, to: F.old, suffix: "C0FFEE31", value: 31.0)])
        let scan = try await h.firstScan()
        XCTAssertEqual(scan.conflictingKeys, ["scan_fat_mass"])

        try await h.records.delete(scan)
        let left = try await h.everyRow().filter { $0.takenAt == F.noonA }
        XCTAssertEqual(left, [])
        try await assertBystandersUntouched(h)
    }

    /// §7.7, §9.1: the note is trimmed, at most 500 characters.
    func testNoteRoundTripsAndLongNoteIsRefused() async throws {
        let h = try await empty()
        let padded = try await h.save(BodyScanDraft(day: F.dayA, values: F.scanC, note: "  Fixture note \n"))
        XCTAssertEqual(padded.note, "Fixture note")
        let noteRow = try await rows(h, takenAt: F.noonA).first { $0.markerKey == MarkerCatalog.scanNoteKey }
        XCTAssertEqual(noteRow?.valueText, "Fixture note")
        XCTAssertNil(noteRow?.value)
        XCTAssertEqual(noteRow?.unit, "")
        XCTAssertEqual(noteRow?.category, "imaging")

        let longest = String(repeating: "n", count: 500)
        let atLimit = try await h.save(BodyScanDraft(day: F.dayB, values: F.scanC, note: longest))
        XCTAssertEqual(atLimit.note, longest)

        let before = try await h.everyRow()
        await assertRefused(.noteTooLong) {
            _ = try await h.records.save(BodyScanDraft(day: F.dayC, values: F.scanC,
                                                       note: String(repeating: "n", count: 501)), replacing: nil)
        }
        let after = try await h.everyRow()
        XCTAssertEqual(after, before)
    }

    // MARK: - Reading

    /// V13, fault F19.
    func testScanUnderAnotherRegisteredIdIsListed() async throws {
        let h = try await empty(deviceId: F.old)
        try await h.save(F.draftA)

        // The active id is re-pointed to the new strap.
        let repo = Repository(deviceId: F.active)
        repo.setStoreForTesting(h.store)
        let records = BodyRecordStore(repository: repo, timeZone: { F.utc }, now: { F.later })
        let listed = await records.scans()
        XCTAssertEqual(listed.count, 1)
        let scan = try XCTUnwrap(listed.first)
        XCTAssertEqual(scan.values, F.scanA, "whole")
        XCTAssertEqual(scan.note, F.noteA)
        XCTAssertTrue(scan.isEditable)

        var values = F.scanA
        values["scan_fat_mass"] = 29.0
        values["scan_visceral_fat_area"] = 90
        try await records.save(BodyScanDraft(day: F.dayA, values: values, note: F.noteA), replacing: scan)
        let stored = try await h.everyRow().filter { $0.takenAt == F.noonA }
        XCTAssertEqual(stored.first { $0.markerKey == "scan_fat_mass" }?.deviceId, F.old, "updated in place")
        XCTAssertEqual(stored.first { $0.markerKey == "scan_fat_mass" }?.value, 29.0)
        XCTAssertEqual(stored.first { $0.markerKey == "scan_visceral_fat_area" }?.deviceId, F.active,
                       "a field added by the edit is written under the active id")
        XCTAssertEqual(stored.count, F.scanA.count + 2)
    }

    /// V14, fault F19.
    func testScanUnderAnUnregisteredIdIsListed() async throws {
        let h = try await empty()
        try await h.seed(F.scanRows(F.scanA, note: F.noteA, deviceId: F.gone, day: F.dayA, takenAt: F.noonA))
        let listed = await h.records.scans()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.values, F.scanA)
        XCTAssertEqual(listed.first?.note, F.noteA)
        XCTAssertEqual(listed.first?.source, MarkerCatalog.scanSource)
        await assertRefused(.instantOccupied) {
            _ = try await h.records.save(F.draftA, replacing: nil)
        }
    }

    /// V15.
    func testCopyOfAScanRowUnderTwoIdsIsListedOnce() async throws {
        let h = try await empty()
        try await h.save(F.draftA)
        let fat = try await h.storedRow("scan_fat_mass", takenAt: F.noonA)
        try await h.seed([copy(fat, to: F.old, suffix: "C0FFEE03")])
        let listed = await h.records.scans()
        XCTAssertEqual(listed.count, 1)
        let scan = try XCTUnwrap(listed.first)
        XCTAssertEqual(scan.rows["scan_fat_mass"]?.count, 1)
        XCTAssertEqual(scan.rows["scan_fat_mass"]?.first?.deviceId, F.active, "represented by the active id's row")
        XCTAssertEqual(scan.values["scan_fat_mass"], 30.0)
        XCTAssertEqual(scan.conflictingKeys, [])
    }

    /// V16, fault F41.
    func testConflictingScanRowsAreBothKeptAndTheKeyIsConflicting() async throws {
        let h = try await empty()
        try await h.save(F.draftA)
        let fat = try await h.storedRow("scan_fat_mass", takenAt: F.noonA)
        let other = copy(fat, to: F.old, suffix: "C0FFEE31", value: 31.0)
        try await h.seed([other])

        let scan = try await h.firstScan()
        XCTAssertEqual(scan.conflictingKeys, ["scan_fat_mass"])
        XCTAssertNil(scan.values["scan_fat_mass"], "a conflicting key is never a number")
        XCTAssertEqual(scan.rows["scan_fat_mass"]?.map(\.id), [fat.id, other.id].sorted(), "both rows, ordered by id")
        XCTAssertEqual(scan.unreadableKeys, [])
        var expected = F.scanA
        expected.removeValue(forKey: "scan_fat_mass")
        XCTAssertEqual(scan.values, expected)
        let imaging = await LabBookRows.category("imaging", store: h.store, activeDeviceId: F.active)
        XCTAssertEqual(Set(imaging.filter { $0.markerKey == "scan_fat_mass" }.map(\.id)), [fat.id, other.id],
                       "both rows are still listed in Lab Book")

        // After the 31.0 row is deleted in Lab Book the scan is whole and editable again.
        try await h.store.deleteLabMarkerAndCopies(id: other.id)
        let repaired = try await h.firstScan()
        XCTAssertEqual(repaired.conflictingKeys, [])
        XCTAssertEqual(repaired.values, F.scanA)
        XCTAssertTrue(repaired.isEditable)
    }

    /// Fault F42.
    func testConflictingScanIsNotEditableAndIsDeletable() async throws {
        let h = try await empty()
        try await h.save(F.draftA)
        let fat = try await h.storedRow("scan_fat_mass", takenAt: F.noonA)
        try await h.seed([copy(fat, to: F.gone, suffix: "C0FFEE31", value: 31.0)])
        let scan = try await h.firstScan()
        XCTAssertFalse(scan.isEditable)
        XCTAssertTrue(scan.isDeletable)
        let before = try await h.everyRow()
        await assertRefused(.notEditable) {
            _ = try await h.records.save(F.draftA, replacing: scan)
        }
        let after = try await h.everyRow()
        XCTAssertEqual(after, before)
    }

    /// V10, §7.6: a scan imported by CSV is listed and is read-only in the body record.
    func testImportedScanIsListedAndNeitherEditableNorDeletable() async throws {
        let h = try await empty()
        try await h.seed(F.scanRows(F.scanA, deviceId: F.active, day: F.dayA, takenAt: F.noonA,
                                    source: LabMarkerCsvImport.sourceId))
        let scan = try await h.firstScan()
        XCTAssertEqual(scan.id, F.scanId(source: LabMarkerCsvImport.sourceId, takenAt: F.noonA))
        XCTAssertEqual(scan.source, LabMarkerCsvImport.sourceId)
        XCTAssertEqual(scan.values, F.scanA)
        XCTAssertFalse(scan.isEditable)
        XCTAssertFalse(scan.isDeletable)
        let before = try await h.everyRow()
        await assertRefused(.notEditable, "delete") { try await h.records.delete(scan) }
        await assertRefused(.notEditable, "edit") { _ = try await h.records.save(F.draftA, replacing: scan) }
        let after = try await h.everyRow()
        XCTAssertEqual(after, before)
    }

    /// §9.1: an imported scan's day is the day key its import stored, not the local day of noon UTC.
    func testImportedScanDayIsTheStoredDay() async throws {
        let h = try await empty(zone: try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati")))
        try await h.seed(F.scanRows(F.scanC, deviceId: F.active, day: F.dayA, takenAt: F.noonA,
                                    source: LabMarkerCsvImport.sourceId))
        let listed = await h.records.scans()
        XCTAssertEqual(listed.map(\.day), [F.dayA], "12:00 UTC is the 9th at UTC+14; the stored day stands")
    }

    /// Fault F9. Entry order A, C, B (§13.1).
    func testScansAreOrderedByInstantNotByEntryOrder() async throws {
        let h = try await empty()
        try await h.save(F.draftA)
        try await h.save(F.draftC)
        try await h.save(F.draftB)
        let listed = await h.records.scans()
        XCTAssertEqual(listed.map(\.id), [F.noonA, F.noonB, F.noonC].map { F.scanId(takenAt: $0) })
        XCTAssertEqual(listed.map(\.values), [F.scanA, F.scanB, F.scanC])

        // At one instant, then by source.
        try await h.seed(F.scanRows(F.scanC, deviceId: F.active, day: F.dayB, takenAt: F.noonB,
                                    source: LabMarkerCsvImport.sourceId))
        let withImport = await h.records.scans()
        XCTAssertEqual(withImport.count, 4)
        XCTAssertEqual(withImport.map(\.takenAt), [F.noonA, F.noonB, F.noonB, F.noonC])
        XCTAssertEqual(withImport[1].source, MarkerCatalog.scanSource, "\"body-scan\" sorts before \"lab-csv\"")
        XCTAssertEqual(withImport[2].source, LabMarkerCsvImport.sourceId)
    }

    /// Fault F18.
    func testManualWeighInIsNeverAScan() async throws {
        let h = try await empty()
        try await h.weighIns.save(weight: 101.0, waist: 99.0, unitSystem: .metric, takenAt: F.date(F.sevenA))
        try await h.seed([LabMarkerRow(id: "body_fat-\(F.sevenA)-0A1B2C3D", deviceId: F.active, markerKey: "body_fat",
                                       category: "bodyMeasurement", day: F.dayA, takenAt: F.sevenA, value: 31.0,
                                       valueText: nil, unit: "%", source: "manual", note: nil, referenceText: nil)])
        let none = await h.records.scans()
        XCTAssertEqual(none, [], "a weight and a body fat with no scan-only row are not a scan")

        try await h.save(F.draftA)
        let listed = await h.records.scans()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.values["weight"], 100.0, "the scan's own total, not the weigh-in")
        XCTAssertEqual(listed.first?.values["body_fat"], 30.0)
        XCTAssertEqual(listed.first?.rows["weight"]?.count, 1)
    }

    /// V9, fault F17: a row whose unit is not recognised, whose value is nil, or whose stored value
    /// is outside the range of §7.7 is unreadable: counted and named, never a number.
    func testUnreadableUnitIsCountedAndNeverShownAsANumber() async throws {
        let h = try await empty()
        try await h.save(F.draftA)
        let stored = try await rows(h, takenAt: F.noonA)
        var fat = try XCTUnwrap(stored.first { $0.markerKey == "scan_fat_mass" })
        fat.unit = "stone"
        var bmd = try XCTUnwrap(stored.first { $0.markerKey == "scan_bmd" })
        bmd.value = 9.0
        var trunk = try XCTUnwrap(stored.first { $0.markerKey == "scan_trunk_lean_mass" })
        trunk.value = nil
        try await h.seed([fat, bmd, trunk])

        let scan = try await h.firstScan()
        XCTAssertEqual(scan.unreadableKeys, ["scan_bmd", "scan_fat_mass", "scan_trunk_lean_mass"])
        for key in scan.unreadableKeys { XCTAssertNil(scan.values[key], key) }
        XCTAssertEqual(scan.note, F.noteA, "the note row is never unreadable")
        XCTAssertEqual(scan.values["scan_lean_mass"], 67.0)

        // A row in a recognised extended option reads in the stored unit.
        var lean = try XCTUnwrap(stored.first { $0.markerKey == "scan_lean_mass" })
        lean.value = 67_000
        lean.unit = "g"
        try await h.seed([lean])
        let reread = try await h.firstScan()
        XCTAssertEqual(try XCTUnwrap(reread.values["scan_lean_mass"]), 67.0, accuracy: 1e-9)
    }

    /// Fault F44: `scans()` is the one read other stages use and does not consult the flag. This
    /// test only reads the flag's key (it writes no setting of the host).
    func testScansReadDoesNotConsultTheFlag() async throws {
        let h = try await empty()
        try await h.save(F.draftA)
        let flagState = UserDefaults.standard.bool(forKey: BodyRecordSettings.enabledKey)
        let listed = await h.records.scans()
        XCTAssertEqual(listed.map(\.values), [F.scanA], "listed with the flag \(flagState ? "on" : "off")")
    }

    func testAFailedStoreReadGivesAnEmptyList() async throws {
        let h = try await BodyRecordHarness.make(suites: suites, onDiskIn: try directories.make())
        try await h.save(F.draftA)
        try await h.records.saveBenchmark(key: "bench_plank_s", value: 60, unit: "s",
                                          takenAt: F.date(F.jan06Noon), note: nil)
        try h.hideTheLabMarkerTable()
        let scans = await h.records.scans()
        XCTAssertEqual(scans, [])
        let readings = await h.records.benchmarkReadings(key: "bench_plank_s")
        XCTAssertEqual(readings, [])
        let keys = await h.records.benchmarkKeysPresent()
        XCTAssertEqual(keys, [])
    }

    // MARK: - Benchmarks

    func testBenchmarkSaveReadAndDelete() async throws {
        let h = try await seeded()
        let countsBefore = try await h.countsById()
        try await h.records.saveBenchmark(key: "bench_dead_hang_s", value: 20, unit: "s",
                                          takenAt: F.date(F.jan06Noon), note: nil)
        let middle = try await h.records.saveBenchmark(key: "bench_dead_hang_s", value: 30, unit: "s",
                                                       takenAt: F.date(F.feb17Noon), note: nil)
        try await h.records.saveBenchmark(key: "bench_dead_hang_s", value: 45, unit: "s",
                                          takenAt: F.date(F.mar31Noon), note: "Fixture bar")

        let readings = await h.records.benchmarkReadings(key: "bench_dead_hang_s")
        XCTAssertEqual(readings.map(\.value), [20, 30, 45], "oldest first")
        XCTAssertEqual(readings.map(\.note), [nil, nil, "Fixture bar"])
        for row in readings {
            XCTAssertEqual(row.category, "other")
            XCTAssertEqual(row.source, "manual")
            XCTAssertEqual(row.unit, "s")
            XCTAssertEqual(row.deviceId, F.active)
        }
        XCTAssertEqual(readings.map(\.day), ["2031-01-06", "2031-02-17", "2031-03-31"])
        XCTAssertEqual(middle.takenAt, F.feb17Noon)
        let keys = await h.records.benchmarkKeysPresent()
        XCTAssertEqual(keys, ["bench_dead_hang_s"])
        var expected = countsBefore
        expected[F.active, default: 0] += 3
        let countsAfter = try await h.countsById()
        XCTAssertEqual(countsAfter, expected)

        try await h.records.deleteBenchmark(middle)
        let left = await h.records.benchmarkReadings(key: "bench_dead_hang_s")
        XCTAssertEqual(left.map(\.value), [20, 45])
        expected[F.active, default: 0] -= 1
        let countsEnd = try await h.countsById()
        XCTAssertEqual(countsEnd, expected)
        try await assertBystandersUntouched(h)
    }

    /// §5.3: a custom benchmark's key is `customKey("bench " + name)`.
    func testCustomBenchmarkKeyHasThePrefix() async throws {
        let key = LabMarkerCsvImport.customKey("bench Fixture carry")
        XCTAssertEqual(key, F.customCarryKey)
        XCTAssertTrue(key.hasPrefix(MarkerCatalog.customBenchmarkPrefix))
        XCTAssertTrue(MarkerCatalog.isBenchmark(key))

        let h = try await empty()
        try await h.records.saveBenchmark(key: "bench_pushup_reps", value: 10, unit: "reps",
                                          takenAt: F.date(F.jan06Noon), note: nil)
        try await h.records.saveBenchmark(key: key, value: 60, unit: "s", takenAt: F.date(F.jan06Noon), note: nil)
        try await h.records.saveBenchmark(key: "bench_dead_hang_s", value: 20, unit: "s",
                                          takenAt: F.date(F.jan06Noon), note: nil)
        let keys = await h.records.benchmarkKeysPresent()
        XCTAssertEqual(keys, ["bench_pushup_reps", "bench_dead_hang_s", F.customCarryKey],
                       "catalogue order, then custom keys ascending")
        let custom = await h.records.benchmarkReadings(key: key)
        XCTAssertEqual(custom.map(\.category), ["other"])
    }

    /// §7.7: repetitions are whole numbers from 0 to 1000; holds are 0 to 86400 s; grip 1 to 150 kg.
    func testBenchmarkRepsMustBeWhole() async throws {
        let h = try await seeded()
        let before = try await h.everyRow()
        let refused: [(String, Double, String)] = [
            ("bench_pushup_reps", 12.5, "reps"), ("bench_pushup_reps", 1001, "reps"), ("bench_pushup_reps", -1, "reps"),
            ("bench_dead_hang_s", 86_401, "s"), ("bench_grip_kg", 0.5, "kg"), ("bench_grip_kg", 150.5, "kg"),
            ("bench_plank_s", .nan, "s"),
        ]
        for (key, value, unit) in refused {
            await assertRefusedWithSomeError("\(key) \(value)") {
                _ = try await h.records.saveBenchmark(key: key, value: value, unit: unit,
                                                      takenAt: F.date(F.jan06Noon), note: nil)
            }
        }
        let after = try await h.everyRow()
        XCTAssertEqual(after, before, "a refused benchmark writes nothing")

        try await h.records.saveBenchmark(key: "bench_pushup_reps", value: 12, unit: "reps",
                                          takenAt: F.date(F.jan06Noon), note: nil)
        try await h.records.saveBenchmark(key: "bench_pullup_reps", value: 0, unit: "reps",
                                          takenAt: F.date(F.jan06Noon), note: nil)
        try await h.records.saveBenchmark(key: "bench_wall_sit_s", value: 86_400, unit: "s",
                                          takenAt: F.date(F.jan06Noon), note: nil)
        let keys = await h.records.benchmarkKeysPresent()
        XCTAssertEqual(keys, ["bench_pushup_reps", "bench_pullup_reps", "bench_wall_sit_s"])
    }

    func testBenchmarkDeleteRemovesCopies() async throws {
        let h = try await seeded()
        let row = try await h.records.saveBenchmark(key: "bench_plank_s", value: 60, unit: "s",
                                                    takenAt: F.date(F.jan06Noon), note: nil)
        try await h.seed([copy(row, to: F.old, suffix: "C0FFEE04")])
        let listed = await h.records.benchmarkReadings(key: "bench_plank_s")
        XCTAssertEqual(listed.count, 1, "a copy is one reading")

        try await h.records.deleteBenchmark(try XCTUnwrap(listed.first))
        let left = try await h.everyRow().filter { $0.markerKey == "bench_plank_s" }
        XCTAssertEqual(left, [])
        try await assertBystandersUntouched(h)
    }

    func testBenchmarkUnderAnUnregisteredIdIsListed() async throws {
        let h = try await empty()
        try await h.seed([F.benchmarkRow("bench_pushup_reps", value: 14, unit: "reps", takenAt: F.feb17Noon,
                                         day: "2031-02-17", deviceId: F.gone)])
        let readings = await h.records.benchmarkReadings(key: "bench_pushup_reps")
        XCTAssertEqual(readings.map(\.value), [14])
        let keys = await h.records.benchmarkKeysPresent()
        XCTAssertEqual(keys, ["bench_pushup_reps"])
    }

    /// §9.1: conflicting benchmark rows are separate readings.
    func testConflictingBenchmarkRowsAreTwoReadings() async throws {
        let h = try await empty()
        try await h.seed([
            F.benchmarkRow("bench_pushup_reps", value: 14, unit: "reps", takenAt: F.feb17Noon, day: "2031-02-17",
                           deviceId: F.active),
            F.benchmarkRow("bench_pushup_reps", value: 15, unit: "reps", takenAt: F.feb17Noon, day: "2031-02-17",
                           deviceId: F.old, suffix: "BE4C0001"),
        ])
        let readings = await h.records.benchmarkReadings(key: "bench_pushup_reps")
        XCTAssertEqual(readings.compactMap(\.value).sorted(), [14, 15])
    }
}
