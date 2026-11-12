// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/stage-4.md §4.5, §12.4 ("OneNumberPerVariableTests.swift,
// existing, extended") and §12.9 (privacy). The specification places these two tests in
// StrandTests/OneNumberPerVariableTests.swift; this stage's test author writes new files only, so
// they live here, in their own class, with the names the specification gives them.
//
// The Coach roll-up (`AICoachEngine.onDeviceSignalsBlock()`, Strand/AI/AICoach.swift) gains one
// line: a Lab Book key for which `MarkerCatalog.isScanOnlyMarker(_:)` or `MarkerCatalog.isBenchmark(_:)`
// is true is skipped. Nothing else changes. `AICoachEngine(repo:)`, `.bodyMeasurements` and
// `onDeviceSignalsBlock()` are used as they exist; `BodyRecordStore` as declared at the top of
// BodyRecordTestSupport.swift.
//
// `weight` and `body_fat` are ordinary readings (ruling R41): a scan's total mass and body-fat
// percentage are rows under those keys and reach the roll-up as any weight or body-fat reading
// does. The privacy assertion is therefore on every scan-only figure, every scan display name and
// every benchmark name.
//
// Synthetic values only: the Fixture Person.

import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

@MainActor
final class BodyRecordCoachRollUpTests: XCTestCase {
    private typealias F = BodyRecordFixture
    private let suites = BodyRecordSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private static let labBookHeader =
        "LAB BOOK (the user's own logged health numbers — not medical advice; do not interpret as clinical findings):"

    /// The whole fixture: scans A, B and C, the benchmarks of §13.5 and one blood result.
    private func wholeFixture(scorecard: Bool) async throws -> BodyRecordHarness {
        let h = try await BodyRecordHarness.make(suites: suites, scorecard: scorecard)
        try await h.save(F.draftA)
        try await h.save(F.draftB)
        try await h.save(F.draftC)
        for (key, value, unit, epoch, note) in [
            ("bench_dead_hang_s", 20.0, "s", F.jan06Noon, nil as String?), ("bench_dead_hang_s", 30.0, "s", F.feb17Noon, nil),
            ("bench_dead_hang_s", 45.0, "s", F.mar31Noon, "Fixture bar"), ("bench_pushup_reps", 10.0, "reps", F.jan06Noon, nil),
            ("bench_pushup_reps", 14.0, "reps", F.feb17Noon, nil), (F.customCarryKey, 60.0, "s", F.jan06Noon, nil),
        ] {
            try await h.records.saveBenchmark(key: key, value: value, unit: unit, takenAt: F.date(epoch), note: note)
        }
        try await h.store.upsertOwnerLabMarkers([
            LabMarkerRow(id: "ldl-1925640000-0A1B2C3D", deviceId: F.active, markerKey: "ldl", category: "bloodPanel",
                         day: F.dayA, takenAt: F.noonA, value: 100 * (1.0 / 38.67), valueText: "100 mg/dL",
                         unit: "mmol/L", source: "manual", note: nil, referenceText: nil),
        ])
        await h.provider.refresh()
        return h
    }

    /// Fault F29, §12.9.
    func testCoachRollUpLeavesOutScanAndBenchmarkMarkers() async throws {
        for scorecard in [false, true] {
            let h = try await wholeFixture(scorecard: scorecard)
            let engine = AICoachEngine(repo: h.repo)
            if scorecard { engine.bodyMeasurements = h.provider }
            let text = await engine.onDeviceSignalsBlock()

            XCTAssertTrue(text.contains("2.59 mmol/L"), "a blood result is still sent (scorecard \(scorecard)):\n\(text)")
            var banned = MarkerCatalog.bodyRecord.map(\.displayName)
            banned += ["(scan)", "laboratory estimate", "Laboratory estimate", "Scan note", F.noteA, "Fixture bar",
                       "custom_bench", "fixture_carry", "Fixture Carry", "Fixture carry", "bench_", "scan_"]
            // Scan-only figures as the roll-up would have printed them, and the benchmark readings.
            banned += ["1000 g", "800 g", "80 cm²", "1.15 ratio", "1.20 ratio", "32.00 kg", "31.50 kg", "19.50 kg",
                       "5.30 kg", "1.200 g/cm²", "1900 kcal/day", "1850 kcal/day", "45 s", "14 reps", "60 s"]
            for word in banned {
                XCTAssertFalse(text.contains(word), "\"\(word)\" reached the Coach (scorecard \(scorecard)):\n\(text)")
            }
        }
    }

    /// No body-record row: the block is byte for byte the base rule (one marker per category, so the
    /// base code's dictionary order cannot change the text).
    func testCoachContextIsUnchangedForAStoreWithoutBodyRecordRows() async throws {
        let h = try await BodyRecordHarness.make(suites: suites, scorecard: false)
        let rows = [
            LabMarkerRow(id: "ldl-1925640000-0A1B2C3D", deviceId: F.active, markerKey: "ldl", category: "bloodPanel",
                         day: F.dayA, takenAt: F.noonA, value: 2.6, valueText: nil, unit: "mmol/L", source: "manual",
                         note: nil, referenceText: nil),
            LabMarkerRow(id: "bp_systolic-1925640000-0A1B2C3D", deviceId: F.active, markerKey: "bp_systolic",
                         category: "bloodPressure", day: F.dayA, takenAt: F.noonA, value: 120, valueText: nil,
                         unit: "mmHg", source: "manual", note: nil, referenceText: nil),
            LabMarkerRow(id: "weight-1925622000-0A1B2C3D", deviceId: F.active, markerKey: "weight",
                         category: "bodyMeasurement", day: F.dayA, takenAt: F.sevenA, value: 100.0, valueText: nil,
                         unit: "kg", source: "manual", note: nil, referenceText: nil),
            LabMarkerRow(id: "zz-custom-marker-1925640000-0A1B2C3D", deviceId: F.active, markerKey: "zz-custom-marker",
                         category: "other", day: F.dayA, takenAt: F.noonA, value: 3.1, valueText: nil, unit: "mmol/L",
                         source: "manual", note: nil, referenceText: nil),
        ]
        try await h.store.upsertLabMarkers(rows)

        var summaries: [String] = []
        for category in LabMarkerCategory.allCases {
            guard let latest = rows.filter({ $0.category == category.rawValue }).max(by: { $0.takenAt < $1.takenAt })
            else { continue }
            let name = MarkerCatalog.definition(for: latest.markerKey)?.displayName ?? latest.markerKey
            let value = latest.value.map { "\(LabBookFormat.value($0, key: latest.markerKey)) \(latest.unit)" }
                ?? latest.valueText ?? "—"
            summaries.append("\(name) \(value)")
        }
        let expected = ["", Self.labBookHeader, "  " + summaries.prefix(8).joined(separator: ", ")].joined(separator: "\n")
        let text = await AICoachEngine(repo: h.repo).onDeviceSignalsBlock()
        XCTAssertEqual(text, expected)
    }
}
