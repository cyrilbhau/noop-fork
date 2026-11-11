// Stage 4 (body record): regression tests for the confirmed review findings on the app side. Each
// test fails on the defect it names. Synthetic values only: the one Fixture Person of
// BodyRecordTestSupport.swift.

import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

@MainActor
final class Stage4ReviewFixTests: XCTestCase {
    private typealias F = BodyRecordFixture
    private let suites = BodyRecordSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    // MARK: - Editing a scan where the decimal separator is ","

    /// The prefill is written with the separator the sheet parses, so an unchanged figure is valid
    /// and Save stays enabled.
    func testScanEditPrefillUsesTheDeviceDecimalSeparator() async throws {
        let h = try await BodyRecordHarness.make(suites: suites)
        let a = try await h.save(F.draftA)
        let prefilled = BodyScanEntry(editing: a, unitSystem: .metric, decimalSeparator: ",")
        XCTAssertEqual(prefilled.texts["weight"], "100,0")
        XCTAssertEqual(prefilled.texts["scan_bmd"], "1,200")
        XCTAssertEqual(prefilled.texts["scan_visceral_fat_mass"], "1000")
        let state = BodyRecordPresenter.sheet(prefilled, unitSystem: .metric, decimalSeparator: ",",
                                              phase: .editing, weighInOutranks: false)
        XCTAssertTrue(state.canSave)
        XCTAssertEqual(state.draft, F.draftA)
        XCTAssertEqual(BodyScanEntry(editing: a, unitSystem: .metric).texts["weight"], "100.0",
                       "the default separator is unchanged")
    }

    /// A note-only edit in a comma locale saves, and every figure keeps its stored value.
    func testCommaLocaleNoteOnlyEditSavesAndKeepsTheStoredFigures() async throws {
        let h = try await BodyRecordHarness.make(suites: suites)
        let a = try await h.save(F.draftA)
        let model = BodyScanSheetModel(store: h.records, weighIns: h.weighIns, editing: a, unitSystem: .metric,
                                       decimalSeparator: ",", today: { "2031-06-04" })
        XCTAssertTrue(model.state.canSave, "an unchanged prefill is valid")
        model.setNote("Fixture note, edited")
        let saved = await model.save()
        let scan = try XCTUnwrap(saved, "the edit was not saved")
        XCTAssertEqual(scan.values, a.values)
        XCTAssertEqual(scan.note, "Fixture note, edited")
    }

    // MARK: - Lab Book editor, "Save and add another"

    private static let taken = Date(timeIntervalSince1970: 1_925_640_000)    // 2031-01-08 12:00 UTC

    private func entryDraft(_ key: String, text: String, takenAt: Date = taken) -> LabMarkerEntryDraft {
        var draft = LabMarkerEntryDraft(markerKey: key, reportUnitsEnabled: true, decimalSeparator: ".",
                                        takenAt: takenAt)
        draft.text = text
        return draft
    }

    /// L5: only the date carries over. The note and the reference range belong to the reading just
    /// saved, so the next marker starts without them.
    func testSaveAndAddAnotherKeepsOnlyTheDate() throws {
        let next = try XCTUnwrap(entryDraft("ldl", text: "2.6")
            .afterSaveAndAddAnother(markerName: "LDL cholesterol", saved: true, savedReadings: []))
        XCTAssertEqual(next.takenAt, Self.taken)
        XCTAssertEqual(next.note, "")
        XCTAssertEqual(next.referenceText, "")
        XCTAssertEqual(next.savedLine, "Saved LDL cholesterol.")
    }

    /// A failed save says so, keeps the reading as typed and never says "Saved".
    func testAFailedSaveAndAddAnotherIsNotReportedAsSaved() {
        XCTAssertNil(entryDraft("ldl", text: "2.6")
            .afterSaveAndAddAnother(markerName: "LDL cholesterol", saved: false, savedReadings: []))
        XCTAssertEqual(LabMarkerEntryDraft.saveFailedLine, "Couldn't save this reading. It is still here to try again.")
    }

