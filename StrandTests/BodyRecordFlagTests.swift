// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/stage-4.md §9.4, §9.5, §10.7, §12.4, §12.6 and ruling A4,
// declared in full at the top of BodyRecordTestSupport.swift. This file calls:
//
//     enum BodyRecordSettings {
//         static let enabledKey = "noop.bodyRecordEnabled"
//         static let labReportUnitsKey = "noop.labReportUnitsEnabled"
//         @MainActor static let enabledFlag: ObservableDefaultsFlag
//         @MainActor static let labReportUnitsFlag: ObservableDefaultsFlag
//         static func csvScope(bodyRecordEnabled: Bool) -> MarkerCatalogScope
//     }
//     BodyRecordPresenter.healthRow(enabled:scans:locale:) -> BodyRecordHealthRow?
//     CutScorecardPresenter.history(weights:waists:appleHealth:unitSystem:locale:today:bodyRecordEnabled:)
//         with `bodyRecordEnabled: Bool = false`; WeighInHistoryRow.scanId: String?
//     LabMarkerCsvImport.parse(text:scope:)                        (§7.1, package 4-4a)
//     #if DEBUG: DemoScreenPrefixes.bodyRecord                     (ruling A4)
//
// The shared `ObservableDefaultsFlag` is used as it exists (scaffolding): tests build their own
// instances over a private defaults suite and never write `UserDefaults.standard`. The two static
// instances are only read: their keys are compared, and reading never writes.
//
// Synthetic values only: the Fixture Person.

import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

@MainActor
final class BodyRecordFlagTests: XCTestCase {
    private typealias F = BodyRecordFixture
    private let suites = BodyRecordSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    func testBothFlagsDefaultToOff() {
        XCTAssertEqual(BodyRecordSettings.enabledKey, "noop.bodyRecordEnabled")
        XCTAssertEqual(BodyRecordSettings.labReportUnitsKey, "noop.labReportUnitsEnabled")
        XCTAssertEqual(BodyRecordSettings.enabledFlag.key, BodyRecordSettings.enabledKey)
        XCTAssertEqual(BodyRecordSettings.labReportUnitsFlag.key, BodyRecordSettings.labReportUnitsKey)

        let defaults = suites.make("BodyRecordFlagTests")
        let records = ObservableDefaultsFlag(key: BodyRecordSettings.enabledKey, defaults: defaults)
        let units = ObservableDefaultsFlag(key: BodyRecordSettings.labReportUnitsKey, defaults: defaults)
        XCTAssertFalse(records.isEnabled)
        XCTAssertFalse(units.isEnabled)
        XCTAssertNil(defaults.object(forKey: BodyRecordSettings.enabledKey), "reading never writes")
        XCTAssertNil(defaults.object(forKey: BodyRecordSettings.labReportUnitsKey))
    }

    func testEachFlagFollowsAWriteToItsOwnKeyOnly() {
        let defaults = suites.make("BodyRecordFlagTests")
        let records = ObservableDefaultsFlag(key: BodyRecordSettings.enabledKey, defaults: defaults)
        let units = ObservableDefaultsFlag(key: BodyRecordSettings.labReportUnitsKey, defaults: defaults)

        records.set(true)
        XCTAssertTrue(records.isEnabled)
        XCTAssertFalse(units.isEnabled, "the other flag is untouched")
        XCTAssertTrue(defaults.bool(forKey: BodyRecordSettings.enabledKey))
        XCTAssertNil(defaults.object(forKey: BodyRecordSettings.labReportUnitsKey))

        defaults.set(true, forKey: BodyRecordSettings.labReportUnitsKey)   // a write by anyone else
        XCTAssertTrue(units.isEnabled)
        XCTAssertTrue(records.isEnabled)

        records.set(false)
        XCTAssertFalse(records.isEnabled)
        XCTAssertTrue(units.isEnabled)
    }

