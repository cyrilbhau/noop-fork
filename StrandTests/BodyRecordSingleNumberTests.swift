// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/stage-4.md §8 (ruling R41 and stage 1's ruling R44) and §12.4,
// declared in full at the top of BodyRecordTestSupport.swift. This file calls:
//
//     BodyRecordStore.save(_:replacing:), .delete(_:), .scans()
//     BodyScanDraft(day:values:note:)
//     BodyScanEntry(day:), BodyRecordPresenter.sheet(_:unitSystem:decimalSeparator:phase:weighInOutranks:)
//         and BodyScanSheetState.draft (for the pounds case only)
//     CutScorecardPresenter.history(weights:waists:appleHealth:unitSystem:locale:today:bodyRecordEnabled:)
//
// and, from the tree as stage 1's work package 1-11 leaves it (stage-1.md §8.1, §8.7):
//
//     BodyMeasurementProvider.current(_:consumer:), .resolve(_:asOf:consumer:), .series(_:consumer:)
//     CutScorecardInputBuilder.build(today:) passing `asOf: today` to the provider's series
//     CutScorecard.evaluate(_:).weeks / .currentWeightKg
//
// These tests assert only what the resolver returns, through every surface that reads it: the Today
// tile input, the estimates' input, the readiness input, the scorecard's current weight and weekly
// point, the profile mirror and the weigh-in history's mark. They never ask how. Every typed scan is
// saved through `BodyRecordStore.save`; the imported scan of V7d is seeded as the markers CSV import
// writes it. The tests naming V7 to V7f go green only once both stage 1's work package 1-11 and
// stage 4's work package 4-5 are in the tree (§14).
//
// Synthetic values only: the Fixture Person. Lab Book rows on the fixed 2031 dates (ruling R31),
// except the Apple Health case, which is dated relative to the real clock because the repository's
// Apple Health reads are windowed on it.

import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

@MainActor
final class BodyRecordSingleNumberTests: XCTestCase {
    private typealias F = BodyRecordFixture
    private let suites = BodyRecordSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    /// Monday of the fixture's week 1, and of the week before it.
    private let week1 = "2031-01-06"
    private let weekBefore = "2030-12-30"
    /// Monday 2031-01-06, Sunday 2031-01-05, Friday 2031-01-10, Wednesday 2031-01-15, all 07:00 UTC.
    private let monday0700 = 1_925_449_200
    private let sunday0700 = 1_925_362_800
    private let friday0700 = 1_925_794_800
    private let week2Wednesday0700 = 1_926_226_800

    private func harness(today: String = BodyRecordFixture.dayA, scorecard: Bool = true) async throws -> BodyRecordHarness {
        try await BodyRecordHarness.make(suites: suites, scorecard: scorecard, today: today)
    }

    /// Every readout of a current weight, plus the week's point and the profile mirror, for `day`.
    private func everySurface(_ h: BodyRecordHarness, day: String, week: String) async -> [Double?] {
        h.today.value = day
        await h.provider.refresh()
        let readouts = await h.weightReadouts(today: day)
        let point = await h.weekPoint(week, today: day)
        return readouts + [point, h.mirroredWeight]
    }

    private func weighIn(_ h: BodyRecordHarness, _ kg: Double, at epoch: Int) async throws -> LabMarkerRow {
        let saved = try await h.weighIns.save(weight: kg, waist: nil, unitSystem: .metric, takenAt: F.date(epoch))
        return try XCTUnwrap(saved.first)
    }

    private func scanTotal(_ h: BodyRecordHarness, _ id: String) async -> Double? {
        await h.scan(id)?.values["weight"]
    }

    // MARK: - V7a: a scan alone in its week

    /// V7a, fault F11 (the provider refresh dropped after a scan write).
    func testScanTotalMassIsTheResolverValueWhenItsWeekHasNoWeighIn() async throws {
        let h = try await harness()
        let scan = try await h.save(F.draftA)
        // No explicit refresh: the save's own finish must have refreshed the provider (§8.2).
        let readouts = await h.weightReadouts(today: F.dayA)
        XCTAssertEqual(readouts, [100.0, 100.0, 100.0, 100.0], "Today, the estimates, readiness, the scorecard")
        XCTAssertEqual(h.provider.current(.weight, consumer: .display),
                       ResolvedBodyMeasurement(kind: .weight, value: 100.0, source: .labBook, day: F.dayA))
        let point = await h.weekPoint(week1, today: F.dayA)
        XCTAssertEqual(point, 100.0, "the week's point")
        XCTAssertEqual(h.mirroredWeight, 100.0, "the profile mirror")
        XCTAssertEqual(scan.values["weight"], 100.0, "the scan's own total: one stored number")
    }

