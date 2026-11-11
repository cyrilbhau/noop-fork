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
}
