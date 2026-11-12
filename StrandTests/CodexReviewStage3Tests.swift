// Stage 3 (protein and intake): the two findings of the independent review C8, each pinned by a
// test that fails on the defect it names. Synthetic values only.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class CodexReviewStage3Tests: XCTestCase {
    private let suites = IntakeSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    // MARK: - C8 P2: two first quick-adds on one day

    /// Two adds launched together on a day with no entry list each start from an absent list. Both
    /// report success, so both entries must be kept and the total must be their sum. Several days
    /// are tried, because which add's write survives an unserialised race varies.
    func testOverlappingFirstAddsOnOneDayKeepBothEntries() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        let store = h.quickAdd()
        for offset in -5...0 {
            async let first = store.add(proteinGrams: 30, energyKcal: nil, label: "Fixture A",
                                        at: h.clock.at(offset, hour: 8))
            async let second = store.add(proteinGrams: 40, energyKcal: nil, label: "Fixture B",
                                         at: h.clock.at(offset, hour: 8))
            let added = try await [first, second]
            let day = h.clock.day(offset)
            XCTAssertEqual(Set(store.entries(day: day).map(\.id)), Set(added.map(\.id)),
                           "both adds reported success on \(day), so both entries are kept")
            let total = try await h.value(IntakeFixture.quickAddId, day, "protein_g")
            XCTAssertEqual(total, 70, "the banked total of \(day) is the sum of both entries")
        }
    }
}