    // MARK: - V7, V7b: a manual weigh-in in the scan's week outranks it

    /// V7: the weigh-in at 07:00 and the scan at 12:00 on one day. The weigh-in is the value
    /// although the scan's instant is later; the scan keeps showing its own total.
    func testManualWeighInOutranksAScanOnTheSameDay() async throws {
        let h = try await harness()
        let scan = try await h.save(F.draftA)
        let manual = try await weighIn(h, 101.0, at: F.sevenA)

        let surfaces = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(surfaces, [101.0, 101.0, 101.0, 101.0, 101.0, 101.0])
        let total = await scanTotal(h, scan.id)
        XCTAssertEqual(total, 100.0, "the scan still shows 100.0")

        try await h.weighIns.delete(manual)
        let back = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(back, [100.0, 100.0, 100.0, 100.0, 100.0, 100.0], "deleting the weigh-in makes all of them 100.0")
    }

    /// V7b: the weigh-in on the Monday, the scan on the Wednesday.
    func testManualWeighInOutranksALaterScanInTheSameWeek() async throws {
        let h = try await harness()
        try await h.save(F.draftA)
        _ = try await weighIn(h, 101.0, at: monday0700)
        let surfaces = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(surfaces, [101.0, 101.0, 101.0, 101.0, 101.0, 101.0])
    }

    /// V7c: the weigh-in on the Sunday before is another week.
    func testManualWeighInInThePreviousWeekDoesNotOutrank() async throws {
        let h = try await harness()
        try await h.save(F.draftA)
        _ = try await weighIn(h, 101.0, at: sunday0700)
        let surfaces = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(surfaces, [100.0, 100.0, 100.0, 100.0, 100.0, 100.0])
        let previous = await h.weekPoint(weekBefore, today: F.dayA)
        XCTAssertEqual(previous, 101.0, "the week of 2030-12-30 has the point 101.0")
    }

    /// V8.
    func testNewerWeighInInALaterWeekIsTheCurrentValue() async throws {
        let h = try await harness(today: "2031-01-15")
        let scan = try await h.save(F.draftA)
        _ = try await weighIn(h, 99.2, at: week2Wednesday0700)
        let surfaces = await everySurface(h, day: "2031-01-15", week: "2031-01-13")
        XCTAssertEqual(surfaces, [99.2, 99.2, 99.2, 99.2, 99.2, 99.2])
        let total = await scanTotal(h, scan.id)
        XCTAssertEqual(total, 100.0, "scan A's total stays 100.0 inside the scan")
        let week1Point = await h.weekPoint(week1, today: "2031-01-15")
        XCTAssertEqual(week1Point, 100.0, "the scan is still its own week's point")
    }

    /// A scan saved after a newer weigh-in does not become the current value.
    func testOlderScanDoesNotOverrideANewerWeighIn() async throws {
        let h = try await harness(today: "2031-01-15")
        _ = try await weighIn(h, 99.2, at: week2Wednesday0700)
        try await h.save(F.draftA)
        let readouts = await h.weightReadouts(today: "2031-01-15")
        XCTAssertEqual(readouts, [99.2, 99.2, 99.2, 99.2])
        XCTAssertEqual(h.mirroredWeight, 99.2)
    }

    /// V7, through the scorecard input builder's weekly series.
    func testWeeklyPointIsTheWeighInWhenBothExist() async throws {
        let h = try await harness()
        try await h.save(F.draftA)
        let manual = try await weighIn(h, 101.0, at: F.sevenA)
        let input = await h.builder.build(today: F.dayA)
        XCTAssertEqual(input.weights.map(\.value), [101.0], "one reading for the day, the weigh-in's")
        XCTAssertEqual(input.weights.map(\.takenAt), [manual.takenAt])
        let weeks = CutScorecard.evaluate(input).weeks
        XCTAssertEqual(weeks.map(\.weekStart), [week1])
        XCTAssertEqual(weeks.map(\.weightKg), [101.0])
    }

