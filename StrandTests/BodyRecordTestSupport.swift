// API ASSUMED BY THESE TESTS
//
// Shared by the stage 4 (body record) app-target tests: BodyRecordStoreTests,
// BodyRecordSingleNumberTests, BodyRecordPresenterTests, BodyRecordFlagTests,
// LabReportUnitsEditorTests and BodyRecordCoachRollUpTests. Written before the implementation, from
// docs/personal/superapp/specs/stage-4.md (§5, §7, §9, §10, §11, §13) with RULINGS-ADDENDUM.md
// (A1 to A17) beside it. This block is the whole new app API those files call; each file repeats
// the part it uses. Anything not listed is used as it exists in the tree.
//
// ---- Strand/Data/BodyRecordSettings.swift (§9.4) ----
//
//     enum BodyRecordSettings {
//         static let enabledKey = "noop.bodyRecordEnabled"
//         static let labReportUnitsKey = "noop.labReportUnitsEnabled"
//         @MainActor static let enabledFlag: ObservableDefaultsFlag        // ObservableDefaultsFlag(key: enabledKey)
//         @MainActor static let labReportUnitsFlag: ObservableDefaultsFlag // ObservableDefaultsFlag(key: labReportUnitsKey)
//         /// §4.4, §7.1: the scope the Lab Book markers CSV import passes. `.withBodyRecord` exactly
//         /// while body record is on, `.builtIn` otherwise.
//         static func csvScope(bodyRecordEnabled: Bool) -> MarkerCatalogScope
//     }
//
//     #if DEBUG, Strand/Data/DemoScreenRegistry.swift (ruling A4, §12.10):
//     extension DemoScreenPrefixes {
//         static let bodyRecord = ["bodyrecord-", "scan-", "compare-", "bench-", "labunits-"]
//     }
//
// ---- Strand/Data/BodyScanFields.swift (§7.7) ----
//
//     enum BodyScanSection: String, CaseIterable {
//         case wholeBody, fatDistribution, leanMassByRegion, boneDensity, energy, note
//         var title: String     // "Whole body", "Fat distribution", "Lean mass by region",
//                               // "Bone density", "Energy", "Note"
//     }
//     struct BodyScanField: Equatable {
//         let key: String
//         let section: BodyScanSection
//         let label: String                 // §11 field label, e.g. "Total mass", "Arms, total"
//         let storedUnit: String            // the catalogue's canonicalUnit; "" for the note
//         let entryUnits: [String]          // §7.7 "Entry units", the stored unit first; [] for the note
//         let range: ClosedRange<Double>?   // §7.7, inclusive, stored unit; nil for the note
//         let decimals: Int                 // the catalogue's
//         let showsPercentChange: Bool      // §7.7 last column
//         static let all: [BodyScanField]   // the 23 rows of §7.7, in that order, the note last
//         static func field(for key: String) -> BodyScanField?
//         static let noteMaxLength: Int     // 500
//     }
//
// ---- Strand/Data/BodyRecordStore.swift (§9.1), exactly as the specification declares it ----
//
//     struct BodyScan: Equatable, Identifiable {
//         let id: String                       // "<source>\u{1F}<takenAt>"
//         let source: String
//         let takenAt: Int
//         let day: String
//         let values: [String: Double]         // readable, non-conflicting keys only, stored unit
//         let rows: [String: [LabMarkerRow]]   // merged member rows per key, ordered by id
//         let note: String?
//         let unreadableKeys: [String]         // sorted
//         let conflictingKeys: [String]        // sorted
//         var isEditable: Bool { get }         // source == MarkerCatalog.scanSource && conflictingKeys.isEmpty
//         var isDeletable: Bool { get }        // source == MarkerCatalog.scanSource
//     }
//     struct BodyScanDraft: Equatable { var day: String; var values: [String: Double]; var note: String? }
//         (memberwise initialiser `BodyScanDraft(day:values:note:)`)
//     enum BodyRecordError: Error, Equatable {
//         case nothingToSave, outOfRange(key: String), noteTooLong, invalidDay, futureDay,
//              instantOccupied, scanNotFound, notEditable, storeUnavailable
//     }
//     @MainActor final class BodyRecordStore {
//         init(repository: Repository, provider: BodyMeasurementProvider? = nil,
//              timeZone: @escaping () -> TimeZone = { TimeZone.current },
//              now: @escaping () -> Date = { Date() })
//         func scans() async -> [BodyScan]
//         @discardableResult func save(_ draft: BodyScanDraft, replacing existing: BodyScan?) async throws -> BodyScan
//         func delete(_ scan: BodyScan) async throws
//         func benchmarkReadings(key: String) async -> [LabMarkerRow]
//         func benchmarkKeysPresent() async -> [String]
//         @discardableResult func saveBenchmark(key: String, value: Double, unit: String, takenAt: Date,
//                                               note: String?) async throws -> LabMarkerRow
//         func deleteBenchmark(_ row: LabMarkerRow) async throws
//     }
//
// ---- Strand/Data/BodyRecordPresenter.swift and Strand/Data/BodyRecordModel.swift (§10, §11) ----
//
// Every user-facing string comes from the presenter; the views bind and decide nothing. Values are
// shown at the catalogue's decimals through `LabBookFormat.value(_:key:)` in the display unit
// (masses stored in kilograms follow the unit system, everything else stays in its stored unit,
// §7.7). Number texts carry no unit: the unit is its own field.
//
//     enum BodyRecordLoad: Equatable {
//         case loading
//         case storeUnavailable
//         case loaded(scans: [BodyScan], benchmarks: [BenchmarkHistory])
//     }
//     struct BenchmarkHistory: Equatable { let key: String; let readings: [LabMarkerRow] }   // oldest first
//         (memberwise initialiser `BenchmarkHistory(key:readings:)`)
//
//     struct BodyRecordScreen: Equatable {            // §10.1
//         var title: String                           // "Body record"
//         var isLoading: Bool                         // G1
//         var storeMessage: String?                   // G9 "Couldn't open the local store."
//         var latestScan: BodyScanCard?               // G3, G4: the last scan of the §7.6 order
//         var compareTitle: String?                   // G4 "Compare with <date of the previous scan>"
//         var addSecondScanText: String?              // G3 "Add a second scan to compare"
//         var scansEmptyText: String?                 // G2 "No scans yet"
//         var addScanTitle: String?                   // "Add a scan" (nil in G1 and G9)
//         var scanRows: [BodyScanListRow]             // G4: every scan, newest first; [] below two scans
//         var benchmarks: [BenchmarkRow]              // G7, G8, in `benchmarkKeysPresent` order
//         var benchmarksEmptyText: String?            // G2 "No benchmarks yet"
//         var addBenchmarkTitle: String?              // "Add a benchmark" (nil in G1 and G9)
//         var openLabBookTitle: String?               // G2 row to Lab Book, "Open Lab Book" (nil in G1, G9)
//     }
//     struct BodyScanCard: Equatable {
//         var scanId: String
//         var dateText: String
//         var figures: [BodyScanFigure]               // the Whole body figures entered and readable, field order
//         var derivedLine: String?                    // "<value>% of legs lean mass", only when it has a value
//         var importedText: String?                   // G6 "Imported from CSV"
//         var unreadableText: String?                 // G5 "<n> values in this scan could not be read. …"
//         var conflictingText: String?                // G5b "<n> figures in this scan have two different …"
//     }
//     struct BodyScanFigure: Equatable {
//         var key: String; var label: String; var valueText: String; var unit: String
//         var caption: String?                        // the RMR's "Laboratory estimate. …"
//     }
//     struct BodyScanListRow: Equatable { var scanId: String; var dateText: String }
//     struct BenchmarkRow: Equatable {
//         var key: String; var name: String; var valueText: String; var unit: String; var dateText: String
//         var sincePreviousText: String?              // signed change with unit, nil with one reading (G8)
//         var sinceFirstText: String?
//     }
//     struct BodyRecordHealthRow: Equatable { var title: String; var detail: String }
//     struct BodyRecordConfirmation: Equatable { var title: String; var confirmTitle: String; var cancelTitle: String }
//
//     struct BodyScanDetail: Equatable {              // §10.3
//         var scanId: String
//         var dateText: String
//         var sections: [BodyScanDetailSection]       // report order; a section with nothing entered is absent
//         var derived: [BodyScanDerivedRow]           // [] when the scan has no arm or leg figure at all
//         var note: String?
//         var canEdit: Bool
//         var canDelete: Bool
//         var importedText: String?                   // I6
//         var unreadableText: String?                 // I5 (the G5 line)
//         var unreadableLabels: [String]              // I5: the fields named
//         var conflictingText: String?                // I5b (the G5b line)
//         var conflictingLabels: [String]
//         var openLabBookTitle: String?               // I5b, I6
//     }
//     struct BodyScanDetailSection: Equatable { var section: BodyScanSection; var title: String; var figures: [BodyScanFigure] }
//     struct BodyScanDerivedRow: Equatable { var title: String; var valueText: String; var caption: String? }
//         titles "Arms to legs", "Left and right arm", "Left and right leg", in that order
//
//     struct BodyScanComparison: Equatable {          // §10.4
//         var earlierScanId: String?                  // the smaller takenAt of the two chosen
//         var laterScanId: String?
//         var earlierChoices: [BodyScanChoice]        // J8: never contains laterScanId
//         var laterChoices: [BodyScanChoice]          // J8: never contains earlierScanId
//         var rows: [BodyScanComparisonRow]           // field order; a field in neither scan has no row
//         var derivedRows: [BodyScanComparisonRow]    // the three derived titles
//         var emptyText: String?                      // J7 "No scans yet"
//         var addScanTitle: String?                   // J7 "Add a scan"
//         var oneScanText: String?                    // J6 "One scan so far. A second scan makes a comparison."
//         var notes: [String]                         // J10b: the G5 / G5b line of a scan in the table
//     }
//     struct BodyScanChoice: Equatable { var scanId: String; var dateText: String }
//     struct BodyScanComparisonRow: Equatable {
//         var key: String                             // the field key; the derived title for a derived row
//         var label: String
//         var earlierText: String                     // the value, or "not entered" / "not available"
//         var laterText: String
//         var unit: String
//         var changeText: String?                     // "+0.40 kg", "-2.6 points", "No change"; nil unless both
//         var directionText: String?                  // "up" / "down"; nil for no change and one side
//         var percentText: String?                    // "-5.0%"; nil when §7.7 hides it or it is nil
//     }
//
//     enum BodyScanSheetPhase: Equatable { case editing, saving, occupied, failed }
//     struct BodyScanEntry: Equatable {               // what the scan sheet holds as typed
//         var day: String
//         var texts: [String: String]                 // key -> typed text; absent or blank: not entered
//         var units: [String: String]                 // key -> chosen entry unit; absent: the default
//         var note: String
//         init(day: String)                           // empty texts, units and note
//         init(editing scan: BodyScan, unitSystem: UnitSystem)   // H9: prefilled in the display unit
//     }
//     struct BodyScanSheetState: Equatable {          // §10.2
//         var introText: String
//         var sections: [BodyScanSheetSection]        // the five numeric sections of §7.7
//         var draft: BodyScanDraft?                   // what Save writes (stored units); nil while Save is disabled
//         var canSave: Bool
//         var controlsDisabled: Bool                  // H11
//         var formMessage: String?                    // H7
//         var weighInLine: String?                    // H8
//         var statusMessage: String?                  // H10, H12
//     }
//     struct BodyScanSheetSection: Equatable {
//         var section: BodyScanSection; var title: String; var fields: [BodyScanSheetField]
//         var mismatchText: String?                   // H6, under the affected section
//     }
//     struct BodyScanSheetField: Equatable {
//         var key: String; var label: String; var unitOptions: [String]; var unit: String; var text: String
//         var storedAsText: String?                   // H3 "Stored as <value> <unit>."
//         var errorText: String?                      // H4, H5
//         var hasSignToggle: Bool                     // T-score and Z-score only
//     }
//
//     struct BenchmarkChoice: Equatable { var key: String?; var name: String }   // key nil: "Custom benchmark"
//     struct BenchmarkEntry: Equatable {
//         var key: String?                            // nil: a custom benchmark
//         var customName: String; var customUnit: String; var text: String
//         init(key: String?, customName: String = "", customUnit: String = "reps", text: String = "")
//     }
//     struct BenchmarkEntryState: Equatable {
//         var key: String?                            // the key a save writes; nil until a custom name is typed
//         var unit: String
//         var unitOptions: [String]                   // K3 ["reps", "s", "kg"] for a custom one, else [unit]
//         var acceptsDuration: Bool                   // K2
//         var value: Double?                          // stored value; nil while invalid
//         var errorText: String?                      // K4
//         var canSave: Bool
//     }
//     struct BenchmarkDetail: Equatable {             // §10.5
//         var key: String; var title: String
//         var rows: [BenchmarkReadingRow]             // newest first
//         var oneReadingText: String?                 // K6 "One reading so far."
//     }
//     struct BenchmarkReadingRow: Equatable {
//         var rowId: String; var valueText: String; var unit: String; var dateText: String
//         var note: String?; var changeText: String?  // against the previous (older) reading
//     }
//
//     enum BodyRecordPresenter {
//         static func screen(_ load: BodyRecordLoad, unitSystem: UnitSystem, locale: Locale) -> BodyRecordScreen
//         static func healthRow(enabled: Bool, scans: [BodyScan], locale: Locale) -> BodyRecordHealthRow?
//         static func detail(_ scan: BodyScan, unitSystem: UnitSystem, locale: Locale) -> BodyScanDetail
//         static func comparison(scans: [BodyScan], earlierId: String?, laterId: String?,
//                                unitSystem: UnitSystem, locale: Locale) -> BodyScanComparison
//         static func comparisonUsesStackedRows(accessibilityTextSize: Bool) -> Bool      // J11
//         static func sheet(_ entry: BodyScanEntry, unitSystem: UnitSystem, decimalSeparator: Character,
//                           phase: BodyScanSheetPhase, weighInOutranks: Bool) -> BodyScanSheetState
//         static func scanDeleteConfirmation() -> BodyRecordConfirmation                   // H13
//         static func benchmarkChoices() -> [BenchmarkChoice]                              // K1
//         static let customBenchmarkUnits: [String]                                        // ["reps", "s", "kg"]
//         static func benchmarkEntry(_ entry: BenchmarkEntry, decimalSeparator: Character) -> BenchmarkEntryState
//         static func benchmarkDetail(_ history: BenchmarkHistory, unitSystem: UnitSystem,
//                                     locale: Locale) -> BenchmarkDetail
//         static func benchmarkDeleteConfirmation() -> BodyRecordConfirmation              // K7
//         /// K2: "45" is 45 s, "1:30" is 90 s; nil for anything else, and for 60 or more seconds after a colon.
//         static func parseDuration(_ text: String, decimalSeparator: Character) -> Double?
//         /// §8.4, H8, exactly as the specification declares it.
//         static func weighInOutranksDraft(draftRow: LabMarkerRow, weighInRows: [LabMarkerRow], today: String) -> Bool
//     }
//
//     @MainActor final class BodyRecordModel: ObservableObject {
//         init(store: BodyRecordStore, unitSystem: @escaping () -> UnitSystem, locale: @escaping () -> Locale)
//         @Published private(set) var screen: BodyRecordScreen    // G1 until the first load ends
//         func load() async                                        // reads scans() and the benchmarks
//         func scan(id: String) -> BodyScan?                       // I7: nil once the scan is gone
//     }
//     @MainActor final class BodyScanSheetModel: ObservableObject {
//         init(store: BodyRecordStore, weighIns: WeighInStore, editing: BodyScan?, unitSystem: UnitSystem,
//              decimalSeparator: Character, today: @escaping () -> String)
//         @Published var entry: BodyScanEntry
//         @Published private(set) var phase: BodyScanSheetPhase
//         var state: BodyScanSheetState { get }   // BodyRecordPresenter.sheet(entry, …, phase:, weighInOutranks:)
//         func evaluate() async                   // asks weighInOutranksDraft for the current entry (H8)
//         @discardableResult func save() async -> BodyScan?   // nil on failure: phase .occupied or .failed
//     }
//
//     /// 4B (§10.6): the Lab Book editor's draft logic, extracted so the view only binds.
//     struct LabMarkerEntryDraft: Equatable {
//         init(markerKey: String, reportUnitsEnabled: Bool, decimalSeparator: Character, takenAt: Date)
//         let markerKey: String
//         var takenAt: Date
//         var unitLabel: String                   // starts at the stored unit
//         var text: String
//         var unitOptions: [String] { get }       // labels; legacy tier while the flag is off
//         var storedUnit: String { get }
//         var typedValue: Double? { get }         // `Double(_:)` while off; `MarkerUnitTable.parseEntry` while on
//         var storedValue: Double? { get }        // converted to the stored unit
//         var annotation: String? { get }         // §9.3 valueText; nil for the stored unit and while off
//         var conversionLine: String? { get }     // L2 "Stored as <value> <unit>." / L3 "Same number, stored as <unit>."
//         var formulaLine: String? { get }        // the HbA1c formula of §11 while "%" is chosen
//         var errorLine: String? { get }          // L4
//         var canSave: Bool { get }
//         var offersSaveAndAddAnother: Bool { get }   // true exactly while the flag is on
//         /// L5: the next draft's date (this draft's, kept) and the "Saved <marker name>." line.
//         func afterSaveAndAddAnother(markerName: String) -> (takenAt: Date, savedLine: String)
//     }
//
// ---- Edited existing app API ----
//
//     CutScorecardPresenter.history(weights:waists:appleHealth:unitSystem:locale:today:bodyRecordEnabled:)
//         `today:` arrives with stage 1's work package 1-11 (stage-1.md §8.7); `bodyRecordEnabled: Bool
//         = false` is stage 4's defaulted parameter (§10.7).
//     WeighInHistoryRow.scanId: String?   // the BodyScan id a tap pushes; nil unless body record is
//                                         // on and the row's source is MarkerCatalog.scanSource
//
// ---- Stage 1 work package 1-11 (stage-1.md §8.1, §8.7, ruling R44), relied on and not tested here ----
//
//     BodyMeasurementResolver.weighInSource: String          // "manual"
//     BodyMeasurementResolver.series(_:candidates:policy:asOf:) with `asOf: String? = nil`
//
// ---- Stage 4 package API (already in the tree or arriving with 4-4a and 4-4c) ----
//
//     MarkerCatalog.scanSource, .isScanOnlyMarker(_:), .isBenchmark(_:), .definition(for:)
//     MarkerUnitTable (all of §6.2)
//     LabMarkerCsvImport.parse(text:scope:)   (§7.1)
//     WhoopStore.replaceLabMarkers(deleteIds:upsert:)   (§9.2; called by BodyRecordStore only)

