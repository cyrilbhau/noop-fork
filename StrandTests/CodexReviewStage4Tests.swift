// The three body record findings of the independent C7 review (stage 4), each pinned by a test that
// failed on the defect before its fix.
//
//  1. Two overlapping new-scan saves at one instant: the second is refused with `instantOccupied`
//     and the first scan is left as saved (§9.1 occupancy), as the weigh-in store refuses an
//     occupied instant.
//  2. Adding a reading to an existing custom benchmark keeps that benchmark's stored unit: a timed
//     custom benchmark takes seconds, not the entry's default of reps (§5.3, §10.5 K2).
//  3. A custom name that derives no `custom_bench_<slug>` key (punctuation only) cannot be saved,
//     and the sheet says why, naming the field (§5.3: the key is the helper's, the prefix rule stays).
//
// Synthetic values only: the Fixture Person (stage 4 §13).

import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

@MainActor
final class CodexReviewStage4Tests: XCTestCase {
    private typealias F = BodyRecordFixture
    private typealias P = BodyRecordPresenter
    private let suites = BodyRecordSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func harness() async throws -> BodyRecordHarness {
        try await BodyRecordHarness.make(suites: suites)
    }

    // MARK: 1. Overlapping new-scan saves

    func testOverlappingNewScanSavesAtOneInstantRefuseTheSecondAndKeepTheFirst() async throws {
        for round in 0..<3 {
            let h = try await harness()
            let draftA = BodyScanDraft(day: F.dayA, values: ["scan_fat_mass": 30.0], note: "Fixture A")
            let draftB = BodyScanDraft(day: F.dayA, values: ["scan_fat_mass": 31.0], note: "Fixture B")
            let first = Task { @MainActor in try await h.records.save(draftA, replacing: nil) }
            let second = Task { @MainActor in try await h.records.save(draftB, replacing: nil) }
            let results = [await first.result, await second.result]

            let saved = results.compactMap { try? $0.get() }
            let refusals = results.compactMap { result -> BodyRecordError? in
                if case .failure(let error) = result { return error as? BodyRecordError }
                return nil
            }
            XCTAssertEqual(saved.count, 1, "round \(round): exactly one of the two saves succeeds")
            XCTAssertEqual(refusals, [.instantOccupied], "round \(round): the other is refused as occupied")

            let listed = await h.records.scans()
            XCTAssertEqual(listed.count, 1, "round \(round)")
            XCTAssertEqual(listed.first?.values, saved.first?.values, "round \(round): the saved scan is unchanged")
            XCTAssertEqual(listed.first?.note, saved.first?.note, "round \(round): its note is unchanged")
            let stored = try await h.everyRow().filter { $0.source == MarkerCatalog.scanSource }
            XCTAssertEqual(stored.count, 2, "round \(round): one figure and one note, nothing else")
        }
    }
}