    func testAddingAWeighInMovesEverySurfaceTogether() async throws {
        let h = try await harness()
        try await h.save(F.draftA)
        let before = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(before, [100.0, 100.0, 100.0, 100.0, 100.0, 100.0])
        _ = try await weighIn(h, 101.0, at: monday0700)
        let after = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(after, [101.0, 101.0, 101.0, 101.0, 101.0, 101.0])
    }

    func testDeletingThatWeighInMovesThemBack() async throws {
        let h = try await harness()
        try await h.save(F.draftA)
        let manual = try await weighIn(h, 101.0, at: monday0700)
        let with = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(with, [101.0, 101.0, 101.0, 101.0, 101.0, 101.0])
        try await h.weighIns.delete(manual)
        let without = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(without, [100.0, 100.0, 100.0, 100.0, 100.0, 100.0])
    }

    /// The scan is current (its week has no weigh-in); deleting it moves every surface to the
    /// weigh-in of the week before, the mirror included.
    func testDeletingTheScanMovesEverySurfaceBackTogether() async throws {
        let h = try await harness()
        _ = try await weighIn(h, 101.0, at: sunday0700)
        let scan = try await h.save(F.draftA)
        let with = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(with, [100.0, 100.0, 100.0, 100.0, 100.0, 100.0])

        try await h.records.delete(scan)
        let readouts = await h.weightReadouts(today: F.dayA)
        XCTAssertEqual(readouts, [101.0, 101.0, 101.0, 101.0], "no explicit refresh: the delete's finish refreshed")
        XCTAssertEqual(h.mirroredWeight, 101.0)
        let point = await h.weekPoint(week1, today: F.dayA)
        XCTAssertNil(point, "the scan's week has no reading left: not measured, never zero")
    }

    /// V7d: a scan imported by CSV is not outranked; it competes by instant and noon is later than 07:00.
    func testCsvImportedScanIsNotOutrankedAndCompetesByInstant() async throws {
        let h = try await harness()
        try await h.seed(F.scanRows(F.scanA, deviceId: F.active, day: F.dayA, takenAt: F.noonA,
                                    source: LabMarkerCsvImport.sourceId))
        _ = try await weighIn(h, 101.0, at: F.sevenA)
        let surfaces = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(surfaces, [100.0, 100.0, 100.0, 100.0, 100.0, 100.0])
    }

    /// V7e: a manual row in a unit the resolver does not admit does not outrank.
    func testManualRowInAnUnknownUnitDoesNotOutrank() async throws {
        let h = try await harness()
        try await h.save(F.draftA)
        try await h.seed([LabMarkerRow(id: "weight-\(F.sevenA)-0A1B2C3D", deviceId: F.active, markerKey: "weight",
                                       category: "bodyMeasurement", day: F.dayA, takenAt: F.sevenA, value: 16.0,
                                       valueText: nil, unit: "stone", source: "manual", note: nil, referenceText: nil)])
        let surfaces = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(surfaces, [100.0, 100.0, 100.0, 100.0, 100.0, 100.0])
    }

    /// V7f: rows after the as-of day never suppress.
    func testAWeighInAfterTheAsOfDayDoesNotSuppressTheScan() async throws {
        let h = try await harness()
        try await h.save(F.draftA)
        _ = try await weighIn(h, 101.0, at: friday0700)
        await h.provider.refresh()

        XCTAssertEqual(h.provider.resolve(.weight, asOf: F.dayA, consumer: .display)?.value, 100.0)
        XCTAssertEqual(h.provider.resolve(.weight, asOf: "2031-01-09", consumer: .display)?.value, 100.0)
        XCTAssertEqual(h.provider.resolve(.weight, asOf: "2031-01-10", consumer: .display)?.value, 101.0)

        let onScanDay = await everySurface(h, day: F.dayA, week: week1)
        XCTAssertEqual(onScanDay, [100.0, 100.0, 100.0, 100.0, 100.0, 100.0], "looking back gives the scan")
        let onFriday = await everySurface(h, day: "2031-01-10", week: week1)
        XCTAssertEqual(onFriday, [101.0, 101.0, 101.0, 101.0, 101.0, 101.0],
                       "the week's point evaluated with today 2031-01-10 is 101.0")
    }

