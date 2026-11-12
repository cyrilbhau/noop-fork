// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/stage-4.md §6.2, §7.2, §9.3, §10.6 and §13.5 (4B, flag
// `noop.labReportUnitsEnabled`). The editor's draft logic is extracted to a testable type in
// Strand/Data/BodyRecordPresenter.swift so the view only binds (§12.4, ruling A2: work package 4-7
// creates the file with this type):
//
//     struct LabMarkerEntryDraft: Equatable {
//         init(markerKey: String, reportUnitsEnabled: Bool, decimalSeparator: Character, takenAt: Date)
//         let markerKey: String
//         var takenAt: Date
//         var unitLabel: String                   // starts at the stored unit
//         var text: String                        // starts empty
//         var unitOptions: [String] { get }       // MarkerUnitTable labels: legacy tier off, extended on
//         var storedUnit: String { get }          // the catalogue's canonical unit
//         var typedValue: Double? { get }         // off: Double(trimmed text), exactly today's parse;
//                                                 // on: MarkerUnitTable.parseEntry(text, decimalSeparator:)
//         var storedValue: Double? { get }        // MarkerUnitTable.toStored(typedValue, key:, from: unitLabel, tier:)
//         var annotation: String? { get }         // §9.3: on and a non-stored option: "<typed, trimmed,
//                                                 // separator written as "."> <label>"; else nil
//         var conversionLine: String? { get }     // on: L2 "Stored as <stored value> <stored unit>." at the
//                                                 // catalogue's decimals, L3 "Same number, stored as <unit>.";
//                                                 // nil for the stored unit. Off: not pinned (today's text)
//         var formulaLine: String? { get }        // on, `hba1c` in "%": "mmol/mol = (percent − 2.152) ÷ 0.09148"
//         var errorLine: String? { get }          // on, text not a number: "Use digits and one decimal separator."
//         var canSave: Bool { get }
//         var offersSaveAndAddAnother: Bool { get }   // exactly while the flag is on
//         func afterSaveAndAddAnother(markerName: String) -> (takenAt: Date, savedLine: String)
//         /// L6: "Entered as <valueText>" for a row with a numeric value and an annotation; else nil.
//         static func enteredAsLine(for row: LabMarkerRow) -> String?
//     }
//
// `MarkerUnitTable` (package 4-4a, in the tree) and `LabBookFormat.value(_:key:)` are used as they exist.
//
// Synthetic values only: the blood results of §13.5.

import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

final class LabReportUnitsEditorTests: XCTestCase {
    private let taken = Date(timeIntervalSince1970: 1_925_640_000)    // 2031-01-08 12:00 UTC

    private func draft(_ key: String, on: Bool = true, unit: String? = nil, text: String,
                       separator: Character = ".") -> LabMarkerEntryDraft {
        var draft = LabMarkerEntryDraft(markerKey: key, reportUnitsEnabled: on, decimalSeparator: separator,
                                        takenAt: taken)
        if let unit { draft.unitLabel = unit }
        draft.text = text
        return draft
    }

    /// L7, fault F27: with the flag off the editor is today's: the five-marker switcher, `Double(_:)`
    /// parsing, the old factors bit for bit, no annotation, no "Save and add another".
    func testFlagOffUsesTheLegacyTierAndPlainDoubleParsing() {
        for definition in MarkerCatalog.builtIn {
            let fresh = LabMarkerEntryDraft(markerKey: definition.key, reportUnitsEnabled: false, decimalSeparator: ".",
                                            takenAt: taken)
            XCTAssertEqual(fresh.unitOptions, MarkerUnitTable.options(for: definition.key, tier: .legacy).map(\.label),
                           definition.key)
            XCTAssertEqual(fresh.unitLabel, definition.canonicalUnit, definition.key)
            XCTAssertFalse(fresh.offersSaveAndAddAnother)
        }
        XCTAssertEqual(draft("hba1c", on: false, text: "36").unitOptions, ["mmol/mol"], "no percent entry while off")
        XCTAssertEqual(draft("ldl", on: false, text: "100").unitOptions, ["mmol/L", "mg/dL"])
        XCTAssertEqual(draft("weight", on: false, text: "100").unitOptions, ["kg"])

        let ldl = draft("ldl", on: false, unit: "mg/dL", text: "100")
        XCTAssertEqual(ldl.storedValue, 100 * (1.0 / 38.67), "bit-identical to the old factor")
        XCTAssertNil(ldl.annotation)

        // `Double(_:)`: an exponent parses, a decimal comma does not, whatever the device separator.
        XCTAssertEqual(draft("ferritin", on: false, text: "1e2").typedValue, 100)
        XCTAssertNil(draft("ferritin", on: false, text: "5,5", separator: ",").typedValue)
        XCTAssertEqual(draft("ferritin", on: false, text: " 80 ").typedValue, 80)
        XCTAssertNil(draft("ferritin", on: false, text: "80").errorLine, "no new message while off")
    }

