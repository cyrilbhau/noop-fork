import Foundation
import StrandImport
import WhoopStore

// Stage 4 (body record and laboratory units), docs/personal/superapp/specs/stage-4.md §10 and §11.
// Every word and every figure the stage's screens draw is decided here; the views bind and decide
// nothing. Work package 4-7 (ruling A2) creates the file with the Lab Book editor's draft type.

// MARK: - 4B: the Lab Book editor's draft (§6.2, §7.2, §9.3, §10.6)

/// One reading as it is being typed in the Lab Book editor, extracted from the view so that its
/// rules are testable. With `reportUnitsEnabled` off it is today's editor: the legacy unit tier and
/// `Double(_:)` parsing, no annotation and no "Save and add another".
struct LabMarkerEntryDraft: Equatable {
    let markerKey: String
    let reportUnitsEnabled: Bool
    let decimalSeparator: Character
    var takenAt: Date
    /// The chosen unit option's label. Starts at the stored unit.
    var unitLabel: String
    var text: String = ""

    init(markerKey: String, reportUnitsEnabled: Bool, decimalSeparator: Character, takenAt: Date) {
        self.markerKey = markerKey
        self.reportUnitsEnabled = reportUnitsEnabled
        self.decimalSeparator = decimalSeparator
        self.takenAt = takenAt
        self.unitLabel = MarkerCatalog.definition(for: markerKey)?.canonicalUnit ?? ""
    }

    private var tier: MarkerUnitTier { reportUnitsEnabled ? .extended : .legacy }

    /// The unit labels the switcher offers, the stored unit first.
    var unitOptions: [String] { MarkerUnitTable.options(for: markerKey, tier: tier).map(\.label) }

    /// The catalogue's canonical unit: the unit every row of this marker is stored in.
    var storedUnit: String { MarkerCatalog.definition(for: markerKey)?.canonicalUnit ?? "" }

    /// The number typed. Off: exactly today's parse. On: digits and the device's decimal separator only.
    var typedValue: Double? {
        if reportUnitsEnabled { return MarkerUnitTable.parseEntry(text, decimalSeparator: decimalSeparator) }
        return Double(text.trimmingCharacters(in: .whitespaces))
    }

    /// The value a save stores, in the stored unit.
    var storedValue: Double? {
        typedValue.flatMap { MarkerUnitTable.toStored($0, key: markerKey, from: unitLabel, tier: tier) }
    }

    private var chosenOption: MarkerUnitOption? {
        MarkerUnitTable.options(for: markerKey, tier: tier).first { $0.label == unitLabel }
    }

    private var isStoredUnit: Bool { unitLabel == storedUnit }

    /// §9.3: what the report printed, kept in the row's `valueText` when another option than the
    /// stored unit is chosen: the typed text trimmed, its decimal separator written as ".", then the
    /// option's label. Nil for the stored unit, for text that is not a number, and while off.
    var annotation: String? {
        guard reportUnitsEnabled, !isStoredUnit, typedValue != nil else { return nil }
        var typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if decimalSeparator == "," { typed = typed.replacingOccurrences(of: ",", with: ".") }
        return "\(typed) \(unitLabel)"
    }

    /// L2 and L3: what a save will store. Nil for the stored unit and while off.
    var conversionLine: String? {
        guard reportUnitsEnabled, !isStoredUnit, let option = chosenOption else { return nil }
        if option.conversion == .identity {
            return String(localized: "Same number, stored as \(storedUnit).")
        }
        guard let stored = storedValue else { return nil }
        let shown = LabBookFormat.value(stored, key: markerKey)
        return String(localized: "Stored as \(shown) \(storedUnit).")
    }

    /// The HbA1c conversion is not a multiplication, so its formula is shown in words (§11).
    var formulaLine: String? {
        guard reportUnitsEnabled, !isStoredUnit, let option = chosenOption,
              case .affine = option.conversion else { return nil }
        return String(localized: "mmol/mol = (percent − 2.152) ÷ 0.09148")
    }

    /// L4. Nil while nothing is typed and while off.
    var errorLine: String? {
        guard reportUnitsEnabled,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              typedValue == nil else { return nil }
        return String(localized: "Use digits and one decimal separator.")
    }

    var canSave: Bool {
        guard let storedValue else { return false }
        return storedValue.isFinite
    }

    /// "Save and add another" exists exactly while the flag is on.
    var offersSaveAndAddAnother: Bool { reportUnitsEnabled }

    /// L5: the next reading keeps this one's date, and the editor says what was saved.
    func afterSaveAndAddAnother(markerName: String) -> (takenAt: Date, savedLine: String) {
        (takenAt, String(localized: "Saved \(markerName)."))
    }

    /// L6: the line under a history row whose numeric reading carries the typed value and unit.
    static func enteredAsLine(for row: LabMarkerRow) -> String? {
        guard row.value != nil, let typed = row.valueText, !typed.isEmpty else { return nil }
        return String(localized: "Entered as \(typed)")
    }
}