import XCTest
import SQLite3
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

// Stage 4 (body record): the fixture and the harness the app-target tests share. Every value is
// synthetic: the one Fixture Person of stage 1 §13, with the three scans of stage 4 §13.1 dated on
// stage 1 weigh-in days and the benchmarks of §13.5. Device ids are the Lab Book ownership
// fixture's (`LabBookOwnershipAppFixture`); the active id is `whoop-FIXTURE-NEW` unless a test says
// otherwise. App-target instants are 12:00 UTC of the day with the zone injected as UTC (§13).

enum BodyRecordFixture {

    // MARK: Device ids (the ownership fixture's)

    static let canonical = LabBookOwnershipAppFixture.a   // my-whoop
    static let old = LabBookOwnershipAppFixture.b         // whoop-FIXTURE-OLD, registered, archived
    static let gone = LabBookOwnershipAppFixture.c        // whoop-FIXTURE-GONE, no registry row
    static let ring = LabBookOwnershipAppFixture.d        // oura-FIXTURE-RING, registered, other brand
    static let active = LabBookOwnershipAppFixture.n      // whoop-FIXTURE-NEW, registered, active
    static let everyId = [canonical, old, gone, ring, active]

    // MARK: Days and instants (§13)

    static let dayA = "2031-01-08"
    static let dayB = "2031-04-09"
    static let dayC = "2031-05-28"
    static let noonA = 1_925_640_000      // 2031-01-08 12:00 UTC
    static let noonB = 1_933_502_400      // 2031-04-09 12:00 UTC
    static let noonC = 1_937_736_000      // 2031-05-28 12:00 UTC
    /// Stage 1's weigh-in of each scan day, at 07:00 UTC.
    static let sevenA = 1_925_622_000
    static let sevenB = 1_933_484_400
    static let sevenC = 1_937_718_000

