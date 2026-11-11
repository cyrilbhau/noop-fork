import Foundation
import StrandAnalytics
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

// MARK: - 4A: what the body-record screens show (§10.1 to §10.5)

/// What the body-record screen has read.
enum BodyRecordLoad: Equatable {
    case loading
    case storeUnavailable
    case loaded(scans: [BodyScan], benchmarks: [BenchmarkHistory])
}

/// One benchmark's readings, oldest first.
struct BenchmarkHistory: Equatable {
    let key: String
    let readings: [LabMarkerRow]
}

/// §10.1.
struct BodyRecordScreen: Equatable {
    var title: String
    /// G1.
    var isLoading: Bool
    /// G9.
    var storeMessage: String?
    /// G3, G4: the last scan of the §7.6 order.
    var latestScan: BodyScanCard?
    /// G4: "Compare with <date of the previous scan>".
    var compareTitle: String?
    /// G3.
    var addSecondScanText: String?
    /// G2.
    var scansEmptyText: String?
    var addScanTitle: String?
    /// G4: every scan, newest first; empty below two scans.
    var scanRows: [BodyScanListRow]
    /// G7, G8.
    var benchmarks: [BenchmarkRow]
    var benchmarksEmptyText: String?
    var addBenchmarkTitle: String?
    var openLabBookTitle: String?
}

struct BodyScanCard: Equatable {
    var scanId: String
    var dateText: String
    /// The whole-body figures entered and readable, in field order.
    var figures: [BodyScanFigure]
    /// "<value>% of legs lean mass", only when the figure has a value.
    var derivedLine: String?
    var importedText: String?
    var unreadableText: String?
    var conflictingText: String?
}

/// One figure as drawn: the number without its unit, and the unit.
struct BodyScanFigure: Equatable {
    var key: String
    var label: String
    var valueText: String
    var unit: String
    var caption: String?
}

struct BodyScanListRow: Equatable {
    var scanId: String
    var dateText: String
}

struct BenchmarkRow: Equatable {
    var key: String
    var name: String
    var valueText: String
    var unit: String
    var dateText: String
    /// Nil with one reading (G8).
    var sincePreviousText: String?
    var sinceFirstText: String?
}

struct BodyRecordHealthRow: Equatable {
    var title: String
    var detail: String
}

struct BodyRecordConfirmation: Equatable {
    var title: String
    var confirmTitle: String
    var cancelTitle: String
}

/// §10.3.
struct BodyScanDetail: Equatable {
    var scanId: String
    var dateText: String
    /// Report order; a section with nothing entered is absent.
    var sections: [BodyScanDetailSection]
    /// Empty when the scan has no arm or leg figure at all.
    var derived: [BodyScanDerivedRow]
    var note: String?
    var canEdit: Bool
    var canDelete: Bool
    var importedText: String?
    var unreadableText: String?
    var unreadableLabels: [String]
    var conflictingText: String?
    var conflictingLabels: [String]
    var openLabBookTitle: String?
}

struct BodyScanDetailSection: Equatable {
    var section: BodyScanSection
    var title: String
    var figures: [BodyScanFigure]
}

struct BodyScanDerivedRow: Equatable {
    var title: String
    var valueText: String
    var caption: String?
}

/// §10.4.
struct BodyScanComparison: Equatable {
    /// The smaller `takenAt` of the two chosen.
    var earlierScanId: String?
    var laterScanId: String?
    /// Never contains `laterScanId`.
    var earlierChoices: [BodyScanChoice]
    /// Never contains `earlierScanId`.
    var laterChoices: [BodyScanChoice]
    /// Field order; a field in neither scan has no row.
    var rows: [BodyScanComparisonRow]
    var derivedRows: [BodyScanComparisonRow]
    var emptyText: String?
    var addScanTitle: String?
    var oneScanText: String?
    /// The G5 and G5b lines of a scan in the table.
    var notes: [String]
}

struct BodyScanChoice: Equatable {
    var scanId: String
    var dateText: String
}

struct BodyScanComparisonRow: Equatable {
    /// The field key; the derived title for a derived row.
    var key: String
    var label: String
    /// The value, or "not entered" / the derived figure's "Not available" sentence.
    var earlierText: String
    var laterText: String
    var unit: String
    /// Nil unless both are present.
    var changeText: String?
    /// Nil for no change and for one side.
    var directionText: String?
    /// Nil where §7.7 hides it.
    var percentText: String?
}

enum BodyScanSheetPhase: Equatable { case editing, saving, occupied, failed }

/// What the scan sheet holds as typed.
struct BodyScanEntry: Equatable {
    var day: String
    /// Key -> typed text; absent or blank: not entered.
    var texts: [String: String] = [:]
    /// Key -> chosen entry unit; absent: the default.
    var units: [String: String] = [:]
    var note: String = ""

    init(day: String) {
        self.day = day
    }

    /// H9: the scan's figures prefilled in the display unit.
    init(editing scan: BodyScan, unitSystem: UnitSystem) {
        day = scan.day
        note = scan.note ?? ""
        for field in BodyScanField.all {
            guard let stored = scan.values[field.key] else { continue }
            let shown = BodyRecordPresenter.displayed(stored, field: field, unitSystem: unitSystem)
            texts[field.key] = shown.text
            units[field.key] = shown.unit
        }
    }
}