    /// §12.6: the route is reached only from the Health row, which exists only while the flag is on.
    func testScreenIsUnreachableWhileTheFlagIsOff() async throws {
        let h = try await BodyRecordHarness.make(suites: suites)
        try await h.save(F.draftA)
        let stored = await h.records.scans()
        XCTAssertNil(BodyRecordPresenter.healthRow(enabled: false, scans: stored, locale: F.british))
        XCTAssertNil(BodyRecordPresenter.healthRow(enabled: false, scans: [], locale: F.british))
        XCTAssertNotNil(BodyRecordPresenter.healthRow(enabled: true, scans: stored, locale: F.british))
    }

    /// §4.4, §7.1: the markers CSV scope follows the flag; off, the output is byte-identical to today.
    func testCsvScopeFollowsTheFlag() {
        XCTAssertEqual(BodyRecordSettings.csvScope(bodyRecordEnabled: false), .builtIn)
        XCTAssertEqual(BodyRecordSettings.csvScope(bodyRecordEnabled: true), .withBodyRecord)

        let csv = """
            date,marker,value,unit
            2031-01-08,Fat mass (scan),30.0,kg
            2031-01-08,Total mass,100.0,kg
            2031-01-08,LDL,2.6,mmol/L
            """
        let off = LabMarkerCsvImport.parse(text: csv, scope: BodyRecordSettings.csvScope(bodyRecordEnabled: false))
        XCTAssertEqual(off, LabMarkerCsvImport.parse(text: csv), "flag off: exactly today's import")
        XCTAssertFalse(off.rows.contains { MarkerCatalog.isScanOnlyMarker($0.markerKey) })
        XCTAssertFalse(off.rows.contains { $0.markerKey == "weight" }, "\"Total mass\" is no alias in the built-in scope")
        XCTAssertTrue(off.rows.contains { $0.markerKey.hasPrefix("custom_") })

        let on = LabMarkerCsvImport.parse(text: csv, scope: BodyRecordSettings.csvScope(bodyRecordEnabled: true))
        XCTAssertEqual(Set(on.rows.map(\.markerKey)), ["scan_fat_mass", "weight", "ldl"])
        XCTAssertEqual(on.customMarkerKeys, [])
    }

    /// §10.7, flag off: a `body-scan` weight row is an ordinary Lab Book row, as every non-manual
    /// row is today. The defaulted parameter gives the same list as passing false.
    func testHistoryTreatsAScanRowAsPlainLabBookWhileTheFlagIsOff() async throws {
        let h = try await BodyRecordHarness.make(suites: suites, today: F.dayA)
        try await h.save(F.draftA)
        try await h.weighIns.save(weight: 101.0, waist: nil, unitSystem: .metric, takenAt: F.date(F.sevenA))
        let weights = await h.weighIns.readings(.weight)

        let off = CutScorecardPresenter.history(weights: weights, waists: [], appleHealth: [], unitSystem: .metric,
                                                locale: F.british, today: F.dayA, bodyRecordEnabled: false)
        let omitted = CutScorecardPresenter.history(weights: weights, waists: [], appleHealth: [], unitSystem: .metric,
                                                    locale: F.british, today: F.dayA)
        XCTAssertEqual(off, omitted, "the parameter defaults to off")
        let scanRow = try XCTUnwrap(off.rows.first { $0.weightRow?.source == MarkerCatalog.scanSource })
        XCTAssertTrue(scanRow.caption.hasSuffix(" · Lab Book"), scanRow.caption)
        XCTAssertFalse(scanRow.caption.contains("body scan"))
        XCTAssertTrue(scanRow.canEdit)
        XCTAssertTrue(scanRow.canDelete)
        XCTAssertNil(scanRow.scanId)
        XCTAssertTrue(off.rows.allSatisfy { $0.scanId == nil })
    }