    /// The same marker again at the kept instant replaces the first reading (one marker at one
    /// instant is one reading, ruling A10); the editor says so before and after the save.
    func testTheSameMarkerAgainAtTheKeptInstantIsAnnouncedAsAReplacement() throws {
        let first = entryDraft("haemoglobin", text: "140")
        XCTAssertNil(first.replaceNotice(markerName: "Haemoglobin", savedReadings: []))
        let next = try XCTUnwrap(first.afterSaveAndAddAnother(markerName: "Haemoglobin", saved: true,
                                                              savedReadings: []))
        let again = entryDraft("haemoglobin", text: "132", takenAt: next.takenAt)
        XCTAssertEqual(again.replaceNotice(markerName: "Haemoglobin", savedReadings: next.savedReadings),
                       "Haemoglobin is already saved at this time. Saving replaces it.")
        let after = try XCTUnwrap(again.afterSaveAndAddAnother(markerName: "Haemoglobin", saved: true,
                                                               savedReadings: next.savedReadings))
        XCTAssertEqual(after.savedLine, "Replaced Haemoglobin.")

        XCTAssertNil(entryDraft("ldl", text: "2.6", takenAt: next.takenAt)
            .replaceNotice(markerName: "LDL cholesterol", savedReadings: next.savedReadings), "another marker")
        XCTAssertNil(entryDraft("haemoglobin", text: "132", takenAt: next.takenAt.addingTimeInterval(60))
            .replaceNotice(markerName: "Haemoglobin", savedReadings: next.savedReadings), "another instant")
    }

    /// What the notice announces: two manual rows of one marker at one instant under one id are one
    /// reading, and the second save replaces the first.
    func testTheOwnerUpsertReplacesTheSameMarkerAtTheSameInstant() async throws {
        let h = try await BodyRecordHarness.make(suites: suites)
        func row(_ id: String, _ value: Double) -> LabMarkerRow {
            LabMarkerRow(id: id, deviceId: F.active, markerKey: "haemoglobin", category: "bloodPanel", day: F.dayA,
                         takenAt: F.noonA, value: value, valueText: nil, unit: "g/L", source: "manual",
                         note: nil, referenceText: nil)
        }
        try await h.store.upsertOwnerLabMarkers([row("haemoglobin-1925640000-AAAAAAAA", 140)])
        try await h.store.upsertOwnerLabMarkers([row("haemoglobin-1925640000-BBBBBBBB", 132)])
        let stored = try await h.everyRow().filter { $0.markerKey == "haemoglobin" }
        XCTAssertEqual(stored.map(\.value), [132])
    }

    // MARK: - Scan detail after an edit that moves the scan to another day

    /// An edit that changes the day moves the scan to a new instant and a new id. The detail follows
    /// the saved scan instead of taking the I7 "no longer exists" exit.
    func testScanDetailFollowsAnEditThatChangesTheDay() async throws {
        let h = try await BodyRecordHarness.make(suites: suites)
        let original = try await h.save(F.draftA)
        var moved = F.draftA
        moved.day = "2031-01-10"
        let saved = try await h.save(moved, replacing: original)
        XCTAssertNotEqual(saved.id, original.id)

        let model = BodyRecordModel(store: h.records, unitSystem: { .metric }, locale: { F.british })
        await model.load()
        XCTAssertNil(model.scan(id: original.id))
        XCTAssertNotNil(model.scan(id: saved.id))
        XCTAssertEqual(model.followedScanId(original.id, saved: saved), saved.id)
        XCTAssertEqual(model.followedScanId(original.id, editing: true), original.id,
                       "never leaves while the sheet is still open")
        XCTAssertNil(model.followedScanId(original.id), "a scan that is gone still leaves the stack (I7)")
    }