/// §10.2.
struct BodyScanSheetState: Equatable {
    var introText: String
    /// The five numeric sections of §7.7.
    var sections: [BodyScanSheetSection]
    /// What Save writes, in stored units; nil while Save is disabled.
    var draft: BodyScanDraft?
    var canSave: Bool
    /// H11.
    var controlsDisabled: Bool
    /// H7.
    var formMessage: String?
    /// H8.
    var weighInLine: String?
    /// H10, H12.
    var statusMessage: String?
}

struct BodyScanSheetSection: Equatable {
    var section: BodyScanSection
    var title: String
    var fields: [BodyScanSheetField]
    /// H6, under the affected section.
    var mismatchText: String?
}

struct BodyScanSheetField: Equatable {
    var key: String
    var label: String
    var unitOptions: [String]
    var unit: String
    var text: String
    /// H3.
    var storedAsText: String?
    /// H4, H5.
    var errorText: String?
    /// T-score and Z-score only: the decimal keypad has no minus key.
    var hasSignToggle: Bool
}

/// K1: one benchmark of the picker; a nil key is "Custom benchmark".
struct BenchmarkChoice: Equatable {
    var key: String?
    var name: String
}

/// What the benchmark sheet holds as typed.
struct BenchmarkEntry: Equatable {
    /// Nil: a custom benchmark.
    var key: String?
    var customName: String
    var customUnit: String
    var text: String

    init(key: String?, customName: String = "", customUnit: String = "reps", text: String = "") {
        self.key = key
        self.customName = customName
        self.customUnit = customUnit
        self.text = text
    }
}

struct BenchmarkEntryState: Equatable {
    /// The key a save writes; nil until a custom name is typed.
    var key: String?
    var unit: String
    var unitOptions: [String]
    /// K2.
    var acceptsDuration: Bool
    /// The stored value; nil while invalid or empty.
    var value: Double?
    /// K4.
    var errorText: String?
    var canSave: Bool
}

/// §10.5.
struct BenchmarkDetail: Equatable {
    var key: String
    var title: String
    /// Newest first.
    var rows: [BenchmarkReadingRow]
    /// K6.
    var oneReadingText: String?
}

struct BenchmarkReadingRow: Equatable {
    var rowId: String
    var valueText: String
    var unit: String
    var dateText: String
    var note: String?
    /// Against the previous (older) reading.
    var changeText: String?
}

/// Every word and figure of the body record. Pure: no store, no clock.
enum BodyRecordPresenter {

    // MARK: Shared wording

    static var title: String { String(localized: "Body record") }
    static var addScanTitle: String { String(localized: "Add a scan") }
    static var addBenchmarkTitle: String { String(localized: "Add a benchmark") }
    static var compareScansTitle: String { String(localized: "Compare scans") }
    static var openLabBookTitle: String { String(localized: "Open Lab Book") }
    static var editTitle: String { String(localized: "Edit") }
    static var deleteTitle: String { String(localized: "Delete") }
    static var saveTitle: String { String(localized: "Save") }
    static var cancelTitle: String { String(localized: "Cancel") }
    static var scansTitle: String { String(localized: "Scans") }
    static var benchmarksTitle: String { String(localized: "Benchmarks") }
    static var bloodResultsTitle: String { String(localized: "Blood results") }
    static var earlierTitle: String { String(localized: "Earlier") }
    static var laterTitle: String { String(localized: "Later") }
    static var changeTitle: String { String(localized: "Change") }
    static var conditionTitle: String { String(localized: "Condition (optional)") }
    static var conditionPrompt: String { String(localized: "e.g. surface height or grip") }
    static var customBenchmarkTitle: String { String(localized: "Custom benchmark") }
    static var sincePreviousTitle: String { String(localized: "Since the previous reading") }
    static var sinceFirstTitle: String { String(localized: "Since the first reading") }
    static var editScanTitle: String { String(localized: "Edit scan") }
    // §10.8 Settings card: "Report units in Lab Book" first, then "Body record".
    static var labUnitsSettingTitle: String { String(localized: "Report units in Lab Book") }
    static var labUnitsSettingDetail: String { String(localized: "Type blood results in the unit your report prints.") }
    static var bodyRecordSettingDetail: String { String(localized: "Scans and benchmarks, entered as printed and compared.") }
    static var settingsBlurb: String { String(localized: "Switching either off hides its screens and deletes nothing.") }
    static var dateTitle: String { String(localized: "Date taken") }
    static var signToggleTitle: String { String(localized: "Change sign") }
    static var valueTitle: String { String(localized: "Value") }
    static var nameTitle: String { String(localized: "Name") }
    static var unitTitle: String { String(localized: "Unit") }
    static var benchmarkTitle: String { String(localized: "Benchmark") }
    static var durationHint: String { String(localized: "Seconds, or minutes and seconds: 45 or 1:30") }
    /// The existing Lab Book note, reused (§11).
    static var screenNote: String {
        String(localized: "These are your own figures shown back to you. NOOP does not decide whether any value is normal, high or low.")
    }
    static var noScansText: String { String(localized: "No scans yet") }
    private static var notEnteredText: String { String(localized: "not entered") }
    private static var rmrCaption: String { String(localized: "Laboratory estimate. Not used by NOOP's calorie figures.") }
    private static var importedShort: String { String(localized: "Imported from CSV") }

    // MARK: §10.1 Body record screen