    /// 2032-01-01 00:00 UTC: after every instant these tests write.
    static let later = Date(timeIntervalSince1970: 1_956_528_000)
    static let utc = TimeZone(identifier: "UTC")!
    static let british = Locale(identifier: "en_GB")

    static func date(_ epoch: Int) -> Date { Date(timeIntervalSince1970: Double(epoch)) }

    // MARK: Scans (§13.1), stored units, keyed by marker key

    static let scanA: [String: Double] = [
        "weight": 100.0, "scan_fat_mass": 30.0, "scan_lean_mass": 67.0, "scan_bone_mass": 3.00,
        "scan_fat_free_mass": 70.0, "body_fat": 30.0, "scan_visceral_fat_mass": 1000,
        "scan_android_fat_pct": 36.0, "scan_gynoid_fat_pct": 30.0, "scan_android_gynoid_ratio": 1.20,
        "scan_arms_lean_mass": 10.00, "scan_arm_left_lean_mass": 4.90, "scan_arm_right_lean_mass": 5.10,
        "scan_legs_lean_mass": 20.00, "scan_leg_left_lean_mass": 10.00, "scan_leg_right_lean_mass": 10.00,
        "scan_trunk_lean_mass": 32.00, "scan_bmd": 1.200, "scan_bmd_t_score": 0.5, "scan_bmd_z_score": 0.4,
        "scan_rmr_lab_estimate": 1900,
    ]
    static let noteA = "Fixture note"

