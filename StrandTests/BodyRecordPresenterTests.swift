// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/stage-4.md §7.7, §8.4, §10.1 to §10.5 and §11, declared in full
// at the top of BodyRecordTestSupport.swift. This file calls:
//
//     BodyScanField.all / .field(for:), BodyScanSection (.title)
//     BodyRecordLoad, BenchmarkHistory(key:readings:)
//     BodyRecordPresenter.screen(_:unitSystem:locale:)          -> BodyRecordScreen, BodyScanCard,
//                                                                  BodyScanFigure, BodyScanListRow, BenchmarkRow
//     BodyRecordPresenter.healthRow(enabled:scans:locale:)     -> BodyRecordHealthRow?
//     BodyRecordPresenter.detail(_:unitSystem:locale:)         -> BodyScanDetail, BodyScanDetailSection,
//                                                                  BodyScanDerivedRow
//     BodyRecordPresenter.comparison(scans:earlierId:laterId:unitSystem:locale:)
//                                                              -> BodyScanComparison, BodyScanChoice,
//                                                                  BodyScanComparisonRow
//     BodyRecordPresenter.comparisonUsesStackedRows(accessibilityTextSize:)
//     BodyScanEntry(day:), BodyScanEntry(editing:unitSystem:), BodyScanSheetPhase
//     BodyRecordPresenter.sheet(_:unitSystem:decimalSeparator:phase:weighInOutranks:)
//                                                              -> BodyScanSheetState, BodyScanSheetSection,
//                                                                  BodyScanSheetField
//     BodyRecordPresenter.scanDeleteConfirmation(), .benchmarkDeleteConfirmation() -> BodyRecordConfirmation
//     BodyRecordPresenter.benchmarkChoices() -> [BenchmarkChoice], .customBenchmarkUnits
//     BodyRecordPresenter.benchmarkEntry(_:decimalSeparator:)  -> BenchmarkEntryState (BenchmarkEntry in)
//     BodyRecordPresenter.benchmarkDetail(_:unitSystem:locale:) -> BenchmarkDetail, BenchmarkReadingRow
//     BodyRecordPresenter.parseDuration(_:decimalSeparator:)
//     BodyRecordPresenter.weighInOutranksDraft(draftRow:weighInRows:today:)
//     BodyRecordModel(store:unitSystem:locale:), .screen, .load(), .scan(id:)
//     BodyScanSheetModel(store:weighIns:editing:unitSystem:decimalSeparator:today:), .entry, .phase,
//         .state, .evaluate(), .save()
//
// Decided by these tests where the specification leaves the shape open (each is one assertion, so
// a different decision fails one test and is easy to see):
//
//  1. Number texts carry no unit; the unit is its own field. Values are `LabBookFormat.value`
//     of the display-unit value at the catalogue's decimals; a change text is a signed number then
//     a space then the unit, or "points" for a percentage field, or "No change". The minus sign may
//     be "-" or "−"; a positive change carries "+".
//  2. Dates carry the year (design round S4, decision 12); their exact format is not pinned. The
//     G4 "Compare with <date>" uses the same date text as the scan list row of the previous scan.
//  3. A count line for one value ("<n> values …") is not pinned beyond its number and its fixed
//     tail, so the singular wording the design round proposes stays open.
//  4. The derived block of the detail is absent for a scan with no arm or leg figure (design
//     decision 11). The comparison shows the side differences without a change (decision 10).
//
// Synthetic values only: the Fixture Person.

import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

@MainActor
final class BodyRecordPresenterTests: XCTestCase {
    private typealias F = BodyRecordFixture
    private typealias P = BodyRecordPresenter
    private let suites = BodyRecordSuites()
    private let directories = BodyRecordTempDirectories()

    override func tearDown() {
        suites.removeAll()
        directories.removeAll()
        super.tearDown()
    }

    // MARK: - Harness

    private func harness(today: String = "2031-06-04") async throws -> BodyRecordHarness {
        try await BodyRecordHarness.make(suites: suites, today: today)
    }

    /// The scans `BodyRecordStore` lists after saving `drafts`, in the §7.6 order.
    private func scans(_ drafts: [BodyScanDraft]) async throws -> [BodyScan] {
        let h = try await harness()
        for draft in drafts { try await h.save(draft) }
        return await h.records.scans()
    }

    private func scanA() async throws -> BodyScan {
        let all = try await scans([F.draftA])
        return try XCTUnwrap(all.first)
    }

    /// V9: scan A with its fat-mass row rewritten in the unit `stone`.
    private func scanAWithUnreadableFat(_ h: BodyRecordHarness) async throws -> BodyScan {
        try await h.save(F.draftA)
        var fat = try await h.storedRow("scan_fat_mass", takenAt: F.noonA)
        fat.unit = "stone"
        try await h.seed([fat])
        return try await h.requireScan(F.scanId(takenAt: F.noonA))
    }

    /// V16: scan A with a second fat-mass row of 31.0 under `whoop-FIXTURE-OLD`.
    private func scanAWithConflictingFat(_ h: BodyRecordHarness) async throws -> BodyScan {
        try await h.save(F.draftA)
        var other = try await h.storedRow("scan_fat_mass", takenAt: F.noonA)
        other.id = "scan_fat_mass-\(F.noonA)-C0FFEE31"
        other.deviceId = F.old
        other.value = 31.0
        try await h.seed([other])
        return try await h.requireScan(F.scanId(takenAt: F.noonA))
    }

    /// V10: scan A's rows as a markers CSV import in the wide scope writes them.
    private func importedScanA(_ h: BodyRecordHarness) async throws -> BodyScan {
        try await h.seed(F.scanRows(F.scanA, deviceId: F.active, day: F.dayA, takenAt: F.noonA,
                                    source: LabMarkerCsvImport.sourceId))
        return try await h.firstScan()
    }

    private func screen(_ scans: [BodyScan], _ benchmarks: [BenchmarkHistory] = [],
                        unitSystem: UnitSystem = .metric) -> BodyRecordScreen {
        P.screen(.loaded(scans: scans, benchmarks: benchmarks), unitSystem: unitSystem, locale: F.british)
    }

    private func detail(_ scan: BodyScan, unitSystem: UnitSystem = .metric) -> BodyScanDetail {
        P.detail(scan, unitSystem: unitSystem, locale: F.british)
    }

    private func compare(_ scans: [BodyScan], _ earlier: String? = nil, _ later: String? = nil) -> BodyScanComparison {
        P.comparison(scans: scans, earlierId: earlier, laterId: later, unitSystem: .metric, locale: F.british)
    }

    private func sheet(_ entry: BodyScanEntry, separator: Character = ".", phase: BodyScanSheetPhase = .editing,
                       outranks: Bool = false, unitSystem: UnitSystem = .metric) -> BodyScanSheetState {
        P.sheet(entry, unitSystem: unitSystem, decimalSeparator: separator, phase: phase, weighInOutranks: outranks)
    }

    /// An entry holding `values` typed as their stored-unit display text.
    private func entry(_ values: [String: Double], day: String = BodyRecordFixture.dayA, note: String = "") -> BodyScanEntry {
        var out = BodyScanEntry(day: day)
        for (key, value) in values { out.texts[key] = LabBookFormat.value(value, key: key) }
        out.note = note
        return out
    }

    private func field(_ state: BodyScanSheetState, _ key: String) -> BodyScanSheetField? {
        state.sections.flatMap(\.fields).first { $0.key == key }
    }

    private func signed(_ text: String?) -> String? { text?.replacingOccurrences(of: "−", with: "-") }

    private func benchmarkHistories() -> [BenchmarkHistory] {
        [BenchmarkHistory(key: "bench_pushup_reps", readings: [
            F.benchmarkRow("bench_pushup_reps", value: 10, unit: "reps", takenAt: F.jan06Noon, day: "2031-01-06",
                           deviceId: F.active),
            F.benchmarkRow("bench_pushup_reps", value: 14, unit: "reps", takenAt: F.feb17Noon, day: "2031-02-17",
                           deviceId: F.active),
         ]),
         BenchmarkHistory(key: "bench_dead_hang_s", readings: deadHang())]
    }

    private func deadHang() -> [LabMarkerRow] {
        [F.benchmarkRow("bench_dead_hang_s", value: 20, unit: "s", takenAt: F.jan06Noon, day: "2031-01-06", deviceId: F.active),
         F.benchmarkRow("bench_dead_hang_s", value: 30, unit: "s", takenAt: F.feb17Noon, day: "2031-02-17", deviceId: F.active),
         F.benchmarkRow("bench_dead_hang_s", value: 45, unit: "s", takenAt: F.mar31Noon, day: "2031-03-31", deviceId: F.active,
                        note: "Fixture bar")]
    }

    private func carry() -> BenchmarkHistory {
        BenchmarkHistory(key: F.customCarryKey, readings: [
            F.benchmarkRow(F.customCarryKey, value: 60, unit: "s", takenAt: F.jan06Noon, day: "2031-01-06", deviceId: F.active),
        ])
    }