    /// L1.
    func testFlagOnOffersEveryExtendedOption() {
        for definition in MarkerCatalog.builtIn {
            XCTAssertEqual(draft(definition.key, text: "").unitOptions,
                           MarkerUnitTable.options(for: definition.key, tier: .extended).map(\.label), definition.key)
        }
        XCTAssertEqual(draft("vitamin_b12", text: "").unitOptions, ["ng/L", "pg/mL", "pmol/L"])
        XCTAssertEqual(draft("hba1c", text: "").unitOptions, ["mmol/mol", "%"])
        XCTAssertEqual(draft("weight", text: "").unitOptions, ["kg", "lb"])
        XCTAssertEqual(draft("waist", text: "").unitOptions, ["cm", "in"])
        XCTAssertTrue(draft("ldl", text: "").offersSaveAndAddAnother)

        // The stricter parse (L4): the device separator, nothing that is not a finite number.
        let comma = draft("ferritin", text: "5,5", separator: ",")
        XCTAssertEqual(comma.typedValue, 5.5)
        for text in ["nan", "inf", "1e2", "5,5", "1,500", ""] {
            let rejected = draft("ferritin", text: text)
            XCTAssertNil(rejected.typedValue, text)
            XCTAssertFalse(rejected.canSave, text)
        }
        XCTAssertEqual(draft("ferritin", text: "nan").errorLine, "Use digits and one decimal separator.")
    }

    /// §13.5, L2 with the formula, fault F20.
    func testPercentHbA1cStoresMmolPerMolAndAnnotates() throws {
        let hba1c = draft("hba1c", unit: "%", text: "5.5")
        XCTAssertEqual(try XCTUnwrap(hba1c.storedValue), (5.5 - 2.152) / 0.09148, accuracy: 1e-12)
        XCTAssertEqual(hba1c.storedUnit, "mmol/mol")
        XCTAssertEqual(hba1c.annotation, "5.5 %")
        XCTAssertEqual(hba1c.conversionLine, "Stored as 37 mmol/mol.")
        XCTAssertEqual(hba1c.formulaLine, "mmol/mol = (percent − 2.152) ÷ 0.09148")
        XCTAssertTrue(hba1c.canSave)
        XCTAssertNil(draft("hba1c", text: "37").formulaLine, "no formula for the stored unit")
        XCTAssertNil(draft("ldl", unit: "mg/dL", text: "100").formulaLine, "a multiplication needs no formula")
    }

    /// §13.5 ferritin, L3.
    func testIdentityOptionAnnotatesAndStoresTheSameNumber() {
        let ferritin = draft("ferritin", unit: "ng/mL", text: "80")
        XCTAssertEqual(ferritin.storedValue, 80)
        XCTAssertEqual(ferritin.storedUnit, "µg/L")
        XCTAssertEqual(ferritin.annotation, "80 ng/mL", "the label is what the report printed")
        XCTAssertEqual(ferritin.conversionLine, "Same number, stored as µg/L.")
    }

    /// §13.5 TSH, fault F28.
    func testStoredUnitEntryLeavesValueTextNil() {
        let tsh = draft("tsh", text: "2.00")
        XCTAssertEqual(tsh.unitLabel, "mIU/L")
        XCTAssertEqual(tsh.storedValue, 2.0)
        XCTAssertNil(tsh.annotation)
        XCTAssertNil(tsh.conversionLine)
    }