    static let scanB: [String: Double] = [
        "weight": 95.0, "scan_fat_mass": 26.0, "scan_lean_mass": 66.0, "scan_bone_mass": 3.00,
        "scan_fat_free_mass": 69.0, "body_fat": 27.4, "scan_visceral_fat_mass": 800,
        "scan_visceral_fat_area": 80, "scan_android_fat_pct": 30.0, "scan_gynoid_fat_pct": 26.0,
        "scan_android_gynoid_ratio": 1.15, "scan_arms_lean_mass": 10.40, "scan_arm_left_lean_mass": 5.20,
        "scan_arm_right_lean_mass": 5.20, "scan_legs_lean_mass": 19.60, "scan_leg_left_lean_mass": 9.80,
        "scan_leg_right_lean_mass": 9.80, "scan_trunk_lean_mass": 31.50, "scan_rmr_lab_estimate": 1850,
    ]

    static let scanC: [String: Double] = [
        "weight": 94.0, "scan_fat_mass": 25.0, "scan_lean_mass": 66.0, "scan_bone_mass": 3.00,
        "scan_arm_left_lean_mass": 5.30, "scan_arm_right_lean_mass": 5.30, "scan_legs_lean_mass": 19.50,
    ]

    static var draftA: BodyScanDraft { BodyScanDraft(day: dayA, values: scanA, note: noteA) }
    static var draftB: BodyScanDraft { BodyScanDraft(day: dayB, values: scanB, note: nil) }
    static var draftC: BodyScanDraft { BodyScanDraft(day: dayC, values: scanC, note: nil) }