    /// §10.7, flag on: the scan row is captioned as a scan, is read-only there, and opens its scan.
    /// Every other row is exactly as with the flag off.
    func testHistoryMakesAScanRowReadOnlyAndRoutedWhileTheFlagIsOn() async throws {
        let h = try await BodyRecordHarness.make(suites: suites, today: F.dayA)
        let scan = try await h.save(F.draftA)
        try await h.weighIns.save(weight: 101.0, waist: nil, unitSystem: .metric, takenAt: F.date(F.sevenA))
        let weights = await h.weighIns.readings(.weight)

        let on = CutScorecardPresenter.history(weights: weights, waists: [], appleHealth: [], unitSystem: .metric,
                                               locale: F.british, today: F.dayA, bodyRecordEnabled: true)
        let off = CutScorecardPresenter.history(weights: weights, waists: [], appleHealth: [], unitSystem: .metric,
                                                locale: F.british, today: F.dayA, bodyRecordEnabled: false)
        let scanRow = try XCTUnwrap(on.rows.first { $0.weightRow?.source == MarkerCatalog.scanSource })
        XCTAssertTrue(scanRow.caption.hasSuffix(" · Lab Book · body scan"), scanRow.caption)
        XCTAssertTrue(scanRow.caption.hasPrefix("Not the weekly point"), "stage 1's lead (R44): \(scanRow.caption)")
        XCTAssertFalse(scanRow.canEdit)
        XCTAssertFalse(scanRow.canDelete)
        XCTAssertEqual(scanRow.scanId, scan.id)

        XCTAssertEqual(on.rows.map(\.id), off.rows.map(\.id), "the same rows are listed")
        XCTAssertEqual(on.rows.map(\.representsWeek), off.rows.map(\.representsWeek), "the mark is stage 1's, unchanged")
        XCTAssertEqual(on.rows.filter { $0.weightRow?.source != MarkerCatalog.scanSource },
                       off.rows.filter { $0.weightRow?.source != MarkerCatalog.scanSource })
        XCTAssertEqual(on.unlistedCount, off.unlistedCount)
    }

    /// §9.5: neither key is backed up; a Bool cannot cross the whitelist.
    func testNeitherFlagIsInTheBackupWhitelist() {
        let defaults = suites.make("BodyRecordFlagTests")
        defaults.set(true, forKey: BodyRecordSettings.enabledKey)
        defaults.set(true, forKey: BodyRecordSettings.labReportUnitsKey)
        let snapshot = BackupSettings.snapshot(from: defaults)
        XCTAssertNil(snapshot[BodyRecordSettings.enabledKey])
        XCTAssertNil(snapshot[BodyRecordSettings.labReportUnitsKey])
        XCTAssertEqual(snapshot.keys.filter { $0.lowercased().contains("bodyrecord") || $0.lowercased().contains("labreport") }, [])
    }

    #if DEBUG
    /// Ruling A4: one registry element owning the stage's five reserved prefixes, overlapping no other.
    func testTheBodyRecordDemoPrefixesAreReservedAndOverlapNoOther() {
        XCTAssertEqual(DemoScreenPrefixes.bodyRecord, ["bodyrecord-", "scan-", "compare-", "bench-", "labunits-"])
        let registry = DemoScreenRegistry<String>([
            .init(prefixes: DemoScreenPrefixes.scorecard, resolve: { _ in nil }),
            .init(prefixes: DemoScreenPrefixes.packet, resolve: { _ in nil }),
            .init(prefixes: DemoScreenPrefixes.bodyRecord, resolve: { "answered " + $0 }),
        ])
        XCTAssertEqual(registry.conflicts, [])
        for name in ["bodyrecord-g4", "scan-h8", "compare-j1", "bench-k5", "labunits-l2", "bodyrecord-history-on"] {
            XCTAssertEqual(registry.screen(named: name), "answered " + name)
        }
        XCTAssertNil(registry.screen(named: "compare"), "the app's own \"compare\" screen is not this stage's")
        XCTAssertNil(registry.screen(named: "scorecard-b1"))
        XCTAssertNil(registry.screen(named: "packet-b1"))
    }
    #endif
}