    static func screen(_ load: BodyRecordLoad, unitSystem: UnitSystem, locale: Locale) -> BodyRecordScreen {
        var screen = BodyRecordScreen(title: title, isLoading: false, storeMessage: nil, latestScan: nil,
                                      compareTitle: nil, addSecondScanText: nil, scansEmptyText: nil,
                                      addScanTitle: nil, scanRows: [], benchmarks: [], benchmarksEmptyText: nil,
                                      addBenchmarkTitle: nil, openLabBookTitle: nil)
        switch load {
        case .loading:
            screen.isLoading = true
        case .storeUnavailable:
            screen.storeMessage = String(localized: "Couldn't open the local store.")
        case .loaded(let scans, let benchmarks):
            screen.addScanTitle = addScanTitle
            screen.addBenchmarkTitle = addBenchmarkTitle
            screen.openLabBookTitle = openLabBookTitle
            if let latest = scans.last {
                screen.latestScan = card(latest, unitSystem: unitSystem, locale: locale)
            } else {
                screen.scansEmptyText = noScansText
            }
            if scans.count == 1 { screen.addSecondScanText = String(localized: "Add a second scan to compare") }
            if scans.count >= 2 {
                let previous = dateText(scans[scans.count - 2].day, locale: locale)
                screen.compareTitle = String(localized: "Compare with \(previous)")
                screen.scanRows = scans.reversed().map {
                    BodyScanListRow(scanId: $0.id, dateText: dateText($0.day, locale: locale))
                }
            }
            screen.benchmarks = benchmarks.compactMap { benchmarkRow($0, unitSystem: unitSystem, locale: locale) }
            if screen.benchmarks.isEmpty { screen.benchmarksEmptyText = String(localized: "No benchmarks yet") }
        }
        return screen
    }

    /// The Health tab's row (§10.1): present only while the flag is on.
    static func healthRow(enabled: Bool, scans: [BodyScan], locale: Locale) -> BodyRecordHealthRow? {
        guard enabled else { return nil }
        guard let last = scans.last else { return BodyRecordHealthRow(title: title, detail: noScansText) }
        let date = dateText(last.day, locale: locale)
        return BodyRecordHealthRow(title: title, detail: String(localized: "Last scan \(date)"))
    }

    private static func card(_ scan: BodyScan, unitSystem: UnitSystem, locale: Locale) -> BodyScanCard {
        let figures = BodyScanField.all.filter { $0.section == .wholeBody }
            .compactMap { figure($0, scan: scan, unitSystem: unitSystem) }
        var derivedLine: String?
        if case .value(let percent) = derivation(scan).armToLegLeanPercent {
            derivedLine = armsToLegsText(percent)
        }
        return BodyScanCard(scanId: scan.id, dateText: dateText(scan.day, locale: locale), figures: figures,
                            derivedLine: derivedLine,
                            importedText: scan.source == MarkerCatalog.scanSource ? nil : importedShort,
                            unreadableText: unreadableLine(scan), conflictingText: conflictingLine(scan))
    }

    // MARK: §10.3 Scan detail

    static func detail(_ scan: BodyScan, unitSystem: UnitSystem, locale: Locale) -> BodyScanDetail {
        var sections: [BodyScanDetailSection] = []
        for section in BodyScanSection.allCases where section != .note {
            let figures = BodyScanField.all.filter { $0.section == section }
                .compactMap { figure($0, scan: scan, unitSystem: unitSystem) }
            if !figures.isEmpty {
                sections.append(BodyScanDetailSection(section: section, title: section.title, figures: figures))
            }
        }
        let imported = scan.source != MarkerCatalog.scanSource
        let unreadable = unreadableLine(scan)
        let conflicting = conflictingLine(scan)
        return BodyScanDetail(
            scanId: scan.id, dateText: dateText(scan.day, locale: locale), sections: sections,
            derived: derivedRows(scan), note: scan.note, canEdit: scan.isEditable, canDelete: scan.isDeletable,
            importedText: imported ? String(localized: "Imported from CSV. Edit or delete its readings in Lab Book.") : nil,
            unreadableText: unreadable, unreadableLabels: labels(scan.unreadableKeys),
            conflictingText: conflicting, conflictingLabels: labels(scan.conflictingKeys),
            openLabBookTitle: imported || unreadable != nil || conflicting != nil ? openLabBookTitle : nil)
    }

    // MARK: §10.4 Scan comparison

    static func comparisonUsesStackedRows(accessibilityTextSize: Bool) -> Bool { accessibilityTextSize }