    /// The 21 scan-only keys of §5.2, in catalogue order (the note last).
    static let scanOnlyKeys = [
        "scan_fat_mass", "scan_lean_mass", "scan_bone_mass", "scan_fat_free_mass", "scan_visceral_fat_mass",
        "scan_visceral_fat_area", "scan_android_fat_pct", "scan_gynoid_fat_pct", "scan_android_gynoid_ratio",
        "scan_arms_lean_mass", "scan_arm_left_lean_mass", "scan_arm_right_lean_mass", "scan_legs_lean_mass",
        "scan_leg_left_lean_mass", "scan_leg_right_lean_mass", "scan_trunk_lean_mass", "scan_bmd",
        "scan_bmd_t_score", "scan_bmd_z_score", "scan_rmr_lab_estimate", "scan_note",
    ]

    /// The 23 keys of §7.7 in field order.
    static let fieldKeys = [
        "weight", "scan_fat_mass", "scan_lean_mass", "scan_bone_mass", "scan_fat_free_mass", "body_fat",
        "scan_visceral_fat_mass", "scan_visceral_fat_area", "scan_android_fat_pct", "scan_gynoid_fat_pct",
        "scan_android_gynoid_ratio", "scan_arms_lean_mass", "scan_arm_left_lean_mass",
        "scan_arm_right_lean_mass", "scan_legs_lean_mass", "scan_leg_left_lean_mass",
        "scan_leg_right_lean_mass", "scan_trunk_lean_mass", "scan_bmd", "scan_bmd_t_score",
        "scan_bmd_z_score", "scan_rmr_lab_estimate", "scan_note",
    ]