    /// Every String reachable from `value` by reflection: the texts a view could draw.
    private func strings(in value: Any) -> [String] {
        if let text = value as? String { return [text] }
        var out: [String] = []
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            return mirror.children.first.map { strings(in: $0.value) } ?? []
        }
        for child in mirror.children { out += strings(in: child.value) }
        return out
    }

    // MARK: - Field table (§7.7)

    func testBodyScanFieldTableIsTheSpecificationsTable() {
        let all = BodyScanField.all
        XCTAssertEqual(all.map(\.key), F.fieldKeys)
        XCTAssertEqual(all.map(\.section.rawValue), [
            "wholeBody", "wholeBody", "wholeBody", "wholeBody", "wholeBody", "wholeBody",
            "fatDistribution", "fatDistribution", "fatDistribution", "fatDistribution", "fatDistribution",
            "leanMassByRegion", "leanMassByRegion", "leanMassByRegion", "leanMassByRegion", "leanMassByRegion",
            "leanMassByRegion", "leanMassByRegion", "boneDensity", "boneDensity", "boneDensity", "energy", "note",
        ])
        XCTAssertEqual(all.map(\.label), [
            "Total mass", "Fat mass", "Lean mass", "Bone mineral content", "Fat-free mass", "Body fat",
            "Visceral fat mass", "Visceral fat area", "Android fat", "Gynoid fat", "Android to gynoid ratio",
            "Arms, total", "Left arm", "Right arm", "Legs, total", "Left leg", "Right leg", "Trunk",
            "Bone mineral density", "T-score", "Z-score", "Resting metabolic rate", "Note",
        ])
        let ranges: [String: ClosedRange<Double>] = [
            "weight": 30...250, "scan_fat_mass": 1...200, "scan_lean_mass": 10...150, "scan_bone_mass": 0.5...6,
            "scan_fat_free_mass": 10...160, "body_fat": 1...75, "scan_visceral_fat_mass": 0...10_000,
            "scan_visceral_fat_area": 0...1_000, "scan_android_fat_pct": 1...80, "scan_gynoid_fat_pct": 1...80,
            "scan_android_gynoid_ratio": 0.1...5, "scan_arms_lean_mass": 1...30, "scan_arm_left_lean_mass": 0.5...15,
            "scan_arm_right_lean_mass": 0.5...15, "scan_legs_lean_mass": 5...60, "scan_leg_left_lean_mass": 2...30,
            "scan_leg_right_lean_mass": 2...30, "scan_trunk_lean_mass": 5...80, "scan_bmd": 0.3...2.5,
            "scan_bmd_t_score": -8...8, "scan_bmd_z_score": -8...8, "scan_rmr_lab_estimate": 500...5_000,
        ]
        for field in all {
            XCTAssertEqual(field.range, ranges[field.key], field.key)
            XCTAssertEqual(field.storedUnit, F.storedUnit[field.key], field.key)
            XCTAssertEqual(field.decimals, MarkerCatalog.definition(for: field.key)?.decimals ?? 0, field.key)
            XCTAssertEqual(BodyScanField.field(for: field.key), field)
            if field.key != "scan_note" { XCTAssertEqual(field.entryUnits.first, field.storedUnit, field.key) }
        }
        XCTAssertEqual(BodyScanField.field(for: "weight")?.range, WeighInStore.weightRangeKg, "the weigh-in range, reused")
        XCTAssertEqual(BodyScanField.field(for: "weight")?.entryUnits, ["kg", "lb"])
        XCTAssertEqual(BodyScanField.field(for: "scan_fat_mass")?.entryUnits, ["kg", "lb", "g"])
        XCTAssertEqual(BodyScanField.field(for: "scan_visceral_fat_mass")?.entryUnits, ["g", "kg", "lb"])
        XCTAssertEqual(BodyScanField.field(for: "scan_note")?.entryUnits, [])
        XCTAssertNil(BodyScanField.field(for: "scan_note")?.range)
        XCTAssertNil(BodyScanField.field(for: "height"), "a scan entry does not ask for height (§1)")
        let noPercent = Set(all.filter { !$0.showsPercentChange }.map(\.key))
        XCTAssertEqual(noPercent, ["body_fat", "scan_android_fat_pct", "scan_gynoid_fat_pct", "scan_bmd_t_score",
                                   "scan_bmd_z_score", "scan_note"])
        XCTAssertEqual(BodyScanField.noteMaxLength, 500)
        XCTAssertEqual(BodyScanSection.allCases.map(\.title),
                       ["Whole body", "Fat distribution", "Lean mass by region", "Bone density", "Energy", "Note"])
    }

    // MARK: - §10.1 Body record screen

    func testG1Loading() {
        let s = P.screen(.loading, unitSystem: .metric, locale: F.british)
        XCTAssertEqual(s.title, "Body record")
        XCTAssertTrue(s.isLoading)
        XCTAssertNil(s.latestScan)
        XCTAssertNil(s.storeMessage)
        XCTAssertNil(s.scansEmptyText, "a skeleton, not an empty state")
        XCTAssertNil(s.benchmarksEmptyText)
        XCTAssertNil(s.addScanTitle)
        XCTAssertEqual(s.scanRows, [])
        XCTAssertEqual(s.benchmarks, [])
    }

    func testG2NothingRecorded() {
        let s = screen([])
        XCTAssertFalse(s.isLoading)
        XCTAssertEqual(s.scansEmptyText, "No scans yet")
        XCTAssertEqual(s.benchmarksEmptyText, "No benchmarks yet")
        XCTAssertEqual(s.addScanTitle, "Add a scan")
        XCTAssertEqual(s.addBenchmarkTitle, "Add a benchmark")
        XCTAssertEqual(s.openLabBookTitle, "Open Lab Book")
        XCTAssertNil(s.latestScan)
        XCTAssertNil(s.compareTitle)
        XCTAssertNil(s.addSecondScanText)
        XCTAssertNil(s.storeMessage)
    }

    func testG3OneScan() async throws {
        let a = try await scanA()
        let s = screen([a])
        let card = try XCTUnwrap(s.latestScan)
        XCTAssertEqual(card.scanId, a.id)
        XCTAssertTrue(card.dateText.contains("2031"), card.dateText)
        XCTAssertEqual(card.figures.map(\.key), ["weight", "scan_fat_mass", "scan_lean_mass", "scan_bone_mass",
                                                 "scan_fat_free_mass", "body_fat"])
        XCTAssertEqual(card.figures.map(\.valueText), ["100.0", "30.0", "67.0", "3.00", "70.0", "30.0"])
        XCTAssertEqual(card.figures.map(\.unit), ["kg", "kg", "kg", "kg", "kg", "%"])
        XCTAssertEqual(card.figures.map(\.label), ["Total mass", "Fat mass", "Lean mass", "Bone mineral content",
                                                   "Fat-free mass", "Body fat"])
        XCTAssertEqual(card.derivedLine, "50.0% of legs lean mass")
        XCTAssertEqual(s.addSecondScanText, "Add a second scan to compare")
        XCTAssertNil(s.compareTitle)
        XCTAssertEqual(s.scanRows, [])
        XCTAssertNil(s.scansEmptyText)
        XCTAssertNil(card.importedText)
        XCTAssertNil(card.unreadableText)
        XCTAssertNil(card.conflictingText)
    }

    func testG4TwoOrMoreScans() async throws {
        let all = try await scans([F.draftA, F.draftC, F.draftB])
        let s = screen(all)
        let card = try XCTUnwrap(s.latestScan)
        XCTAssertEqual(card.scanId, F.scanId(takenAt: F.noonC), "the latest scan by instant")
        XCTAssertEqual(card.figures.map(\.valueText), ["94.0", "25.0", "66.0", "3.00"])
        XCTAssertEqual(card.derivedLine, "54.4% of legs lean mass")
        XCTAssertEqual(s.scanRows.map(\.scanId), [F.noonC, F.noonB, F.noonA].map { F.scanId(takenAt: $0) },
                       "newest first")
        XCTAssertEqual(s.compareTitle, "Compare with \(s.scanRows[1].dateText)", "the previous scan's date")
        XCTAssertNil(s.addSecondScanText)
        XCTAssertNil(s.scansEmptyText)
        for row in s.scanRows { XCTAssertTrue(row.dateText.contains("2031"), row.dateText) }
        XCTAssertEqual(Set(s.scanRows.map(\.dateText)).count, 3)
    }

    func testG5ScanWithUnreadableRows() async throws {
        let h = try await harness()
        let a = try await scanAWithUnreadableFat(h)
        let card = try XCTUnwrap(screen([a]).latestScan)
        let line = try XCTUnwrap(card.unreadableText)
        XCTAssertTrue(line.hasPrefix("1 "), line)
        XCTAssertTrue(line.contains("could not be read"), line)
        XCTAssertTrue(line.hasSuffix("Lab Book."), line)
        XCTAssertFalse(card.figures.contains { $0.key == "scan_fat_mass" }, "never shown as a number")
        XCTAssertEqual(card.figures.map(\.key), ["weight", "scan_lean_mass", "scan_bone_mass", "scan_fat_free_mass",
                                                 "body_fat"])
    }

    func testG5bScanWithAConflictingKey() async throws {
        let h = try await harness()
        let a = try await scanAWithConflictingFat(h)
        let card = try XCTUnwrap(screen([a]).latestScan)
        let line = try XCTUnwrap(card.conflictingText)
        XCTAssertTrue(line.hasPrefix("1 "), line)
        XCTAssertTrue(line.hasSuffix("Open Lab Book to delete the one that is wrong."), line)
        XCTAssertFalse(card.figures.contains { $0.key == "scan_fat_mass" })
        XCTAssertNil(card.unreadableText)
    }

    func testG6AnImportedScan() async throws {
        let h = try await harness()
        let imported = try await importedScanA(h)
        let card = try XCTUnwrap(screen([imported]).latestScan)
        XCTAssertEqual(card.importedText, "Imported from CSV")
        XCTAssertEqual(card.figures.first?.valueText, "100.0")
    }

    func testG7Benchmarks() {
        let s = screen([], benchmarkHistories())
        XCTAssertEqual(s.benchmarks.map(\.key), ["bench_pushup_reps", "bench_dead_hang_s"])
        XCTAssertEqual(s.benchmarks.map(\.name), ["Push-ups, most in one set", "Dead hang, longest hold"])
        let hang = s.benchmarks[1]
        XCTAssertEqual(hang.valueText, "45")
        XCTAssertEqual(hang.unit, "s")
        XCTAssertTrue(hang.dateText.contains("2031"), hang.dateText)
        XCTAssertEqual(signed(hang.sincePreviousText), "+15 s", "since the previous reading")
        XCTAssertEqual(signed(hang.sinceFirstText), "+25 s", "since the first reading")
        let pushups = s.benchmarks[0]
        XCTAssertEqual(pushups.valueText, "14")
        XCTAssertEqual(signed(pushups.sincePreviousText), "+4 reps")
        XCTAssertEqual(signed(pushups.sinceFirstText), "+4 reps")
        XCTAssertNil(s.benchmarksEmptyText)
        XCTAssertEqual(s.scansEmptyText, "No scans yet")
    }

    func testG8ABenchmarkWithOneReading() {
        let s = screen([], [carry()])
        let row = try? XCTUnwrap(s.benchmarks.first)
        XCTAssertEqual(row?.valueText, "60")
        XCTAssertEqual(row?.unit, "s")
        XCTAssertNil(row?.sincePreviousText, "no change line")
        XCTAssertNil(row?.sinceFirstText)
        XCTAssertFalse(row?.name.isEmpty ?? true)
    }

    func testG9StoreCouldNotBeOpened() {
        let s = P.screen(.storeUnavailable, unitSystem: .metric, locale: F.british)
        XCTAssertEqual(s.storeMessage, "Couldn't open the local store.")
        XCTAssertFalse(s.isLoading)
        XCTAssertNil(s.latestScan, "and nothing else")
        XCTAssertNil(s.scansEmptyText)
        XCTAssertNil(s.benchmarksEmptyText)
        XCTAssertNil(s.addScanTitle)
        XCTAssertNil(s.addBenchmarkTitle)
        XCTAssertNil(s.openLabBookTitle)
        XCTAssertNil(s.compareTitle)
        XCTAssertEqual(s.scanRows, [])
        XCTAssertEqual(s.benchmarks, [])
    }

    /// G10 is G4 and G7 at the largest text size: the presentation takes no text size, so the same
    /// content is drawn. Only the layout differs, which the simulator frames check (§12.10).
    func testG10LargestTextSizeShowsTheContentOfG4AndG7() async throws {
        let all = try await scans([F.draftA, F.draftB, F.draftC])
        let combined = screen(all, benchmarkHistories())
        XCTAssertEqual(combined.latestScan, screen(all).latestScan)
        XCTAssertEqual(combined.scanRows, screen(all).scanRows)
        XCTAssertEqual(combined.benchmarks, screen([], benchmarkHistories()).benchmarks)
    }

    /// §10.1, §11: the Health row exists only while the flag is on.
    func testHealthRowFollowsTheFlagAndNamesTheLastScan() async throws {
        XCTAssertNil(P.healthRow(enabled: false, scans: [], locale: F.british))
        let all = try await scans([F.draftA, F.draftB])
        XCTAssertNil(P.healthRow(enabled: false, scans: all, locale: F.british), "off: no row, whatever is stored")
        XCTAssertEqual(P.healthRow(enabled: true, scans: [], locale: F.british),
                       BodyRecordHealthRow(title: "Body record", detail: "No scans yet"))
        let row = try XCTUnwrap(P.healthRow(enabled: true, scans: all, locale: F.british))
        XCTAssertEqual(row.title, "Body record")
        XCTAssertEqual(row.detail, "Last scan \(screen(all).scanRows[0].dateText)")
    }

    /// §10.1: the screen shows no current weight; a scan's total mass appears with its date only.
    func testScreenShowsNoCurrentWeight() async throws {
        let all = try await scans([F.draftA, F.draftB])
        for text in strings(in: screen(all, benchmarkHistories())) {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("current"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("latest weight"), text)
        }
    }

    // MARK: - §10.2 Scan sheet

    func testH1NewEmpty() {
        let state = sheet(BodyScanEntry(day: F.dayC))
        XCTAssertEqual(state.introText,
                       "Type the figures as your report prints them. Leave out anything it does not give.")
        XCTAssertEqual(state.sections.map(\.title),
                       ["Whole body", "Fat distribution", "Lean mass by region", "Bone density", "Energy"])
        XCTAssertEqual(state.sections.flatMap(\.fields).map(\.key), Array(F.fieldKeys.dropLast()))
        XCTAssertTrue(state.sections.flatMap(\.fields).allSatisfy { $0.text.isEmpty && $0.errorText == nil
            && $0.storedAsText == nil })
        XCTAssertFalse(state.canSave)
        XCTAssertNil(state.draft)
        XCTAssertNil(state.formMessage, "nothing typed is not yet a message")
        XCTAssertNil(state.weighInLine)
        XCTAssertFalse(state.controlsDisabled)
        XCTAssertEqual(field(state, "weight")?.unit, "kg")
        XCTAssertEqual(field(state, "weight")?.unitOptions, ["kg", "lb"])
        XCTAssertEqual(field(state, "scan_fat_mass")?.unitOptions, ["kg", "lb", "g"])
        XCTAssertEqual(field(state, "scan_visceral_fat_mass")?.unit, "g")
        XCTAssertEqual(field(state, "body_fat")?.unitOptions, ["%"])

        // The mass-unit control follows `units.system`.
        let imperial = sheet(BodyScanEntry(day: F.dayC), unitSystem: .imperial)
        XCTAssertEqual(field(imperial, "weight")?.unit, "lb")
        XCTAssertEqual(field(imperial, "scan_trunk_lean_mass")?.unit, "lb")
        XCTAssertEqual(field(imperial, "scan_visceral_fat_mass")?.unit, "g", "grams stay grams")
        XCTAssertEqual(field(imperial, "body_fat")?.unit, "%")
    }

    func testH2FilledValid() {
        let state = sheet(entry(F.scanA, note: F.noteA))
        XCTAssertTrue(state.canSave)
        XCTAssertEqual(state.draft, F.draftA, "the draft Save writes, in stored units")
        XCTAssertNil(state.formMessage)
        XCTAssertTrue(state.sections.allSatisfy { $0.mismatchText == nil }, "scan A adds up (§13.1)")
        XCTAssertTrue(state.sections.flatMap(\.fields).allSatisfy { $0.errorText == nil })
    }

    func testScoreFieldsCarryASignToggle() {
        let state = sheet(BodyScanEntry(day: F.dayA))
        let toggles = state.sections.flatMap(\.fields).filter(\.hasSignToggle).map(\.key)
        XCTAssertEqual(toggles, ["scan_bmd_t_score", "scan_bmd_z_score"])
        var negative = entry(["scan_fat_mass": 30.0])
        negative.texts["scan_bmd_t_score"] = "-1.2"
        XCTAssertEqual(sheet(negative).draft?.values["scan_bmd_t_score"], -1.2)
    }

    func testH3AFieldInAnotherUnit() {
        var typed = entry(["scan_fat_mass": 30.0])
        typed.texts["weight"] = "220.5"
        typed.units["weight"] = "lb"
        typed.texts["scan_bone_mass"] = "3000"
        typed.units["scan_bone_mass"] = "g"
        let state = sheet(typed)
        XCTAssertEqual(field(state, "weight")?.storedAsText, "Stored as 100.0 kg.")
        XCTAssertEqual(field(state, "scan_bone_mass")?.storedAsText, "Stored as 3.00 kg.")
        XCTAssertNil(field(state, "scan_fat_mass")?.storedAsText, "typed in the stored unit")
        XCTAssertEqual(try XCTUnwrap(state.draft?.values["scan_bone_mass"]), 3.0, accuracy: 1e-12)
    }

    func testH4AFieldOutOfRange() {
        var typed = entry(F.scanC)
        typed.texts["scan_fat_mass"] = "250"
        let state = sheet(typed)
        let error = try? XCTUnwrap(field(state, "scan_fat_mass")?.errorText)
        XCTAssertTrue(error?.hasPrefix("Enter a value between ") ?? false, error ?? "no message")
        XCTAssertTrue(error?.hasSuffix(" kg.") ?? false, error ?? "no message")
        XCTAssertFalse(state.canSave)
        XCTAssertNil(state.draft)
        XCTAssertNil(field(state, "scan_lean_mass")?.errorText, "only the field out of range")
    }

    func testH5NotANumber() {
        for text in ["6,7", "nan", "inf", "1e2", "6..7", "6.", "abc", "１２"] {
            var typed = entry(F.scanC)
            typed.texts["scan_lean_mass"] = text
            let state = sheet(typed)
            XCTAssertEqual(field(state, "scan_lean_mass")?.errorText, "Use digits and one decimal separator.", text)
            XCTAssertFalse(state.canSave, text)
        }
        // The device's decimal separator is accepted.
        var comma = entry(["scan_fat_mass": 30.0])
        comma.texts["scan_lean_mass"] = "67,0"
        comma.texts["scan_fat_mass"] = "30,0"
        let state = sheet(comma, separator: ",")
        XCTAssertTrue(state.canSave)
        XCTAssertEqual(state.draft?.values["scan_lean_mass"], 67.0)
    }

    /// V3, V4, V5: a mismatch is one neutral line under the section, and never blocks Save.
    func testH6FiguresThatDoNotAddUp() {
        var v3 = F.scanB
        v3["scan_fat_free_mass"] = 96.0
        let state = sheet(entry(v3, day: F.dayB))
        let wholeBody = state.sections.first { $0.section == .wholeBody }
        XCTAssertEqual(wholeBody?.mismatchText, "These figures do not add up as typed. Check them against the report.")
        XCTAssertEqual(state.sections.filter { $0.mismatchText != nil }.count, 1, "one line, under the affected section")
        XCTAssertTrue(state.canSave, "Save stays enabled")

        var v4 = F.scanB
        v4["body_fat"] = 28.3
        XCTAssertTrue(sheet(entry(v4, day: F.dayB)).sections.allSatisfy { $0.mismatchText == nil },
                      "fat over fat plus lean is accepted")

        var v5 = F.scanB
        v5["body_fat"] = 31.0
        let v5State = sheet(entry(v5, day: F.dayB))
        XCTAssertNotNil(v5State.sections.first { $0.section == .wholeBody }?.mismatchText)
        XCTAssertTrue(v5State.canSave)

        var ratio = F.scanB
        ratio["scan_android_gynoid_ratio"] = 1.30
        let ratioState = sheet(entry(ratio, day: F.dayB))
        XCTAssertNotNil(ratioState.sections.first { $0.section == .fatDistribution }?.mismatchText)
        XCTAssertNil(ratioState.sections.first { $0.section == .wholeBody }?.mismatchText)
    }

    func testH7OnlyTheTotalMassEntered() {
        let state = sheet(entry(["weight": 100.0]))
        XCTAssertEqual(state.formMessage, "Add at least one scan figure besides total mass.")
        XCTAssertFalse(state.canSave)
        XCTAssertNil(state.draft)
        let withBodyFat = sheet(entry(["weight": 100.0, "body_fat": 30.0]))
        XCTAssertEqual(withBodyFat.formMessage, "Add at least one scan figure besides total mass.")
        XCTAssertFalse(withBodyFat.canSave)
    }

    func testH8AManualWeighInInTheChosenDaysWeek() {
        let line = "You have a weigh-in this week. It stays this week's weight; the scan keeps its own total."
        XCTAssertEqual(sheet(entry(F.scanA), outranks: true).weighInLine, line)
        XCTAssertNil(sheet(entry(F.scanA), outranks: false).weighInLine)
        XCTAssertTrue(sheet(entry(F.scanA), outranks: true).canSave, "a neutral line: Save stays enabled")
    }

    func testWeighInLineIsNotShownWithoutATotalMass() async throws {
        var noTotal = F.scanA
        noTotal.removeValue(forKey: "weight")
        XCTAssertNil(sheet(entry(noTotal), outranks: true).weighInLine, "never shown for a draft with no total mass")

        // The sheet model does not even ask: a weigh-in in the week changes nothing without a total.
        let h = try await harness(today: F.dayA)
        try await h.weighIns.save(weight: 101.0, waist: nil, unitSystem: .metric, takenAt: F.date(1_925_449_200))
        let model = BodyScanSheetModel(store: h.records, weighIns: h.weighIns, editing: nil, unitSystem: .metric,
                                       decimalSeparator: ".", today: { F.dayA })
        model.entry = entry(noTotal)
        await model.evaluate()
        XCTAssertNil(model.state.weighInLine)
    }

    /// H8 through the sheet model: it asks the resolver for the entry as typed.
    func testSheetModelShowsTheWeighInLineFromTheResolver() async throws {
        let h = try await harness(today: F.dayA)
        try await h.weighIns.save(weight: 101.0, waist: nil, unitSystem: .metric, takenAt: F.date(1_925_449_200))
        let model = BodyScanSheetModel(store: h.records, weighIns: h.weighIns, editing: nil, unitSystem: .metric,
                                       decimalSeparator: ".", today: { F.dayA })
        model.entry = entry(F.scanA)
        await model.evaluate()
        XCTAssertEqual(model.state.weighInLine,
                       "You have a weigh-in this week. It stays this week's weight; the scan keeps its own total.")

        // The same entry on 2031-01-13, the next week: the weigh-in is in another week.
        model.entry = entry(F.scanA, day: "2031-01-13")
        await model.evaluate()
        XCTAssertNil(model.state.weighInLine)
    }

    func testH9Editing() async throws {
        let a = try await scanA()
        let prefilled = BodyScanEntry(editing: a, unitSystem: .metric)
        XCTAssertEqual(prefilled.day, F.dayA)
        XCTAssertEqual(prefilled.note, F.noteA)
        XCTAssertEqual(prefilled.texts["weight"], "100.0")
        XCTAssertEqual(prefilled.texts["scan_bone_mass"], "3.00")
        XCTAssertEqual(prefilled.texts["scan_visceral_fat_mass"], "1000")
        XCTAssertEqual(prefilled.texts["scan_bmd"], "1.200")
        XCTAssertNil(prefilled.texts["scan_visceral_fat_area"], "a field not entered stays empty")
        let state = sheet(prefilled)
        XCTAssertTrue(state.canSave)
        XCTAssertEqual(state.draft, F.draftA, "saving an unchanged prefill writes the same figures")

        let imperial = BodyScanEntry(editing: a, unitSystem: .imperial)
        XCTAssertEqual(imperial.texts["weight"], "220.5", "prefilled in the display unit")
        XCTAssertEqual(sheet(imperial, unitSystem: .imperial).field(forTest: "weight")?.unit, "lb")
    }

    func testH10EditingDayChangedToOneThatAlreadyHasAScan() async throws {
        let state = sheet(entry(F.scanB, day: F.dayA), phase: .occupied)
        XCTAssertEqual(state.statusMessage, "Another scan is already recorded at that time.")

        // Through the model: nothing is written.
        let h = try await harness()
        try await h.save(F.draftA)
        let b = try await h.save(F.draftB)
        let before = try await h.everyRow()
        let model = BodyScanSheetModel(store: h.records, weighIns: h.weighIns, editing: b, unitSystem: .metric,
                                       decimalSeparator: ".", today: { "2031-06-04" })
        model.entry.day = F.dayA
        let saved = await model.save()
        XCTAssertNil(saved)
        XCTAssertEqual(model.phase, .occupied)
        XCTAssertEqual(model.state.statusMessage, "Another scan is already recorded at that time.")
        let after = try await h.everyRow()
        XCTAssertEqual(after, before, "nothing is written")
    }

    func testH11Saving() {
        let state = sheet(entry(F.scanA), phase: .saving)
        XCTAssertTrue(state.controlsDisabled)
        XCTAssertFalse(state.canSave)
    }

    func testH12SaveFailed() async throws {
        let state = sheet(entry(F.scanA), phase: .failed)
        XCTAssertEqual(state.statusMessage, "Couldn't save the scan. Nothing was changed.")
        XCTAssertEqual(field(state, "weight")?.text, "100.0", "the entries are kept")

        // Through the model, with every insert failing.
        let h = try await BodyRecordHarness.make(suites: suites, onDiskIn: try directories.make())
        try h.failEveryInsert()
        let model = BodyScanSheetModel(store: h.records, weighIns: h.weighIns, editing: nil, unitSystem: .metric,
                                       decimalSeparator: ".", today: { "2031-06-04" })
        model.entry = entry(F.scanA)
        let saved = await model.save()
        XCTAssertNil(saved)
        XCTAssertEqual(model.phase, .failed)
        XCTAssertEqual(model.state.statusMessage, "Couldn't save the scan. Nothing was changed.")
        let stored = try await h.everyRow()
        XCTAssertEqual(stored, [])
    }

    func testH13DeleteConfirmation() {
        XCTAssertEqual(P.scanDeleteConfirmation(),
                       BodyRecordConfirmation(title: "Delete this scan? Its total mass is removed from your weight history too.",
                                              confirmTitle: "Delete", cancelTitle: "Cancel"))
    }

    /// H14 is H2 at the largest text size: the same state.
    func testH14LargestTextSizeIsH2() {
        XCTAssertEqual(sheet(entry(F.scanA, note: F.noteA)), sheet(entry(F.scanA, note: F.noteA)))
    }

    // MARK: - §10.3 Scan detail

    func testI1AFullScan() async throws {
        let d = detail(try await scanA())
        XCTAssertEqual(d.sections.map(\.title),
                       ["Whole body", "Fat distribution", "Lean mass by region", "Bone density", "Energy"])
        XCTAssertEqual(d.sections.map { $0.figures.map(\.valueText) }, [
            ["100.0", "30.0", "67.0", "3.00", "70.0", "30.0"],
            ["1000", "36.0", "30.0", "1.20"],
            ["10.00", "4.90", "5.10", "20.00", "10.00", "10.00", "32.00"],
            ["1.200", "0.5", "0.4"],
            ["1900"],
        ])
        XCTAssertEqual(d.sections[1].figures.map(\.unit), ["g", "%", "%", "ratio"])
        XCTAssertEqual(d.sections[3].figures.map(\.unit), ["g/cm²", "SD", "SD"])
        XCTAssertEqual(d.sections[4].figures.first?.unit, "kcal/day")
        XCTAssertEqual(d.sections[4].figures.first?.caption, "Laboratory estimate. Not used by NOOP's calorie figures.")
        XCTAssertEqual(d.derived, [
            BodyScanDerivedRow(title: "Arms to legs", valueText: "50.0% of legs lean mass", caption: nil),
            BodyScanDerivedRow(title: "Left and right arm", valueText: "Right 3.9% more", caption: nil),
            BodyScanDerivedRow(title: "Left and right leg", valueText: "Equal", caption: nil),
        ])
        XCTAssertEqual(d.note, F.noteA)
        XCTAssertTrue(d.canEdit)
        XCTAssertTrue(d.canDelete)
        XCTAssertNil(d.importedText)
        XCTAssertNil(d.unreadableText)
        XCTAssertNil(d.conflictingText)
    }

    func testI2ASparseScan() async throws {
        let all = try await scans([F.draftC])
        let d = detail(try XCTUnwrap(all.first))
        XCTAssertEqual(d.sections.map(\.section), [.wholeBody, .leanMassByRegion], "a section with nothing entered is absent")
        XCTAssertEqual(d.sections[0].figures.map(\.key), ["weight", "scan_fat_mass", "scan_lean_mass", "scan_bone_mass"])
        XCTAssertEqual(d.sections[1].figures.map(\.key),
                       ["scan_arm_left_lean_mass", "scan_arm_right_lean_mass", "scan_legs_lean_mass"])
        XCTAssertNil(d.note)
        for figure in d.sections.flatMap(\.figures) {
            XCTAssertNotNil(F.scanC[figure.key], "only fields entered: \(figure.key)")
            XCTAssertNotEqual(figure.valueText, "—", figure.key)
        }
    }

    func testI3DerivedFigureNotAvailable() async throws {
        var noLegs = F.scanA
        for key in ["scan_legs_lean_mass", "scan_leg_left_lean_mass", "scan_leg_right_lean_mass"] {
            noLegs.removeValue(forKey: key)
        }
        let all = try await scans([BodyScanDraft(day: F.dayA, values: noLegs, note: nil)])
        let d = detail(try XCTUnwrap(all.first))
        XCTAssertEqual(d.derived.first, BodyScanDerivedRow(title: "Arms to legs",
                                                           valueText: "Not available. Enter arms and legs lean mass.",
                                                           caption: nil))
        XCTAssertEqual(d.derived.last?.valueText, "Not available. Enter both sides.")
        XCTAssertEqual(d.derived[1].valueText, "Right 3.9% more", "the arm figure is still available")
    }

    func testI4DerivedFigureFromTheTwoSides() async throws {
        let all = try await scans([F.draftC])
        let d = detail(try XCTUnwrap(all.first))
        XCTAssertEqual(d.derived.first?.valueText, "54.4% of legs lean mass")
        XCTAssertEqual(d.derived.first?.caption, "From left and right arm.")
        XCTAssertEqual(d.derived[1].valueText, "Equal")
        XCTAssertEqual(d.derived[2].valueText, "Not available. Enter both sides.")
    }

    func testDerivedBlockIsAbsentForAScanWithNoArmOrLegFigure() async throws {
        let all = try await scans([BodyScanDraft(day: F.dayA, values: ["weight": 100.0, "scan_fat_mass": 30.0], note: nil)])
        XCTAssertEqual(detail(try XCTUnwrap(all.first)).derived, [])
        XCTAssertNil(screen(all).latestScan?.derivedLine, "the card shows the derived line only with a value")
    }

    func testI5UnreadableRows() async throws {
        let h = try await harness()
        let d = detail(try await scanAWithUnreadableFat(h))
        XCTAssertTrue(d.unreadableText?.contains("could not be read") ?? false, d.unreadableText ?? "no line")
        XCTAssertEqual(d.unreadableLabels, ["Fat mass"], "naming the fields")
        XCTAssertFalse(d.sections.flatMap(\.figures).contains { $0.key == "scan_fat_mass" })
        XCTAssertTrue(d.canEdit, "an unreadable row does not block editing the rest")
    }

    func testI5bConflictingKeys() async throws {
        let h = try await harness()
        let d = detail(try await scanAWithConflictingFat(h))
        XCTAssertTrue(d.conflictingText?.hasSuffix("Open Lab Book to delete the one that is wrong.") ?? false)
        XCTAssertEqual(d.conflictingLabels, ["Fat mass"])
        XCTAssertFalse(d.canEdit, "no Edit")
        XCTAssertTrue(d.canDelete, "Delete stays for a typed scan")
        XCTAssertEqual(d.openLabBookTitle, "Open Lab Book")
    }

    func testI6ImportedScan() async throws {
        let h = try await harness()
        let d = detail(try await importedScanA(h))
        XCTAssertFalse(d.canEdit)
        XCTAssertFalse(d.canDelete)
        XCTAssertEqual(d.importedText, "Imported from CSV. Edit or delete its readings in Lab Book.")
        XCTAssertEqual(d.openLabBookTitle, "Open Lab Book")
    }

    /// I7: the scan detail leaves the stack when the scan is gone; the model answers nil for it.
    func testI7TheScanNoLongerExists() async throws {
        let h = try await harness()
        let a = try await h.save(F.draftA)
        let model = BodyRecordModel(store: h.records, unitSystem: { .metric }, locale: { F.british })
        XCTAssertTrue(model.screen.isLoading, "G1 until the first load ends")
        await model.load()
        XCTAssertEqual(model.scan(id: a.id)?.id, a.id)
        XCTAssertEqual(model.screen.latestScan?.scanId, a.id)

        try await h.records.delete(a)
        await model.load()
        XCTAssertNil(model.scan(id: a.id))
        XCTAssertEqual(model.screen.scansEmptyText, "No scans yet")
    }

    /// I8 is I1 at the largest text size: the same presentation.
    func testI8LargestTextSizeIsI1() async throws {
        let a = try await scanA()
        XCTAssertEqual(detail(a), detail(a))
    }

    /// V6 and §7.7: masses in kilograms follow the unit system; everything else stays in its unit.
    func testMassesFollowTheUnitSystemAndOtherUnitsDoNot() async throws {
        let all = try await scans([BodyScanDraft(day: F.dayA, values: F.scanA.merging(["weight": 220.5 / 2.20462]) { $1 },
                                                 note: nil)])
        let a = try XCTUnwrap(all.first)
        XCTAssertEqual(detail(a).sections[0].figures.first?.valueText, "100.0", "V6: shown as 100.0 kg")
        let imperial = detail(a, unitSystem: .imperial)
        XCTAssertEqual(imperial.sections[0].figures.map(\.unit), ["lb", "lb", "lb", "lb", "lb", "%"])
        XCTAssertEqual(imperial.sections[0].figures[0].valueText, "220.5")
        XCTAssertEqual(imperial.sections[0].figures[1].valueText, LabBookFormat.value(30.0 * 2.20462, key: "scan_fat_mass"))
        XCTAssertEqual(imperial.sections[0].figures[3].valueText, LabBookFormat.value(3.0 * 2.20462, key: "scan_bone_mass"))
        XCTAssertEqual(imperial.sections[1].figures[0].unit, "g", "grams are never converted")
        XCTAssertEqual(imperial.sections[1].figures[0].valueText, "1000")
        XCTAssertEqual(imperial.sections[3].figures[0].unit, "g/cm²")
    }

    // MARK: - §10.4 Scan comparison

    /// J1 and §13.3, row by row (recomputed from §7.3 before relying on it: every row agrees).
    func testJ1TwoScansAllMarkersInBoth() async throws {
        let all = try await scans([F.draftA, F.draftB])
        let c = compare(all)
        XCTAssertEqual(c.earlierScanId, F.scanId(takenAt: F.noonA))
        XCTAssertEqual(c.laterScanId, F.scanId(takenAt: F.noonB))
        XCTAssertNil(c.oneScanText)
        XCTAssertNil(c.emptyText)
        // key, earlier, later, change (signed, with unit or "points"), percent, direction
        let expected: [(String, String, String, String?, String?, String?)] = [
            ("weight", "100.0", "95.0", "-5.0 kg", "-5.0%", "down"),
            ("scan_fat_mass", "30.0", "26.0", "-4.0 kg", "-13.3%", "down"),
            ("scan_lean_mass", "67.0", "66.0", "-1.0 kg", "-1.5%", "down"),
            ("scan_bone_mass", "3.00", "3.00", "No change", nil, nil),
            ("scan_fat_free_mass", "70.0", "69.0", "-1.0 kg", "-1.4%", "down"),
            ("body_fat", "30.0", "27.4", "-2.6 points", nil, "down"),
            ("scan_visceral_fat_mass", "1000", "800", "-200 g", "-20.0%", "down"),
            ("scan_visceral_fat_area", "not entered", "80", nil, nil, nil),
            ("scan_android_fat_pct", "36.0", "30.0", "-6.0 points", nil, "down"),
            ("scan_gynoid_fat_pct", "30.0", "26.0", "-4.0 points", nil, "down"),
            ("scan_android_gynoid_ratio", "1.20", "1.15", "-0.05 ratio", "-4.2%", "down"),
            ("scan_arms_lean_mass", "10.00", "10.40", "+0.40 kg", "4.0%", "up"),
            ("scan_arm_left_lean_mass", "4.90", "5.20", "+0.30 kg", "6.1%", "up"),
            ("scan_arm_right_lean_mass", "5.10", "5.20", "+0.10 kg", "2.0%", "up"),
            ("scan_legs_lean_mass", "20.00", "19.60", "-0.40 kg", "-2.0%", "down"),
            ("scan_leg_left_lean_mass", "10.00", "9.80", "-0.20 kg", "-2.0%", "down"),
            ("scan_leg_right_lean_mass", "10.00", "9.80", "-0.20 kg", "-2.0%", "down"),
            ("scan_trunk_lean_mass", "32.00", "31.50", "-0.50 kg", "-1.6%", "down"),
            ("scan_bmd", "1.200", "not entered", nil, nil, nil),
            ("scan_bmd_t_score", "0.5", "not entered", nil, nil, nil),
            ("scan_bmd_z_score", "0.4", "not entered", nil, nil, nil),
            ("scan_rmr_lab_estimate", "1900", "1850", "-50 kcal/day", "-2.6%", "down"),
        ]
        XCTAssertEqual(c.rows.map(\.key), expected.map(\.0), "field order; no row for a field in neither scan")
        for (row, want) in zip(c.rows, expected) {
            XCTAssertEqual(row.earlierText, want.1, row.key)
            XCTAssertEqual(row.laterText, want.2, row.key)
            XCTAssertEqual(signed(row.changeText), want.3, row.key)
            XCTAssertEqual(signed(row.percentText).map { $0.hasPrefix("-") ? $0 : $0.replacingOccurrences(of: "+", with: "") },
                           want.4, row.key)
            XCTAssertEqual(row.directionText, want.5, row.key)
        }
        let armsToLegs = try XCTUnwrap(c.derivedRows.first)
        XCTAssertEqual(armsToLegs.label, "Arms to legs")
        XCTAssertTrue(armsToLegs.earlierText.contains("50.0"), armsToLegs.earlierText)
        XCTAssertTrue(armsToLegs.laterText.contains("53.1"), armsToLegs.laterText)
        XCTAssertEqual(signed(armsToLegs.changeText), "+3.1 points")
        XCTAssertNil(armsToLegs.percentText, "hidden for a percentage")
        XCTAssertEqual(armsToLegs.directionText, "up")
        XCTAssertEqual(c.derivedRows.map(\.label), ["Arms to legs", "Left and right arm", "Left and right leg"])
        XCTAssertNil(c.derivedRows[1].changeText, "a side difference is shown without a change")
    }

    /// J2: B and C, the default (the two newest).
    func testJ2AMarkerOnlyInTheEarlierScan() async throws {
        let all = try await scans([F.draftA, F.draftB, F.draftC])
        let c = compare(all)
        XCTAssertEqual(c.earlierScanId, F.scanId(takenAt: F.noonB))
        XCTAssertEqual(c.laterScanId, F.scanId(takenAt: F.noonC))
        let ffm = try XCTUnwrap(c.rows.first { $0.key == "scan_fat_free_mass" })
        XCTAssertEqual(ffm.earlierText, "69.0")
        XCTAssertEqual(ffm.laterText, "not entered")
        XCTAssertNil(ffm.changeText, "no change")
        XCTAssertNil(ffm.percentText)
        XCTAssertNil(ffm.directionText)
    }

    func testJ3AMarkerOnlyInTheLaterScan() async throws {
        let all = try await scans([F.draftA, F.draftB])
        let area = try XCTUnwrap(compare(all).rows.first { $0.key == "scan_visceral_fat_area" })
        XCTAssertEqual(area.earlierText, "not entered")
        XCTAssertEqual(area.laterText, "80")
        XCTAssertNil(area.changeText)
    }

    func testJ4AMarkerInNeither() async throws {
        let all = try await scans([F.draftA, F.draftC])
        let c = compare(all)
        XCTAssertFalse(c.rows.contains { $0.key == "scan_visceral_fat_area" }, "the row is absent")
        XCTAssertTrue(c.rows.contains { $0.key == "scan_bmd" }, "a field in one scan keeps its row")
    }

    func testJ5NoChange() async throws {
        let all = try await scans([F.draftB, F.draftC])
        let lean = try XCTUnwrap(compare(all).rows.first { $0.key == "scan_lean_mass" })
        XCTAssertEqual(lean.changeText, "No change")
        XCTAssertNil(lean.directionText)
    }

    func testJ6OneScanOnly() async throws {
        let all = try await scans([F.draftA])
        let c = compare(all)
        XCTAssertEqual(c.oneScanText, "One scan so far. A second scan makes a comparison.")
        XCTAssertTrue(c.rows.allSatisfy { $0.changeText == nil })
        let shown = Set(c.rows.flatMap { [$0.earlierText, $0.laterText] }).subtracting(["not entered"])
        XCTAssertTrue(shown.isSuperset(of: ["100.0", "30.0", "1900"]), "that scan's values: \(shown)")
    }

    func testJ7NoScans() {
        let c = compare([])
        XCTAssertEqual(c.emptyText, "No scans yet")
        XCTAssertEqual(c.addScanTitle, "Add a scan")
        XCTAssertEqual(c.rows, [])
        XCTAssertEqual(c.derivedRows, [])
    }

    func testJ8TheSameScanCannotBeChosenTwice() async throws {
        let all = try await scans([F.draftA, F.draftB, F.draftC])
        let a = F.scanId(takenAt: F.noonA), b = F.scanId(takenAt: F.noonB), c = F.scanId(takenAt: F.noonC)
        let chosen = compare(all, a, c)
        XCTAssertEqual(chosen.earlierChoices.map(\.scanId).sorted(), [a, b].sorted())
        XCTAssertEqual(chosen.laterChoices.map(\.scanId).sorted(), [b, c].sorted())
        XCTAssertFalse(chosen.earlierChoices.contains { $0.scanId == chosen.laterScanId })
        XCTAssertFalse(chosen.laterChoices.contains { $0.scanId == chosen.earlierScanId })
    }

    /// J9: scans entered out of order (A, C, B) compare exactly as J1.
    func testJ9ScansEnteredOutOfOrder() async throws {
        let inOrder = try await scans([F.draftA, F.draftB])
        let outOfOrder = try await scans([F.draftA, F.draftC, F.draftB])
        let j1 = compare(inOrder)
        let j9 = compare(outOfOrder, F.scanId(takenAt: F.noonA), F.scanId(takenAt: F.noonB))
        XCTAssertEqual(j9.rows, j1.rows)
        XCTAssertEqual(j9.derivedRows, j1.derivedRows)
    }

    /// Fault F6: whatever is chosen, the scan with the smaller instant is the left column.
    func testComparisonAlwaysPutsTheOlderScanFirst() async throws {
        let all = try await scans([F.draftA, F.draftB])
        let a = F.scanId(takenAt: F.noonA), b = F.scanId(takenAt: F.noonB)
        let reversed = compare(all, b, a)
        XCTAssertEqual(reversed.earlierScanId, a)
        XCTAssertEqual(reversed.laterScanId, b)
        XCTAssertEqual(reversed.rows, compare(all, a, b).rows)
        XCTAssertEqual(reversed.rows.first { $0.key == "weight" }?.earlierText, "100.0")
        XCTAssertEqual(reversed.rows.first { $0.key == "weight" }?.directionText, "down")
    }

    func testJ10ADerivedFigureAvailableInOneScanOnly() async throws {
        let all = try await scans([F.draftB, F.draftC])
        let legs = try XCTUnwrap(compare(all).derivedRows.first { $0.label == "Left and right leg" })
        XCTAssertEqual(legs.earlierText, "Equal")
        XCTAssertTrue(legs.laterText.localizedCaseInsensitiveContains("not available"), legs.laterText)
        XCTAssertNil(legs.changeText)
    }

    func testJ10bAFieldUnreadableOrConflictingInOneScan() async throws {
        let h = try await harness()
        _ = try await scanAWithUnreadableFat(h)
        try await h.save(F.draftB)
        let c = compare(await h.records.scans())
        let fat = try XCTUnwrap(c.rows.first { $0.key == "scan_fat_mass" })
        XCTAssertEqual(fat.earlierText, "not entered", "treated as not entered in that scan")
        XCTAssertEqual(fat.laterText, "26.0")
        XCTAssertNil(fat.changeText)
        XCTAssertTrue(c.notes.contains { $0.contains("could not be read") }, "\(c.notes)")

        let h2 = try await harness()
        _ = try await scanAWithConflictingFat(h2)
        try await h2.save(F.draftB)
        let c2 = compare(await h2.records.scans())
        XCTAssertEqual(c2.rows.first { $0.key == "scan_fat_mass" }?.earlierText, "not entered")
        XCTAssertTrue(c2.notes.contains { $0.contains("two different stored values") }, "\(c2.notes)")
    }

    func testJ11LargestTextSizeStacksTheRows() {
        XCTAssertTrue(P.comparisonUsesStackedRows(accessibilityTextSize: true))
        XCTAssertFalse(P.comparisonUsesStackedRows(accessibilityTextSize: false))
    }

    func testPercentChangeIsHiddenForPercentAndScoreFields() async throws {
        var later = F.scanC
        later["scan_bmd_t_score"] = 0.7
        later["scan_bmd_z_score"] = 0.2
        later["body_fat"] = 26.6
        let all = try await scans([F.draftA, BodyScanDraft(day: F.dayC, values: later, note: nil)])
        let c = compare(all)
        for key in ["body_fat", "scan_bmd_t_score", "scan_bmd_z_score"] {
            let row = try XCTUnwrap(c.rows.first { $0.key == key }, key)
            XCTAssertNotNil(row.changeText, key)
            XCTAssertNil(row.percentText, key)
        }
        XCTAssertTrue(c.rows.first { $0.key == "body_fat" }?.changeText?.hasSuffix("points") ?? false)
        XCTAssertNotNil(c.rows.first { $0.key == "scan_fat_mass" }?.percentText, "a mass shows its percent")
    }

    // MARK: - §10.5 Benchmarks

    func testK1SheetNew() {
        let choices = P.benchmarkChoices()
        XCTAssertEqual(choices.map(\.key), ["bench_pushup_reps", "bench_incline_pushup_reps", "bench_knee_pushup_reps",
                                            "bench_pullup_reps", "bench_dead_hang_s", "bench_plank_s",
                                            "bench_wall_sit_s", "bench_grip_kg", nil])
        XCTAssertEqual(choices.map(\.name), ["Push-ups, most in one set", "Incline push-ups, most in one set",
                                             "Knee push-ups, most in one set", "Pull-ups, most in one set",
                                             "Dead hang, longest hold", "Plank, longest hold", "Wall sit, longest hold",
                                             "Grip strength", "Custom benchmark"])
        let state = P.benchmarkEntry(BenchmarkEntry(key: "bench_grip_kg"), decimalSeparator: ".")
        XCTAssertEqual(state.unit, "kg")
        XCTAssertFalse(state.canSave, "nothing typed yet")
        XCTAssertNil(state.errorText)
    }

    func testK2SheetATimedBenchmark() {
        let seconds = P.benchmarkEntry(BenchmarkEntry(key: "bench_dead_hang_s", text: "45"), decimalSeparator: ".")
        XCTAssertTrue(seconds.acceptsDuration)
        XCTAssertEqual(seconds.value, 45)
        XCTAssertTrue(seconds.canSave)
        let minutes = P.benchmarkEntry(BenchmarkEntry(key: "bench_plank_s", text: "1:30"), decimalSeparator: ".")
        XCTAssertEqual(minutes.value, 90)
        XCTAssertEqual(minutes.unit, "s")
        XCTAssertFalse(P.benchmarkEntry(BenchmarkEntry(key: "bench_pushup_reps", text: "10"),
                                        decimalSeparator: ".").acceptsDuration)
    }

    func testK3SheetCustom() {
        XCTAssertEqual(P.customBenchmarkUnits, ["reps", "s", "kg"])
        let unnamed = P.benchmarkEntry(BenchmarkEntry(key: nil, customName: "", customUnit: "s", text: "60"),
                                       decimalSeparator: ".")
        XCTAssertEqual(unnamed.unitOptions, ["reps", "s", "kg"])
        XCTAssertNil(unnamed.key, "no key until a name is typed")
        XCTAssertFalse(unnamed.canSave)
        let named = P.benchmarkEntry(BenchmarkEntry(key: nil, customName: "Fixture carry", customUnit: "s", text: "60"),
                                     decimalSeparator: ".")
        XCTAssertEqual(named.key, F.customCarryKey)
        XCTAssertEqual(named.unit, "s")
        XCTAssertEqual(named.value, 60)
        XCTAssertTrue(named.canSave)
    }

    func testK4SheetInvalidValue() {
        let fractional = P.benchmarkEntry(BenchmarkEntry(key: "bench_pushup_reps", text: "12.5"), decimalSeparator: ".")
        XCTAssertEqual(fractional.errorText, "Enter a whole number.")
        XCTAssertFalse(fractional.canSave)
        XCTAssertNil(fractional.value)
        let letters = P.benchmarkEntry(BenchmarkEntry(key: "bench_grip_kg", text: "abc"), decimalSeparator: ".")
        XCTAssertEqual(letters.errorText, "Use digits and one decimal separator.")
        let tooMany = P.benchmarkEntry(BenchmarkEntry(key: "bench_pushup_reps", text: "1001"), decimalSeparator: ".")
        XCTAssertTrue(tooMany.errorText?.hasPrefix("Enter a value between ") ?? false, tooMany.errorText ?? "none")
        let grip = P.benchmarkEntry(BenchmarkEntry(key: "bench_grip_kg", text: "0.5"), decimalSeparator: ".")
        XCTAssertTrue(grip.errorText?.hasPrefix("Enter a value between ") ?? false, grip.errorText ?? "none")
        let comma = P.benchmarkEntry(BenchmarkEntry(key: "bench_grip_kg", text: "42,5"), decimalSeparator: ",")
        XCTAssertEqual(comma.value, 42.5)
    }

    func testK5DetailSeveralReadings() {
        let d = P.benchmarkDetail(BenchmarkHistory(key: "bench_dead_hang_s", readings: deadHang()), unitSystem: .metric,
                                  locale: F.british)
        XCTAssertEqual(d.title, "Dead hang, longest hold")
        XCTAssertEqual(d.rows.map(\.valueText), ["45", "30", "20"], "newest first")
        XCTAssertEqual(d.rows.map(\.note), ["Fixture bar", nil, nil])
        XCTAssertEqual(d.rows.map { signed($0.changeText) }, ["+15 s", "+10 s", nil], "against the previous reading")
        XCTAssertEqual(d.rows.map(\.unit), ["s", "s", "s"])
        XCTAssertNil(d.oneReadingText)
        XCTAssertEqual(Set(d.rows.map(\.rowId)).count, 3, "delete on each")
    }

    func testK6DetailOneReading() {
        let d = P.benchmarkDetail(carry(), unitSystem: .metric, locale: F.british)
        XCTAssertEqual(d.rows.count, 1)
        XCTAssertNil(d.rows.first?.changeText)
        XCTAssertEqual(d.oneReadingText, "One reading so far.")
    }

    func testK7DeleteConfirmation() {
        XCTAssertEqual(P.benchmarkDeleteConfirmation(),
                       BodyRecordConfirmation(title: "Delete this reading?", confirmTitle: "Delete", cancelTitle: "Cancel"))
    }

    /// K8 is K5 at the largest text size: the same presentation.
    func testK8LargestTextSizeIsK5() {
        let history = BenchmarkHistory(key: "bench_dead_hang_s", readings: deadHang())
        XCTAssertEqual(P.benchmarkDetail(history, unitSystem: .metric, locale: F.british),
                       P.benchmarkDetail(history, unitSystem: .metric, locale: F.british))
    }

    /// K2: seconds, or minutes and seconds.
    func testDurationParsesSecondsAndMinutesSeconds() {
        XCTAssertEqual(P.parseDuration("45", decimalSeparator: "."), 45)
        XCTAssertEqual(P.parseDuration(" 45 ", decimalSeparator: "."), 45)
        XCTAssertEqual(P.parseDuration("1:30", decimalSeparator: "."), 90)
        XCTAssertEqual(P.parseDuration("0:05", decimalSeparator: "."), 5)
        XCTAssertEqual(P.parseDuration("10:00", decimalSeparator: "."), 600)
        XCTAssertEqual(P.parseDuration("90", decimalSeparator: "."), 90, "seconds alone may exceed 59")
    }

    func testDurationRejectsSixtyOrMoreSeconds() {
        for text in ["1:60", "1:99", "0:60", "", "abc", ":30", "1:", "1:30:00", "nan", "1:3a"] {
            XCTAssertNil(P.parseDuration(text, decimalSeparator: "."), text)
        }
        XCTAssertEqual(P.parseDuration("1:59", decimalSeparator: "."), 119)
    }

    // MARK: - §8.4, H8: the weigh-in line asks the resolver

    /// The variants of §13.4 the line is decided for, each with the manual rows beside scan A.
    private func weighInVariants() -> [(name: String, manual: [LabMarkerRow], today: String, expected: Bool)] {
        func manual(_ epoch: Int, _ day: String, _ value: Double, unit: String = "kg") -> LabMarkerRow {
            LabMarkerRow(id: "weight-\(epoch)-0A1B2C3D", deviceId: F.active, markerKey: "weight",
                         category: "bodyMeasurement", day: day, takenAt: epoch, value: value, valueText: nil,
                         unit: unit, source: BodyMeasurementResolver.weighInSource, note: nil, referenceText: nil)
        }
        return [
            ("V7", [manual(F.sevenA, F.dayA, 101.0)], F.dayA, true),
            ("V7a", [], F.dayA, false),
            ("V7b", [manual(1_925_449_200, "2031-01-06", 101.0)], F.dayA, true),
            ("V7c", [manual(1_925_362_800, "2031-01-05", 101.0)], F.dayA, false),
            ("V7e", [manual(F.sevenA, F.dayA, 16.0, unit: "stone")], F.dayA, false),
            ("V7f", [manual(1_925_794_800, "2031-01-10", 101.0)], "2031-01-10", true),
        ]
    }

    private func draftWeightRow() -> LabMarkerRow {
        F.scanRow("weight", value: 100.0, deviceId: F.active, day: F.dayA, takenAt: F.noonA, suffix: "D4AF7000")
    }

    /// Faults F45 and F46. True for V7, V7b and V7f; false for V7a, V7c and V7e.
    func testWeighInThisWeekLineShowsOnlyWhenTheScanWouldBeOutranked() {
        for variant in weighInVariants() {
            XCTAssertEqual(P.weighInOutranksDraft(draftRow: draftWeightRow(), weighInRows: variant.manual,
                                                  today: variant.today),
                           variant.expected, variant.name)
        }
        // V7f looked at on the scan's own day: the Friday weigh-in is after the as-of day.
        let v7f = weighInVariants().first { $0.name == "V7f" }!
        XCTAssertFalse(P.weighInOutranksDraft(draftRow: draftWeightRow(), weighInRows: v7f.manual, today: F.dayA))
    }

    /// For every variant the line is true exactly when, after the save, the resolver's series as of
    /// today holds no entry for the scan's weight row.
    func testWeighInLineAgreesWithTheResolverForEveryVariant() async throws {
        for variant in weighInVariants() {
            let h = try await harness(today: variant.today)
            if !variant.manual.isEmpty { try await h.seed(variant.manual) }
            let weighInRows = await h.weighIns.readings(.weight)
                .filter { $0.source == BodyMeasurementResolver.weighInSource }
            let line = P.weighInOutranksDraft(draftRow: draftWeightRow(), weighInRows: weighInRows,
                                              today: variant.today)

            let scan = try await h.save(F.draftA)
            await h.provider.refresh()
            let scanRowId = try XCTUnwrap(scan.rows["weight"]?.first?.id)
            let candidates = h.provider.candidates(.weight)
            let series = BodyMeasurementResolver.series(.weight, candidates: candidates, policy: .unified,
                                                        asOf: variant.today)
            let held = series.contains { $0.rowId == scanRowId }
            XCTAssertEqual(line, !held, variant.name)
            XCTAssertEqual(line, variant.expected, variant.name)
        }
    }

    // MARK: - Across every state

    func testNoStateRendersAMissingValueAsZero() async throws {
        let all = try await scans([F.draftA, F.draftC])
        let c = try XCTUnwrap(all.last)
        for figure in detail(c).sections.flatMap(\.figures) {
            XCTAssertNotNil(c.values[figure.key], "a figure is shown only when entered: \(figure.key)")
        }
        for figure in screen(all).latestScan?.figures ?? [] {
            XCTAssertNotNil(c.values[figure.key], figure.key)
        }
        for row in compare(all).rows {
            if all[0].values[row.key] == nil { XCTAssertEqual(row.earlierText, "not entered", row.key) }
            if c.values[row.key] == nil { XCTAssertEqual(row.laterText, "not entered", row.key) }
        }
        let empty = sheet(BodyScanEntry(day: F.dayA))
        XCTAssertTrue(empty.sections.flatMap(\.fields).allSatisfy { $0.text.isEmpty }, "an empty field is empty, never 0")
    }

    func testAConflictingKeyIsNeverRenderedAsANumber() async throws {
        let h = try await harness()
        let a = try await scanAWithConflictingFat(h)
        try await h.save(F.draftB)
        let all = await h.records.scans()
        var texts = strings(in: detail(a)) + strings(in: screen([a])) + strings(in: compare(all))
        texts += strings(in: P.healthRow(enabled: true, scans: all, locale: F.british) as Any)
        XCTAssertFalse(texts.contains { $0.contains("31.0") }, "the conflicting 31.0 is never shown")
        XCTAssertFalse(detail(a).sections.flatMap(\.figures).contains { $0.key == "scan_fat_mass" },
                       "nor the first row's 30.0")
    }

    func testNoStringContainsAnInterpolatedNilNaNOrInfinity() async throws {
        let h = try await harness()
        _ = try await scanAWithUnreadableFat(h)
        try await h.save(F.draftB)
        try await h.save(F.draftC)
        let all = await h.records.scans()
        var texts: [String] = []
        texts += strings(in: screen(all, benchmarkHistories() + [carry()]))
        texts += strings(in: screen(all, unitSystem: .imperial))
        for scan in all { texts += strings(in: detail(scan)) + strings(in: detail(scan, unitSystem: .imperial)) }
        texts += strings(in: compare(all)) + strings(in: compare([])) + strings(in: compare([all[0]]))
        // Typed garbage: the messages the sheet derives from it, not the typed text it echoes back.
        var garbage = BodyScanEntry(day: F.dayA)
        garbage.texts = ["weight": "inf", "scan_fat_mass": "nan", "scan_lean_mass": "1e400", "scan_bmd": "-0"]
        let garbageState = sheet(garbage)
        texts += garbageState.sections.flatMap { $0.fields.compactMap(\.errorText) + $0.fields.compactMap(\.storedAsText) }
        texts += [garbageState.formMessage, garbageState.weighInLine, garbageState.statusMessage].compactMap { $0 }
        texts += strings(in: sheet(entry(F.scanA), outranks: true))
        texts += strings(in: P.benchmarkDetail(BenchmarkHistory(key: "bench_dead_hang_s", readings: deadHang()),
                                               unitSystem: .metric, locale: F.british))
        texts += strings(in: P.benchmarkEntry(BenchmarkEntry(key: "bench_plank_s", text: "inf"), decimalSeparator: "."))
        XCTAssertFalse(texts.isEmpty)
        let negativeZero = try NSRegularExpression(pattern: "(^|[^0-9.])[-−]0(\\.0+)?($|[^0-9.])")
        for text in texts {
            for banned in ["nil", "Optional(", "nan", "NaN", "inf", "Infinity"] {
                XCTAssertFalse(text.contains(banned), "\"\(banned)\" in \"\(text)\"")
            }
            XCTAssertEqual(negativeZero.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)), 0,
                           "a negative zero in \"\(text)\"")
        }
    }

    /// For every body-record key and a spread of in-range values, the displayed value is
    /// `LabBookFormat.value` of the stored value (metric display).
    func testEveryDisplayedScanValueEqualsLabBookFormat() async throws {
        let h = try await harness()
        let numeric = BodyScanField.all.filter { $0.range != nil }
        let fractions = [0.137, 0.5, 0.9969]
        for (index, fraction) in fractions.enumerated() {
            var values: [String: Double] = [:]
            for field in numeric {
                let range = try XCTUnwrap(field.range)
                values[field.key] = range.lowerBound + (range.upperBound - range.lowerBound) * fraction + 0.00049
                if values[field.key]! > range.upperBound { values[field.key] = range.upperBound }
            }
            let day = CanonicalDay.key(CanonicalDay.number(F.dayA)! + index)
            try await h.save(BodyScanDraft(day: day, values: values, note: nil))
        }
        for scan in await h.records.scans() {
            let figures = detail(scan).sections.flatMap(\.figures)
            XCTAssertEqual(figures.count, numeric.count)
            for figure in figures {
                let stored = try XCTUnwrap(scan.values[figure.key])
                XCTAssertEqual(figure.valueText, LabBookFormat.value(stored, key: figure.key), figure.key)
                XCTAssertEqual(figure.unit, BodyScanField.field(for: figure.key)?.storedUnit, figure.key)
            }
        }
    }
}

private extension BodyScanSheetState {
    func field(forTest key: String) -> BodyScanSheetField? { sections.flatMap(\.fields).first { $0.key == key } }
}