    /// §9.3: trimmed, the separator written as ".", nothing else changed.
    func testAnnotationKeepsTheTypedDigits() {
        XCTAssertEqual(draft("hba1c", unit: "%", text: "5,50", separator: ",").annotation, "5.50 %")
        XCTAssertEqual(draft("ldl", unit: "mg/dL", text: " 100 ").annotation, "100 mg/dL")
        XCTAssertEqual(draft("ldl", unit: "mg/dL", text: "100.0").annotation, "100.0 mg/dL", "trailing zero kept")
        XCTAssertNil(draft("ldl", unit: "mg/dL", text: "abc").annotation, "nothing to annotate")
    }

    /// L5: the marker list again, the date kept, "Saved <marker name>."
    func testSaveAndAddAnotherKeepsTheDate() {
        let ldl = draft("ldl", unit: "mg/dL", text: "100")
        XCTAssertTrue(ldl.offersSaveAndAddAnother)
        let next = ldl.afterSaveAndAddAnother(markerName: "LDL cholesterol")
        XCTAssertEqual(next.takenAt, taken)
        XCTAssertEqual(next.savedLine, "Saved LDL cholesterol.")
        XCTAssertFalse(draft("ldl", on: false, text: "2.6").offersSaveAndAddAnother, "flag off: no second button")
    }

    /// Ruling O12, §7.2: the resolver's constants, so a weight typed in pounds stores the kilograms the
    /// resolver would compute.
    func testWeightTypedInPoundsStoresKilograms() {
        let weight = draft("weight", unit: "lb", text: "220.5")
        XCTAssertEqual(weight.storedValue, 220.5 / UnitFormatter.poundsPerKilogram)
        XCTAssertEqual(weight.storedUnit, "kg")
        XCTAssertEqual(weight.annotation, "220.5 lb")
        XCTAssertEqual(weight.conversionLine, "Stored as 100.0 kg.")
        XCTAssertEqual(draft("waist", unit: "in", text: "40").storedValue, 40 * UnitFormatter.centimetersPerInch)
        XCTAssertEqual(draft("height", unit: "in", text: "70").storedValue, 70 * UnitFormatter.centimetersPerInch)
    }

    /// §13.5, the dual-unit rows: stored, shown and annotated as the table gives them.
    func testFixtureBloodResultsTable() {
        let rows: [(String, String, String, String)] = [
            ("ldl", "100", "Stored as 2.59 mmol/L.", "100 mg/dL"),
            ("hdl", "50", "Stored as 1.29 mmol/L.", "50 mg/dL"),
            ("total_cholesterol", "200", "Stored as 5.17 mmol/L.", "200 mg/dL"),
            ("triglycerides", "150", "Stored as 1.69 mmol/L.", "150 mg/dL"),
            ("fasting_glucose", "90", "Stored as 5.0 mmol/L.", "90 mg/dL"),
        ]
        for (key, typed, line, annotation) in rows {
            let entry = draft(key, unit: "mg/dL", text: typed)
            XCTAssertEqual(entry.conversionLine, line, key)
            XCTAssertEqual(entry.annotation, annotation, key)
            XCTAssertEqual(entry.storedValue, MarkerUnitTable.toStored(Double(typed)!, key: key, from: "mg/dL", tier: .legacy),
                           "the extended tier keeps the legacy conversion: \(key)")
        }
    }

    /// L6: the history row of an annotated reading; an existing reader still takes `value` first.
    func testEnteredAsLineShowsTheAnnotationOfANumericRowOnly() {
        func row(value: Double?, valueText: String?) -> LabMarkerRow {
            LabMarkerRow(id: "hba1c-1925640000-0A1B2C3D", deviceId: "whoop-FIXTURE-NEW", markerKey: "hba1c",
                         category: "bloodPanel", day: "2031-01-08", takenAt: 1_925_640_000, value: value,
                         valueText: valueText, unit: "mmol/mol", source: "manual", note: nil, referenceText: nil)
        }
        XCTAssertEqual(LabMarkerEntryDraft.enteredAsLine(for: row(value: 36.598, valueText: "5.5 %")), "Entered as 5.5 %")
        XCTAssertNil(LabMarkerEntryDraft.enteredAsLine(for: row(value: 36.598, valueText: nil)))
        XCTAssertNil(LabMarkerEntryDraft.enteredAsLine(for: row(value: nil, valueText: "negative")),
                     "a qualitative reading shows its text as the value, not as an annotation")
        XCTAssertEqual(LabBookFormat.value(36.598, key: "hba1c"), "37", "the stored value and unit stay first")
    }
}