    static func comparison(scans: [BodyScan], earlierId: String?, laterId: String?,
                           unitSystem: UnitSystem, locale: Locale) -> BodyScanComparison {
        var result = BodyScanComparison(earlierScanId: nil, laterScanId: nil, earlierChoices: [], laterChoices: [],
                                        rows: [], derivedRows: [], emptyText: nil, addScanTitle: nil,
                                        oneScanText: nil, notes: [])
        guard !scans.isEmpty else {
            result.emptyText = noScansText
            result.addScanTitle = addScanTitle
            return result
        }
        let ordered = scans.sorted { ($0.takenAt, $0.source) < ($1.takenAt, $1.source) }
        if ordered.count == 1 {
            let only = ordered[0]
            result.earlierScanId = only.id
            result.oneScanText = String(localized: "One scan so far. A second scan makes a comparison.")
            result.rows = comparisonRows(earlier: only, later: nil, unitSystem: unitSystem)
            result.derivedRows = derivedComparisonRows(earlier: only, later: nil)
            result.notes = notes(only)
            return result
        }
        // Nil ids mean the two newest; the same scan is never both.
        var first = ordered.first { $0.id == earlierId }
        var second = ordered.first { $0.id == laterId && $0.id != first?.id }
        if first == nil { first = ordered.last { $0.id != second?.id } }
        if second == nil { second = ordered.last { $0.id != first?.id } }
        guard var earlier = first, var later = second else { return result }
        if (later.takenAt, later.source) < (earlier.takenAt, earlier.source) { swap(&earlier, &later) }
        result.earlierScanId = earlier.id
        result.laterScanId = later.id
        result.earlierChoices = ordered.filter { $0.id != later.id }
            .map { BodyScanChoice(scanId: $0.id, dateText: dateText($0.day, locale: locale)) }
        result.laterChoices = ordered.filter { $0.id != earlier.id }
            .map { BodyScanChoice(scanId: $0.id, dateText: dateText($0.day, locale: locale)) }
        result.rows = comparisonRows(earlier: earlier, later: later, unitSystem: unitSystem)
        result.derivedRows = derivedComparisonRows(earlier: earlier, later: later)
        result.notes = notes(earlier) + notes(later)
        return result
    }

    private static func comparisonRows(earlier: BodyScan, later: BodyScan?,
                                       unitSystem: UnitSystem) -> [BodyScanComparisonRow] {
        BodyScanField.all.compactMap { field in
            guard field.range != nil else { return nil }
            let a = earlier.values[field.key].map { displayed($0, field: field, unitSystem: unitSystem) }
            let b = later?.values[field.key].map { displayed($0, field: field, unitSystem: unitSystem) }
            guard a != nil || b != nil else { return nil }
            let unit = (a ?? b)?.unit ?? field.storedUnit
            var row = BodyScanComparisonRow(key: field.key, label: field.label,
                                            earlierText: a?.text ?? notEnteredText,
                                            laterText: b?.text ?? notEnteredText, unit: unit, changeText: nil,
                                            directionText: nil, percentText: nil)
            if let a, let b {
                let change = BodyRecordComparison.compare(
                    earlier: BodyRecordReading(value: a.value, decimals: field.decimals),
                    later: BodyRecordReading(value: b.value, decimals: field.decimals))
                if case .both(let delta) = change {
                    let changeUnit = unit == "%" ? String(localized: "points") : unit
                    fill(&row, delta: delta, decimals: field.decimals, unit: changeUnit,
                         showsPercent: field.showsPercentChange)
                }
            }
            return row
        }
    }

    private static func derivedComparisonRows(earlier: BodyScan, later: BodyScan?) -> [BodyScanComparisonRow] {
        guard hasArmOrLegFigure(earlier) || later.map(hasArmOrLegFigure) == true else { return [] }
        let a = derivation(earlier)
        let b = later.map(derivation)
        func text(_ value: BodyScanDerivedValue?, _ words: (Double) -> String, missing: String) -> String {
            guard let value else { return notEnteredText }
            return derivedText(value, words, missing: missing)
        }
        let armsMissing = String(localized: "Not available. Enter arms and legs lean mass.")
        let sidesMissing = String(localized: "Not available. Enter both sides.")
        var ratio = BodyScanComparisonRow(
            key: armsToLegsTitle, label: armsToLegsTitle,
            earlierText: text(a.armToLegLeanPercent, armsToLegsText, missing: armsMissing),
            laterText: text(b?.armToLegLeanPercent, armsToLegsText, missing: armsMissing),
            unit: "%", changeText: nil, directionText: nil, percentText: nil)
        if case .value(let x) = a.armToLegLeanPercent, case .value(let y)? = b?.armToLegLeanPercent,
           case .both(let delta) = BodyRecordComparison.compare(earlier: BodyRecordReading(value: x, decimals: 1),
                                                                later: BodyRecordReading(value: y, decimals: 1)) {
            fill(&ratio, delta: delta, decimals: 1, unit: String(localized: "points"), showsPercent: false)
        }
        let arms = BodyScanComparisonRow(
            key: armSidesTitle, label: armSidesTitle,
            earlierText: text(a.armSideDifferencePercent, sideText, missing: sidesMissing),
            laterText: text(b?.armSideDifferencePercent, sideText, missing: sidesMissing),
            unit: "%", changeText: nil, directionText: nil, percentText: nil)
        let legs = BodyScanComparisonRow(
            key: legSidesTitle, label: legSidesTitle,
            earlierText: text(a.legSideDifferencePercent, sideText, missing: sidesMissing),
            laterText: text(b?.legSideDifferencePercent, sideText, missing: sidesMissing),
            unit: "%", changeText: nil, directionText: nil, percentText: nil)
        return [ratio, arms, legs]
    }

    /// A change with its sign and unit, the direction word, and the percentage where it is shown.
    private static func fill(_ row: inout BodyScanComparisonRow, delta: BodyRecordDelta, decimals: Int,
                             unit: String, showsPercent: Bool) {
        guard delta.direction != .same else {
            row.changeText = String(localized: "No change")
            return
        }
        row.changeText = "\(signed(delta.delta, decimals: decimals)) \(unit)"
        row.directionText = delta.direction == .up ? String(localized: "up") : String(localized: "down")
        if showsPercent, let percent = delta.percent {
            row.percentText = "\(signed(percent, decimals: 1))%"
        }
    }