    /// The stored unit of each §7.7 key (the catalogue's canonical unit, §5.2).
    static let storedUnit: [String: String] = [
        "weight": "kg", "scan_fat_mass": "kg", "scan_lean_mass": "kg", "scan_bone_mass": "kg",
        "scan_fat_free_mass": "kg", "body_fat": "%", "scan_visceral_fat_mass": "g", "scan_visceral_fat_area": "cm²",
        "scan_android_fat_pct": "%", "scan_gynoid_fat_pct": "%", "scan_android_gynoid_ratio": "ratio",
        "scan_arms_lean_mass": "kg", "scan_arm_left_lean_mass": "kg", "scan_arm_right_lean_mass": "kg",
        "scan_legs_lean_mass": "kg", "scan_leg_left_lean_mass": "kg", "scan_leg_right_lean_mass": "kg",
        "scan_trunk_lean_mass": "kg", "scan_bmd": "g/cm²", "scan_bmd_t_score": "SD", "scan_bmd_z_score": "SD",
        "scan_rmr_lab_estimate": "kcal/day", "scan_note": "",
    ]

    static func category(_ key: String) -> String {
        key == "weight" || key == "body_fat" ? "bodyMeasurement" : "imaging"
    }

    static func scanId(source: String = MarkerCatalog.scanSource, takenAt: Int) -> String {
        "\(source)\u{1F}\(takenAt)"
    }

    /// One row as a scan sheet writes it (§9.1), or, with another source, as a markers CSV import of
    /// the same figures writes it. Used to seed rows under other device ids.
    static func scanRow(_ key: String, value: Double?, deviceId: String, day: String, takenAt: Int,
                        source: String = MarkerCatalog.scanSource, unit: String? = nil,
                        valueText: String? = nil, suffix: String = "5CA40000") -> LabMarkerRow {
        LabMarkerRow(id: "\(key)-\(takenAt)-\(suffix)", deviceId: deviceId, markerKey: key,
                     category: category(key), day: day, takenAt: takenAt, value: value,
                     valueText: valueText, unit: unit ?? storedUnit[key] ?? "", source: source,
                     note: nil, referenceText: nil)
    }

    /// Every row of a scan's figures, as `scanRow` builds them.
    static func scanRows(_ values: [String: Double], note: String? = nil, deviceId: String, day: String,
                         takenAt: Int, source: String = MarkerCatalog.scanSource,
                         suffix: String = "5CA40000") -> [LabMarkerRow] {
        var rows = values.keys.sorted().map {
            scanRow($0, value: values[$0], deviceId: deviceId, day: day, takenAt: takenAt, source: source,
                    suffix: suffix)
        }
        if let note {
            rows.append(scanRow("scan_note", value: nil, deviceId: deviceId, day: day, takenAt: takenAt,
                                source: source, valueText: note, suffix: suffix))
        }
        return rows
    }

    // MARK: Benchmarks (§13.5), at 12:00 UTC

    static let jan06Noon = 1_925_467_200    // 2031-01-06 12:00 UTC
    static let feb17Noon = 1_929_096_000    // 2031-02-17 12:00 UTC
    static let mar31Noon = 1_932_724_800    // 2031-03-31 12:00 UTC
    static let customCarryKey = "custom_bench_fixture_carry"

    static func benchmarkRow(_ key: String, value: Double, unit: String, takenAt: Int, day: String,
                             deviceId: String, note: String? = nil, suffix: String = "BE4C0000") -> LabMarkerRow {
        LabMarkerRow(id: "\(key)-\(takenAt)-\(suffix)", deviceId: deviceId, markerKey: key, category: "other",
                     day: day, takenAt: takenAt, value: value, valueText: nil, unit: unit, source: "manual",
                     note: note, referenceText: nil)
    }