    /// An Apple Health value is not a manual weigh-in (stage 1 S13). Dated on the real clock.
    func testAppleHealthValueInTheScanWeekDoesNotOutrankIt() async throws {
        let seconds = Int(Date().timeIntervalSince1970) - 2 * 86_400
        let start = seconds - seconds % 86_400                       // 00:00 UTC two days back
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = F.utc
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date(timeIntervalSince1970: Double(start)))
        let monday = try XCTUnwrap(CutScorecard.weekStart(containing: today))

        let h = try await BodyRecordHarness.make(suites: suites, today: today,
                                                 now: Date(timeIntervalSince1970: Double(start + 20 * 3_600)))
        try await h.store.upsertAppleDaily([AppleDaily(day: monday, steps: nil, activeKcal: nil, basalKcal: nil,
                                                       vo2max: nil, avgHr: nil, maxHr: nil, walkingHr: nil,
                                                       weightKg: 97.0)], deviceId: "apple-health")
        try await h.save(BodyScanDraft(day: today, values: F.scanC, note: nil))
        await h.provider.refresh()

        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.value, 94.0)
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.source, .labBook)
        let readouts = await h.weightReadouts(today: today)
        XCTAssertEqual(readouts, [94.0, 94.0, 94.0, 94.0])
        let series = h.provider.series(.weight, consumer: .display)
        XCTAssertTrue(series.contains { $0.day == today && $0.value == 94.0 }, "the scan stays in the series")
        if monday != today {
            XCTAssertTrue(series.contains { $0.day == monday && $0.source == .appleHealth },
                          "the Apple Health value is not removed either")
        }
    }

    // MARK: - The history's mark

    /// For V7, V7a, V7b and V7c the row captioned "Represents its week" is the row whose value the
    /// resolver's series holds for that week.
    func testHistoryRepresentativeAgreesWithTheResolver() async throws {
        let variants: [(name: String, manual: Int?)] = [("V7", F.sevenA), ("V7a", nil), ("V7b", monday0700),
                                                        ("V7c", sunday0700)]
        for variant in variants {
            let h = try await harness()
            let scan = try await h.save(F.draftA)
            if let at = variant.manual { _ = try await weighIn(h, 101.0, at: at) }
            await h.provider.refresh()

            let weights = await h.weighIns.readings(.weight)
            let history = CutScorecardPresenter.history(weights: weights, waists: [], appleHealth: [],
                                                        unitSystem: .metric, locale: F.british,
                                                        today: F.dayA, bodyRecordEnabled: true)
            let series = h.provider.series(.weight, consumer: .display)
            for week in Set(series.compactMap { CutScorecard.weekStart(containing: $0.day) }) {
                let resolverRow = series.last { CutScorecard.weekStart(containing: $0.day) == week }?.rowId
                let marked = history.rows.filter { $0.representsWeek && CutScorecard.weekStart(containing: $0.day) == week }
                XCTAssertEqual(marked.count, 1, "\(variant.name): one mark in the week of \(week)")
                XCTAssertEqual(marked.first?.weightRow?.id, resolverRow, "\(variant.name), week of \(week)")
            }
            let scanRow = history.rows.first { $0.weightRow?.source == MarkerCatalog.scanSource }
            let outranked = variant.name == "V7" || variant.name == "V7b"
            XCTAssertEqual(scanRow?.representsWeek, !outranked, variant.name)
            XCTAssertEqual(scanRow?.caption.hasPrefix(outranked ? "Not the weekly point" : "Represents its week"),
                           true, "\(variant.name): \(scanRow?.caption ?? "no scan row")")
            XCTAssertEqual(scanRow?.scanId, scan.id, variant.name)
        }
    }

    // MARK: - The combined seed and the stored number

    /// §13, §12.6: stage 1's weigh-ins plus scans A, B and C give stage 1's weekly points exactly
    /// (stage-1.md §13.3): every scan's week holds a manual weigh-in.
    func testCombinedSeedLeavesTheStageOneWeeklySeriesUnchanged() async throws {
        let h = try await harness(today: "2031-06-04")
        for entry in F.stageOneWeeks {
            guard let weight = entry.weight else { continue }
            try await h.weighIns.save(weight: weight, waist: entry.waist, unitSystem: .metric,
                                      takenAt: F.date(F.stageOneInstant(week: entry.week)))
        }
        try await h.weighIns.save(weight: 98.9, waist: nil, unitSystem: .metric, takenAt: F.date(F.stageOneMondayExtra))
        let stageOne = CutScorecard.evaluate(await h.builder.build(today: "2031-06-04")).weeks
        XCTAssertEqual(stageOne.map(\.weightKg), F.stageOneWeeks.map(\.weight), "precondition: stage 1's §13.3")

        try await h.save(F.draftA)
        try await h.save(F.draftB)
        try await h.save(F.draftC)
        let combined = CutScorecard.evaluate(await h.builder.build(today: "2031-06-04")).weeks
        XCTAssertEqual(combined, stageOne, "the scans change no week of the series")
        XCTAssertEqual(combined.map(\.weightKg), F.stageOneWeeks.map(\.weight))
        let readouts = await h.weightReadouts(today: "2031-06-04")
        XCTAssertEqual(readouts, [93.5, 93.5, 93.5, 93.5])
    }

    /// Fault F10.
    func testTotalMassIsStoredUnderNoOtherKey() async throws {
        let h = try await harness()
        try await h.save(F.draftA)
        let stored = try await h.everyRow()
        XCTAssertEqual(stored.filter { $0.value == 100.0 }.map(\.markerKey), ["weight"],
                       "the total is stored once, as a weight reading")
        XCTAssertEqual(Set(stored.map(\.markerKey)).subtracting(F.fieldKeys), [], "no key outside §7.7")
    }

    /// V6, fault F12: pounds are divided by the shared constant, exactly as the resolver converts a
    /// Lab Book row in pounds.
    func testPoundsEnteredInTheScanEqualTheResolverConversion() async throws {
        var entry = BodyScanEntry(day: F.dayA)
        entry.texts = ["weight": "220.5", "scan_fat_mass": "30.0"]
        entry.units = ["weight": "lb", "scan_fat_mass": "kg"]
        let state = BodyRecordPresenter.sheet(entry, unitSystem: .metric, decimalSeparator: ".", phase: .editing,
                                              weighInOutranks: false)
        let draft = try XCTUnwrap(state.draft)
        let kilograms = try XCTUnwrap(draft.values["weight"])
        XCTAssertEqual(kilograms, 220.5 / UnitFormatter.poundsPerKilogram, "divided, by the shared constant")
        let poundsRow = LabMarkerRow(id: "weight-1-00000000", deviceId: F.active, markerKey: "weight",
                                     category: "bodyMeasurement", day: F.dayA, takenAt: 1, value: 220.5,
                                     valueText: nil, unit: "lb", source: "manual", note: nil, referenceText: nil)
        XCTAssertEqual(kilograms, BodyMeasurementResolver.normalizedValue(of: poundsRow, as: .weight),
                       "the kilograms the resolver would have computed")

        let h = try await harness()
        let scan = try await h.save(draft)
        XCTAssertEqual(scan.values["weight"], kilograms, "stored unrounded")
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.value, kilograms)
    }

    /// §8.1: with the scorecard flag off the legacy policies ignore Lab Book.
    func testScanChangesNothingOnTodayWhileTheScorecardFlagIsOff() async throws {
        let h = try await harness(scorecard: false)
        h.defaults.set(80.0, forKey: "profile.weightKg")
        await h.provider.refresh()
        let before = [h.provider.current(.weight, consumer: .display)?.value,
                      h.provider.current(.weight, consumer: .estimate)?.value]
        XCTAssertEqual(before, [80.0, 80.0], "precondition: the profile value")

        try await h.save(F.draftA)
        await h.provider.refresh()
        let after = [h.provider.current(.weight, consumer: .display)?.value,
                     h.provider.current(.weight, consumer: .estimate)?.value]
        XCTAssertEqual(after, before)
        XCTAssertEqual(h.defaults.double(forKey: "profile.weightKg"), 80.0, "no mirror write with the flag off")
    }

    /// §7.2: one constant per conversion across the app.
    func testUnitConstantsEqualTheAppFormatterConstants() {
        XCTAssertEqual(MarkerUnitTable.poundsPerKilogram, UnitFormatter.poundsPerKilogram)
        XCTAssertEqual(MarkerUnitTable.centimetersPerInch, UnitFormatter.centimetersPerInch)
        XCTAssertEqual(MarkerUnitTable.toStored(220.5, key: "weight", from: "lb", tier: .extended),
                       220.5 / UnitFormatter.poundsPerKilogram)
        XCTAssertEqual(MarkerUnitTable.toStored(40, key: "waist", from: "in", tier: .extended),
                       40 * UnitFormatter.centimetersPerInch)
    }
}