    private static func notes(_ scan: BodyScan) -> [String] {
        [unreadableLine(scan), conflictingLine(scan)].compactMap { $0 }
    }

    // MARK: §10.2 Scan sheet

    static func sheet(_ entry: BodyScanEntry, unitSystem: UnitSystem, decimalSeparator: Character,
                      phase: BodyScanSheetPhase, weighInOutranks: Bool) -> BodyScanSheetState {
        let parsed = parse(entry, unitSystem: unitSystem, decimalSeparator: decimalSeparator)
        let mismatched = Set(BodyScanChecks.mismatches(checkInput(parsed.values)).map(section(of:)))
        let sections = BodyScanSection.allCases.filter { $0 != .note }.map { section in
            BodyScanSheetSection(
                section: section, title: section.title,
                fields: parsed.fields.filter { BodyScanField.field(for: $0.key)?.section == section },
                mismatchText: mismatched.contains(section)
                    ? String(localized: "These figures do not add up as typed. Check them against the report.")
                    : nil)
        }
        let hasScanFigure = parsed.values.keys.contains { MarkerCatalog.isScanOnlyMarker($0) }
        let typedScanFigure = entry.texts.contains {
            MarkerCatalog.isScanOnlyMarker($0.key) && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let typedAnything = entry.texts.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let note = entry.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = !parsed.hasError && hasScanFigure && note.count <= BodyScanField.noteMaxLength
        let canSave = valid && phase != .saving
        var status: String?
        switch phase {
        case .occupied: status = String(localized: "Another scan is already recorded at that time.")
        case .failed: status = String(localized: "Couldn't save the scan. Nothing was changed.")
        case .editing, .saving: status = nil
        }
        return BodyScanSheetState(
            introText: String(localized: "Type the figures as your report prints them. Leave out anything it does not give."),
            sections: sections,
            draft: canSave ? BodyScanDraft(day: entry.day, values: parsed.values, note: note.isEmpty ? nil : note) : nil,
            canSave: canSave, controlsDisabled: phase == .saving,
            formMessage: typedAnything && !typedScanFigure
                ? String(localized: "Add at least one scan figure besides total mass.") : nil,
            weighInLine: weighInOutranks && parsed.values[MarkerCatalog.scanTotalMassKey] != nil
                ? String(localized: "You have a weigh-in this week. It stays this week's weight; the scan keeps its own total.")
                : nil,
            statusMessage: status)
    }

    /// The total mass typed in the sheet, in kilograms, when it is a valid figure. The sheet model
    /// asks the resolver about it (H8).
    static func typedTotalMassKg(_ entry: BodyScanEntry, unitSystem: UnitSystem,
                                 decimalSeparator: Character) -> Double? {
        parse(entry, unitSystem: unitSystem, decimalSeparator: decimalSeparator)
            .values[MarkerCatalog.scanTotalMassKey]
    }

    static func scanDeleteConfirmation() -> BodyRecordConfirmation {
        BodyRecordConfirmation(title: String(localized: "Delete this scan? Its total mass is removed from your weight history too."),
                               confirmTitle: deleteTitle, cancelTitle: cancelTitle)
    }

    /// The default entry unit of a field: masses stored in kilograms follow the unit system.
    static func defaultUnit(_ field: BodyScanField, unitSystem: UnitSystem) -> String {
        if field.storedUnit == "kg", unitSystem == .imperial, field.entryUnits.contains("lb") { return "lb" }
        return field.storedUnit
    }

    private struct ParsedEntry {
        var fields: [BodyScanSheetField] = []
        var values: [String: Double] = [:]
        var hasError = false
    }

    private static func parse(_ entry: BodyScanEntry, unitSystem: UnitSystem,
                              decimalSeparator: Character) -> ParsedEntry {
        var out = ParsedEntry()
        for field in BodyScanField.all where field.range != nil {
            let chosen = entry.units[field.key].flatMap { field.entryUnits.contains($0) ? $0 : nil }
                ?? defaultUnit(field, unitSystem: unitSystem)
            let text = entry.texts[field.key] ?? ""
            var sheetField = BodyScanSheetField(
                key: field.key, label: field.label, unitOptions: field.entryUnits, unit: chosen, text: text,
                storedAsText: nil, errorText: nil,
                hasSignToggle: field.key == BodyScanKeys.tScore || field.key == BodyScanKeys.zScore)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty, let range = field.range {
                if let typed = MarkerUnitTable.parseEntry(text, decimalSeparator: decimalSeparator),
                   let stored = chosen == field.storedUnit
                    ? typed : MarkerUnitTable.toStored(typed, key: field.key, from: chosen, tier: .extended) {
                    if range.contains(stored) {
                        out.values[field.key] = stored
                        if chosen != field.storedUnit {
                            let shown = LabBookFormat.value(stored, key: field.key)
                            sheetField.storedAsText = String(localized: "Stored as \(shown) \(field.storedUnit).")
                        }
                    } else {
                        sheetField.errorText = rangeMessage(range, key: field.key, unit: chosen)
                    }
                } else {
                    sheetField.errorText = String(localized: "Use digits and one decimal separator.")
                }
                if sheetField.errorText != nil { out.hasError = true }
            }
            out.fields.append(sheetField)
        }
        return out
    }

    /// "Enter a value between <low> and <high> <unit>." in the unit the figure is typed in.
    private static func rangeMessage(_ range: ClosedRange<Double>, key: String, unit: String) -> String {
        let low = MarkerUnitTable.fromStored(range.lowerBound, key: key, to: unit, tier: .extended) ?? range.lowerBound
        let high = MarkerUnitTable.fromStored(range.upperBound, key: key, to: unit, tier: .extended) ?? range.upperBound
        return rangeMessage(low: LabBookFormat.plain(low), high: LabBookFormat.plain(high), unit: unit)
    }

    private static func rangeMessage(low: String, high: String, unit: String) -> String {
        String(localized: "Enter a value between \(low) and \(high) \(unit).")
    }

    private static func checkInput(_ values: [String: Double]) -> BodyScanCheckInput {
        var input = BodyScanCheckInput()
        input.totalMass = values[MarkerCatalog.scanTotalMassKey]
        input.fatMass = values[BodyScanKeys.fatMass]
        input.leanMass = values[BodyScanKeys.leanMass]
        input.boneMass = values[BodyScanKeys.boneMass]
        input.fatFreeMass = values[BodyScanKeys.fatFreeMass]
        input.bodyFatPercent = values[MarkerCatalog.scanBodyFatKey]
        input.armsLean = values[BodyScanKeys.armsLean]
        input.armLeftLean = values[BodyScanKeys.armLeftLean]
        input.armRightLean = values[BodyScanKeys.armRightLean]
        input.legsLean = values[BodyScanKeys.legsLean]
        input.legLeftLean = values[BodyScanKeys.legLeftLean]
        input.legRightLean = values[BodyScanKeys.legRightLean]
        input.androidFatPercent = values[BodyScanKeys.androidFat]
        input.gynoidFatPercent = values[BodyScanKeys.gynoidFat]
        input.androidGynoidRatio = values[BodyScanKeys.androidGynoidRatio]
        return input
    }

    private static func section(of check: BodyScanCheck) -> BodyScanSection {
        switch check {
        case .totalIsFatLeanBone, .fatFreeIsLeanBone, .bodyFatPercentIsFatShare: return .wholeBody
        case .armsIsLeftPlusRight, .legsIsLeftPlusRight: return .leanMassByRegion
        case .ratioIsAndroidOverGynoid: return .fatDistribution
        }
    }

    // MARK: §8.4 H8

    /// H8. True exactly when the resolver, given the weigh-in rows and the weight row this draft
    /// would write, holds no entry for that row as of `today`. One call to the resolver's `series`;
    /// no rule of its own.
    static func weighInOutranksDraft(draftRow: LabMarkerRow, weighInRows: [LabMarkerRow], today: String) -> Bool {
        let candidates = BodyMeasurementCandidates(labBook: weighInRows + [draftRow], appleHealth: [],
                                                   profileValue: 0, profileIsSet: false)
        let series = BodyMeasurementResolver.series(.weight, candidates: candidates, policy: .unified, asOf: today)
        return !series.contains { $0.rowId == draftRow.id }
    }

    // MARK: §10.5 Benchmarks

    static let customBenchmarkUnits: [String] = BenchmarkRules.customUnits

    static func benchmarkChoices() -> [BenchmarkChoice] {
        MarkerCatalog.bodyRecord.filter { MarkerCatalog.isBenchmark($0.key) }
            .map { BenchmarkChoice(key: $0.key, name: $0.displayName) }
            + [BenchmarkChoice(key: nil, name: customBenchmarkTitle)]
    }

    static func benchmarkEntry(_ entry: BenchmarkEntry, decimalSeparator: Character) -> BenchmarkEntryState {
        let custom = entry.key == nil
        let name = entry.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = entry.key ?? (name.isEmpty ? nil : LabMarkerCsvImport.customKey("bench " + name))
        let unit = entry.key.flatMap { MarkerCatalog.definition(for: $0)?.canonicalUnit } ?? entry.customUnit
        var state = BenchmarkEntryState(key: key, unit: unit, unitOptions: custom ? customBenchmarkUnits : [unit],
                                        acceptsDuration: BenchmarkRules.acceptsDuration(unit: unit), value: nil,
                                        errorText: nil, canSave: false)
        let text = entry.text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return state }
        let parsed = state.acceptsDuration
            ? parseDuration(text, decimalSeparator: decimalSeparator)
            : MarkerUnitTable.parseEntry(text, decimalSeparator: decimalSeparator)
        guard let value = parsed else {
            state.errorText = String(localized: "Use digits and one decimal separator.")
            return state
        }
        if BenchmarkRules.requiresWholeNumber(unit: unit), value != value.rounded() {
            state.errorText = String(localized: "Enter a whole number.")
            return state
        }
        guard let range = BenchmarkRules.range(unit: unit) else { return state }
        guard range.contains(value) else {
            state.errorText = rangeMessage(low: LabBookFormat.plain(range.lowerBound),
                                           high: LabBookFormat.plain(range.upperBound), unit: unit)
            return state
        }
        state.value = value
        state.canSave = key != nil
        return state
    }