    // MARK: Stage 1 weigh-ins (stage-1.md §13.3), Wednesdays from 2031-01-08 at 07:00 UTC

    /// Week number -> (weight, waist); week 10 was missed.
    static let stageOneWeeks: [(week: Int, weight: Double?, waist: Double?)] = [
        (1, 100.0, 100.0), (2, 99.2, 99.5), (3, 98.4, 99.0), (4, 97.6, 98.5), (5, 97.5, 98.0),
        (6, 97.4, 97.5), (7, 97.3, 97.0), (8, 97.2, 97.0), (9, 97.1, 97.0), (10, nil, nil),
        (11, 96.0, 96.5), (12, 95.2, 96.0), (13, 95.1, 95.5), (14, 95.0, 95.0), (15, 94.9, 94.5),
        (16, 94.8, 94.5), (17, 94.7, 94.5), (18, 94.6, 94.5), (19, 94.5, 94.5), (20, 95.5, 94.5),
        (21, 94.0, 94.0), (22, 93.5, 93.5),
    ]
    /// 07:00 UTC on the Wednesday of stage 1 week `week`.
    static func stageOneInstant(week: Int) -> Int { sevenA + (week - 1) * 7 * 86_400 }
    /// Monday 2031-01-20 07:00 UTC, 98.9 kg: stage 1's extra week 3 reading, which loses to Wednesday.
    static let stageOneMondayExtra = 1_926_658_800
}

struct BodyRecordTestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// The temporary directories one test class created, removed in its `tearDown`.
final class BodyRecordTempDirectories {
    private var made: [URL] = []
    func make() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("body-record-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        made.append(dir)
        return dir
    }
    func removeAll() {
        for dir in made { try? FileManager.default.removeItem(at: dir) }
        made = []
    }
}

/// A value a clock or zone closure reads; set by a test between calls. Main actor only.
final class BodyRecordBox<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// The defaults suites one test class created, removed in its `tearDown`.
final class BodyRecordSuites {
    var names: [String] = []
    func make(_ prefix: String) -> UserDefaults {
        let name = "\(prefix)-\(UUID().uuidString)"
        names.append(name)
        return UserDefaults(suiteName: name)!
    }
    func removeAll() {
        for name in names { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        names = []
    }
}

/// One in-memory store with the ownership fixture's registry (N active), and the stage 1 and stage
/// 4 writers and readers over it.
@MainActor
struct BodyRecordHarness {
    let store: WhoopStore
    let repo: Repository
    let defaults: UserDefaults
    let provider: BodyMeasurementProvider
    let records: BodyRecordStore
    let weighIns: WeighInStore
    let builder: CutScorecardInputBuilder
    let zone: BodyRecordBox<TimeZone>
    let now: BodyRecordBox<Date>
    let today: BodyRecordBox<String>
    /// The database file of an on-disk harness; nil for the in-memory one.
    let path: String?

    typealias F = BodyRecordFixture

    /// `scorecard` switches `noop.cutScorecardEnabled` on in the harness's own suite, so the
    /// provider resolves under the `unified` policy. `onDiskIn`: a directory for a file-backed
    /// store, which a second SQLite connection can reach to inject a failure (`failEveryInsert`,
    /// `hideTheLabMarkerTable`); nil keeps the store in memory.
    static func make(suites: BodyRecordSuites, scorecard: Bool = true, deviceId: String = F.active,
                     today: String = "2031-06-04", now: Date = F.later,
                     zone: TimeZone = F.utc, onDiskIn directory: URL? = nil) async throws -> BodyRecordHarness {
        let store: WhoopStore
        let path = directory?.appendingPathComponent("body-record-tests.sqlite").path
        if let path {
            store = try await WhoopStore(path: path)
            try LabBookOwnershipAppFixture.registerFixtureDevices(in: store)
        } else {
            store = try await LabBookOwnershipAppFixture.emptyStoreWithRegistry()
        }
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        let defaults = suites.make("BodyRecordTests")
        if scorecard { defaults.set(true, forKey: CutScorecardSettings.enabledKey) }
        let todayBox = BodyRecordBox(today)
        let nowBox = BodyRecordBox(now)
        let zoneBox = BodyRecordBox(zone)
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { todayBox.value })
        let records = BodyRecordStore(repository: repo, provider: provider, timeZone: { zoneBox.value },
                                      now: { nowBox.value })
        let weighIns = WeighInStore(repository: repo, provider: provider, timeZone: { zoneBox.value },
                                    now: { nowBox.value })
        let builder = CutScorecardInputBuilder(repository: repo, provider: provider,
                                               settings: CutScorecardSettings(defaults: defaults),
                                               timeZone: { zoneBox.value })
        return BodyRecordHarness(store: store, repo: repo, defaults: defaults, provider: provider,
                                 records: records, weighIns: weighIns, builder: builder, zone: zoneBox,
                                 now: nowBox, today: todayBox, path: path)
    }