    /// The control: an edit that keeps the day keeps the id, and the detail stays on it.
    func testScanDetailStaysOnAnEditThatKeepsTheDay() async throws {
        let h = try await BodyRecordHarness.make(suites: suites)
        let original = try await h.save(F.draftA)
        var edited = F.draftA
        edited.note = "Fixture note, edited"
        let saved = try await h.save(edited, replacing: original)
        XCTAssertEqual(saved.id, original.id)
        let model = BodyRecordModel(store: h.records, unitSystem: { .metric }, locale: { F.british })
        await model.load()
        XCTAssertEqual(model.followedScanId(original.id, saved: saved), original.id)
        XCTAssertEqual(model.followedScanId(original.id), original.id)
    }

    // MARK: - Weigh-in history: a body-scan weight row with no scan

    /// §7.6: a `weight` row with no scan-only row at its instant is not a scan. With the body record
    /// on, the history lists it as an ordinary Lab Book row and opens nothing.
    func testOrphanedScanWeightRowStaysAnEditableLabBookRow() async throws {
        let h = try await BodyRecordHarness.make(suites: suites, today: F.dayA)
        let scan = try await h.save(F.draftA)
        for (key, rows) in scan.rows where MarkerCatalog.isScanOnlyMarker(key) {
            for row in rows { _ = try await h.store.deleteLabMarkerAndCopies(id: row.id) }
        }
        let remaining = await h.records.scans()
        XCTAssertTrue(remaining.isEmpty, "the scan no longer exists")

        let model = WeighInHistoryModel(weighIns: h.weighIns, provider: h.provider, unitSystem: { .metric },
                                        locale: { F.british }, today: { F.dayA }, bodyRecordEnabled: { true })
        await model.load()
        guard case .loaded(let history) = model.state else { return XCTFail("not loaded") }
        let row = try XCTUnwrap(history.rows.first { $0.weightRow?.source == MarkerCatalog.scanSource })
        XCTAssertNil(row.scanId)
        XCTAssertTrue(row.canEdit)
        XCTAssertTrue(row.canDelete)
        XCTAssertFalse(row.caption.contains("body scan"), row.caption)
    }

    /// The control: while the scan exists, its row still names and opens it.
    func testScanWeightRowStillOpensAnExistingScan() async throws {
        let h = try await BodyRecordHarness.make(suites: suites, today: F.dayA)
        let scan = try await h.save(F.draftA)
        let model = WeighInHistoryModel(weighIns: h.weighIns, provider: h.provider, unitSystem: { .metric },
                                        locale: { F.british }, today: { F.dayA }, bodyRecordEnabled: { true })
        await model.load()
        guard case .loaded(let history) = model.state else { return XCTFail("not loaded") }
        let row = try XCTUnwrap(history.rows.first { $0.weightRow?.source == MarkerCatalog.scanSource })
        XCTAssertEqual(row.scanId, scan.id)
        XCTAssertFalse(row.canEdit)
        XCTAssertTrue(row.caption.hasSuffix(" · Lab Book · body scan"), row.caption)
    }

    /// The presenter: with the stored scans' ids given, a body-scan row with no scan is an ordinary
    /// Lab Book row; without them (`nil`) it keeps the previous behaviour.
    func testHistoryOpensOnlyAScanThatExists() async throws {
        let h = try await BodyRecordHarness.make(suites: suites, today: F.dayA)
        let scan = try await h.save(F.draftA)
        let weights = await h.weighIns.readings(.weight)
        func scanRow(_ ids: Set<String>?) throws -> WeighInHistoryRow {
            let history = CutScorecardPresenter.history(weights: weights, waists: [], appleHealth: [],
                                                        unitSystem: .metric, locale: F.british, today: F.dayA,
                                                        bodyRecordEnabled: true, scanIds: ids)
            return try XCTUnwrap(history.rows.first { $0.weightRow?.source == MarkerCatalog.scanSource })
        }
        let orphan = try scanRow([])
        XCTAssertNil(orphan.scanId)
        XCTAssertTrue(orphan.canEdit)
        XCTAssertTrue(orphan.canDelete)
        XCTAssertFalse(orphan.caption.contains("body scan"), orphan.caption)
        XCTAssertEqual(try scanRow([scan.id]).scanId, scan.id)
        XCTAssertEqual(try scanRow(nil).scanId, scan.id)
    }

}