    /// K2: "45" is 45 s, "1:30" is 90 s; nil for anything else, and for 60 or more seconds after a colon.
    static func parseDuration(_ text: String, decimalSeparator: Character) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(":") else {
            return MarkerUnitTable.parseEntry(trimmed, decimalSeparator: decimalSeparator)
        }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let minutes = wholeDigits(parts[0]), let seconds = wholeDigits(parts[1]),
              parts[1].count <= 2, seconds < 60 else { return nil }
        return Double(minutes * 60 + seconds)
    }

    private static func wholeDigits(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.count <= 6, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }

    static func benchmarkDetail(_ history: BenchmarkHistory, unitSystem: UnitSystem,
                                locale: Locale) -> BenchmarkDetail {
        let readings = history.readings.filter { $0.value?.isFinite == true }
        var rows: [BenchmarkReadingRow] = []
        for (index, row) in readings.enumerated() {
            let shown = benchmarkValue(row, key: history.key, unitSystem: unitSystem)
            var change: String?
            if index > 0 {
                change = changeText(from: readings[index - 1], to: row, key: history.key, unitSystem: unitSystem)
            }
            rows.append(BenchmarkReadingRow(rowId: row.id, valueText: shown.text, unit: shown.unit,
                                            dateText: dateText(row.day, locale: locale), note: row.note,
                                            changeText: change))
        }
        return BenchmarkDetail(key: history.key, title: benchmarkName(history.key), rows: rows.reversed(),
                               oneReadingText: rows.count == 1 ? String(localized: "One reading so far.") : nil)
    }

    static func benchmarkDeleteConfirmation() -> BodyRecordConfirmation {
        BodyRecordConfirmation(title: String(localized: "Delete this reading?"), confirmTitle: deleteTitle,
                               cancelTitle: cancelTitle)
    }

    /// A benchmark's name: the catalogue's, or for a custom one the name it was saved under.
    static func benchmarkName(_ key: String) -> String {
        if let definition = MarkerCatalog.definition(for: key) { return definition.displayName }
        let words = key.hasPrefix(MarkerCatalog.customBenchmarkPrefix)
            ? String(key.dropFirst(MarkerCatalog.customBenchmarkPrefix.count)) : key
        let spaced = words.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    private static func benchmarkRow(_ history: BenchmarkHistory, unitSystem: UnitSystem,
                                     locale: Locale) -> BenchmarkRow? {
        let readings = history.readings.filter { $0.value?.isFinite == true }
        guard let latest = readings.last else { return nil }
        let shown = benchmarkValue(latest, key: history.key, unitSystem: unitSystem)
        var row = BenchmarkRow(key: history.key, name: benchmarkName(history.key), valueText: shown.text,
                               unit: shown.unit, dateText: dateText(latest.day, locale: locale),
                               sincePreviousText: nil, sinceFirstText: nil)
        if readings.count >= 2 {
            row.sincePreviousText = changeText(from: readings[readings.count - 2], to: latest, key: history.key,
                                               unitSystem: unitSystem)
            row.sinceFirstText = changeText(from: readings[0], to: latest, key: history.key, unitSystem: unitSystem)
        }
        return row
    }

    private static func benchmarkDecimals(_ key: String, unit: String) -> Int {
        MarkerCatalog.definition(for: key)?.decimals ?? (unit == "kg" ? 1 : 0)
    }

    private static func benchmarkValue(_ row: LabMarkerRow, key: String,
                                       unitSystem: UnitSystem) -> (text: String, value: Double, unit: String) {
        let stored = row.value ?? 0
        if row.unit == "kg", unitSystem == .imperial {
            let pounds = stored * UnitFormatter.poundsPerKilogram
            return (BodyRecordMath.displayString(pounds, decimals: benchmarkDecimals(key, unit: row.unit)), pounds, "lb")
        }
        return (BodyRecordMath.displayString(stored, decimals: benchmarkDecimals(key, unit: row.unit)), stored, row.unit)
    }

    private static func changeText(from older: LabMarkerRow, to newer: LabMarkerRow, key: String,
                                   unitSystem: UnitSystem) -> String? {
        let a = benchmarkValue(older, key: key, unitSystem: unitSystem)
        let b = benchmarkValue(newer, key: key, unitSystem: unitSystem)
        guard a.unit == b.unit else { return nil }
        let decimals = benchmarkDecimals(key, unit: newer.unit)
        guard case .both(let delta) = BodyRecordComparison.compare(
            earlier: BodyRecordReading(value: a.value, decimals: decimals),
            later: BodyRecordReading(value: b.value, decimals: decimals)) else { return nil }
        if delta.direction == .same { return String(localized: "No change") }
        return "\(signed(delta.delta, decimals: decimals)) \(b.unit)"
    }

    // MARK: Figures and derived values

    /// A stored value in the display unit: masses stored in kilograms follow the unit system;
    /// everything else stays in its stored unit (§7.7). The text is the catalogue's decimals.
    static func displayed(_ stored: Double, field: BodyScanField,
                          unitSystem: UnitSystem) -> (text: String, value: Double, unit: String) {
        if field.storedUnit == "kg", unitSystem == .imperial {
            let pounds = stored * UnitFormatter.poundsPerKilogram
            return (LabBookFormat.value(pounds, key: field.key), pounds, "lb")
        }
        return (LabBookFormat.value(stored, key: field.key), stored, field.storedUnit)
    }

    private static func figure(_ field: BodyScanField, scan: BodyScan, unitSystem: UnitSystem) -> BodyScanFigure? {
        guard field.range != nil, let stored = scan.values[field.key] else { return nil }
        let shown = displayed(stored, field: field, unitSystem: unitSystem)
        return BodyScanFigure(key: field.key, label: field.label, valueText: shown.text, unit: shown.unit,
                              caption: field.key == BodyScanKeys.rmrEstimate ? rmrCaption : nil)
    }

    private static func derivation(_ scan: BodyScan) -> BodyScanDerived {
        BodyScanDerivation.derive(BodyScanComponents(
            armsLean: scan.values[BodyScanKeys.armsLean], armLeftLean: scan.values[BodyScanKeys.armLeftLean],
            armRightLean: scan.values[BodyScanKeys.armRightLean], legsLean: scan.values[BodyScanKeys.legsLean],
            legLeftLean: scan.values[BodyScanKeys.legLeftLean], legRightLean: scan.values[BodyScanKeys.legRightLean]))
    }

    private static func hasArmOrLegFigure(_ scan: BodyScan) -> Bool {
        [BodyScanKeys.armsLean, BodyScanKeys.armLeftLean, BodyScanKeys.armRightLean, BodyScanKeys.legsLean,
         BodyScanKeys.legLeftLean, BodyScanKeys.legRightLean].contains { scan.values[$0] != nil }
    }

    private static var armsToLegsTitle: String { String(localized: "Arms to legs") }
    private static var armSidesTitle: String { String(localized: "Left and right arm") }
    private static var legSidesTitle: String { String(localized: "Left and right leg") }

    private static func derivedRows(_ scan: BodyScan) -> [BodyScanDerivedRow] {
        guard hasArmOrLegFigure(scan) else { return [] }
        let derived = derivation(scan)
        var captions: [String] = []
        if derived.armsSource == .sumOfSides { captions.append(String(localized: "From left and right arm.")) }
        if derived.legsSource == .sumOfSides { captions.append(String(localized: "From left and right leg.")) }
        var ratioCaption: String?
        if case .value = derived.armToLegLeanPercent, !captions.isEmpty {
            ratioCaption = captions.joined(separator: " ")
        }
        let sidesMissing = String(localized: "Not available. Enter both sides.")
        return [
            BodyScanDerivedRow(title: armsToLegsTitle,
                               valueText: derivedText(derived.armToLegLeanPercent, armsToLegsText,
                                                      missing: String(localized: "Not available. Enter arms and legs lean mass.")),
                               caption: ratioCaption),
            BodyScanDerivedRow(title: armSidesTitle,
                               valueText: derivedText(derived.armSideDifferencePercent, sideText, missing: sidesMissing),
                               caption: nil),
            BodyScanDerivedRow(title: legSidesTitle,
                               valueText: derivedText(derived.legSideDifferencePercent, sideText, missing: sidesMissing),
                               caption: nil),
        ]
    }

    private static func derivedText(_ value: BodyScanDerivedValue, _ words: (Double) -> String,
                                    missing: String) -> String {
        switch value {
        case .value(let x): return words(x)
        case .notAvailable(.missingComponent): return missing
        case .notAvailable(.invalidComponent):
            return String(localized: "Not available. A figure it needs could not be used.")
        }
    }

    private static func armsToLegsText(_ percent: Double) -> String {
        let shown = BodyRecordMath.displayString(percent, decimals: 1)
        return String(localized: "\(shown)% of legs lean mass")
    }

    /// Positive: the left side is larger.
    private static func sideText(_ percent: Double) -> String {
        let shown = BodyRecordMath.displayString(abs(percent), decimals: 1)
        if BodyRecordMath.quantize(percent, decimals: 1) > 0 { return String(localized: "Left \(shown)% more") }
        if BodyRecordMath.quantize(percent, decimals: 1) < 0 { return String(localized: "Right \(shown)% more") }
        return String(localized: "Equal")
    }

    // MARK: Lines and small formats

    private static func unreadableLine(_ scan: BodyScan) -> String? {
        let n = scan.unreadableKeys.count
        guard n > 0 else { return nil }
        if n == 1 { return String(localized: "1 value in this scan could not be read. It remains in Lab Book.") }
        return String(localized: "\(n) values in this scan could not be read. They remain in Lab Book.")
    }

    private static func conflictingLine(_ scan: BodyScan) -> String? {
        let n = scan.conflictingKeys.count
        guard n > 0 else { return nil }
        if n == 1 {
            return String(localized: "1 figure in this scan has two different stored values. Open Lab Book to delete the one that is wrong.")
        }
        return String(localized: "\(n) figures in this scan have two different stored values. Open Lab Book to delete the one that is wrong.")
    }

    private static func labels(_ keys: [String]) -> [String] {
        BodyScanField.all.filter { keys.contains($0.key) }.map(\.label)
    }

    /// A signed number: "+" before a rise, "−" before a fall, no sign on zero.
    private static func signed(_ x: Double, decimals: Int) -> String {
        let magnitude = BodyRecordMath.displayString(abs(x), decimals: decimals)
        if x > 0 { return "+\(magnitude)" }
        if x < 0 { return "\u{2212}\(magnitude)" }
        return magnitude
    }

    /// A stored day key as a date with the year ("Wed 8 Jan 2031" in English), in the given locale.
    static func dateText(_ day: String, locale: Locale) -> String {
        guard let date = dayKeyFormatter.date(from: day) else { return day }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMMyyyy")
        return formatter.string(from: date)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