    /// Runs `sql` on the store's file through a second SQLite connection (on-disk harness only).
    func executeOnTheFile(_ sql: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let path = try XCTUnwrap(path, "an on-disk harness is needed to inject a failure", file: file, line: line)
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            sqlite3_close(db)
            throw BodyRecordTestError("could not open \(path)")
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw BodyRecordTestError("could not run: \(sql)")
        }
    }

    /// Every insert into `labMarker` fails from now on; deletes and updates still run, so a write
    /// that is not one transaction is caught half done.
    func failEveryInsert() throws {
        try executeOnTheFile("CREATE TRIGGER stage4_fail_insert BEFORE INSERT ON labMarker "
                             + "BEGIN SELECT RAISE(ABORT, 'injected by the stage 4 tests'); END")
    }

    /// Every read of `labMarker` fails from now on.
    func hideTheLabMarkerTable() throws {
        try executeOnTheFile("ALTER TABLE labMarker RENAME TO stage4HiddenLabMarker")
    }

    /// Every stored Lab Book row under every id, ordered by (`takenAt`, `id`).
    func everyRow() async throws -> [LabMarkerRow] {
        try await store.allLabMarkers().sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
    }

    /// Stored row count per device id; ids with no row are left out.
    func countsById() async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for row in try await everyRow() { counts[row.deviceId, default: 0] += 1 }
        return counts
    }

    /// Stored row count per row id (every id is unique, so each count is 1); for "no other row changed".
    func rowsById() async throws -> [String: LabMarkerRow] {
        Dictionary(uniqueKeysWithValues: try await everyRow().map { ($0.id, $0) })
    }

    /// The `lab-book` projected cell of one marker and day, nil when there is none.
    func cell(_ key: String, _ day: String) async throws -> Double? {
        try await store.metricSeries(deviceId: WhoopStore.labBookSourceId, key: key, from: day, to: day)
            .first { $0.day == day }?.value
    }

    /// Writes rows exactly as given, through the owner-scope upsert the Lab Book screen uses.
    func seed(_ rows: [LabMarkerRow]) async throws {
        try await store.upsertOwnerLabMarkers(rows)
    }

    /// A save through the store that must succeed.
    @discardableResult
    func save(_ draft: BodyScanDraft, replacing existing: BodyScan? = nil) async throws -> BodyScan {
        try await records.save(draft, replacing: existing)
    }

    /// The scan with this id as `scans()` lists it.
    func scan(_ id: String) async -> BodyScan? {
        await records.scans().first { $0.id == id }
    }

    /// The scan with this id, failing the test when it is not listed.
    func requireScan(_ id: String, file: StaticString = #filePath, line: UInt = #line) async throws -> BodyScan {
        let found = await scan(id)
        return try XCTUnwrap(found, "scan \(id) is not listed", file: file, line: line)
    }

    /// The first scan `scans()` lists, failing the test when there is none.
    func firstScan(file: StaticString = #filePath, line: UInt = #line) async throws -> BodyScan {
        let listed = await records.scans()
        return try XCTUnwrap(listed.first, "no scan is listed", file: file, line: line)
    }

    /// The stored row of `key` at `takenAt` with `source`, failing the test when there is none.
    func storedRow(_ key: String, takenAt: Int, source: String = MarkerCatalog.scanSource,
                   file: StaticString = #filePath, line: UInt = #line) async throws -> LabMarkerRow {
        let rows = try await everyRow()
        return try XCTUnwrap(rows.first { $0.markerKey == key && $0.takenAt == takenAt && $0.source == source },
                             "no \(key) row at \(takenAt)", file: file, line: line)
    }

    // MARK: Stage 1 readouts (stage-1.md §8.6), weight

    /// The Today tile input, the estimates' input, the readiness input and the scorecard's current
    /// weight, as `BodyMeasurementSingleSourceTests` names them.
    func weightReadouts(today day: String) async -> [Double?] {
        let input = await builder.build(today: day)
        return [provider.current(.weight, consumer: .display)?.value,
                provider.current(.weight, consumer: .estimate)?.value,
                provider.resolve(.weight, asOf: day, consumer: .estimate)?.value,
                CutScorecard.evaluate(input).currentWeightKg]
    }

    /// The scorecard's weekly point for the Monday `weekStart`, evaluated for `today`.
    func weekPoint(_ weekStart: String, today day: String) async -> Double? {
        let input = await builder.build(today: day)
        return CutScorecard.evaluate(input).weeks.first { $0.weekStart == weekStart }?.weightKg
    }

    /// The profile mirror the provider writes (stage-1.md §8.5).
    var mirroredWeight: Double? {
        defaults.object(forKey: "profile.weightKg") == nil ? nil : defaults.double(forKey: "profile.weightKg")
    }
}
