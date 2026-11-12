// Gap tests for `IntakeAggregation`, written after the implementation's fault-injection run
// (docs/personal/superapp/specs/stage-3.md §6.3, §6.4, §7.1 to §7.3). Each test names the uncaught
// fault it closes. Expected values are worked from the specification and the orchestrator's rulings,
// not from what the implementation returns.
//
// Faults closed here: A2, A31, P12, P13.
// Left for a ruling, with only what both readings share pinned: P14, P16.
//
// Everything is the one Fixture Person's invented data (`IntakeFixture`).

import XCTest
@testable import StrandAnalytics

private typealias X = IntakeFixture

/// The ruled and uncaught cases of `IntakeAggregation` (stage 3 §7.1 to §7.3).
final class IntakeAggregationRulingGapTests: XCTestCase {

    // MARK: - Helpers

    private let readAt = X.epoch("2030-12-10T09:00:00Z")
    private let earlierRead = X.epoch("2030-12-10T06:00:00Z")

    private func aggregate(_ samples: [IntakeSample], log: [IntakeZoneSegment] = X.logU) -> IntakeAggregationResult {
        IntakeAggregation.aggregate(samples: samples, zoneLog: log, admittedSourceIds: nil,
                                    firstDay: X.firstDay, lastDay: X.lastDay)
    }

    private func stored(_ day: String, _ protein: Double?, _ energy: Double?, readAt: Int?) -> IntakeStoredDay {
        IntakeStoredDay(day: day, proteinGrams: protein, energyKcal: energy, readAtEpochSeconds: readAt)
    }

    private func plan(_ result: IntakeAggregationResult, _ stored: [IntakeStoredDay]) -> IntakeWritePlan {
        IntakeAggregation.plan(result: result, stored: stored, readAtEpochSeconds: readAt)
    }

    private func upserts(_ plan: IntakeWritePlan) -> [String] {
        plan.upserts.map { "\($0.day) \($0.key) \($0.value)" }
    }

    private func deletions(_ plan: IntakeWritePlan) -> [String] {
        plan.deletions.map { "\($0.day) \($0.key)" }
    }

    /// s1 and s2 only: 2030-12-09 holds 30 g and 450 kcal, 2030-12-10 is an empty day.
    private var oneDayResult: IntakeAggregationResult { aggregate([X.s1, X.s2]) }

    /// What the store holds for 2030-12-09 when it already equals `oneDayResult`.
    private var firstDayAsStored: IntakeStoredDay { stored("2030-12-09", 30, 450, readAt: earlierRead) }

    // MARK: - A2: two segments with the same start

    /// Fault A2. The specification is silent on two segments sharing a start; the orchestrator ruled
    /// that the later segment in the log wins. 18:00 UTC on 2030-12-09 is 2030-12-09 in UTC and
    /// 07:00 on 2030-12-10 in Auckland (thirteen hours ahead), so the two orders give different days.
    func testOfTwoSegmentsWithTheSameStartTheLaterInTheLogWins() {
        let instant = X.epoch("2030-12-09T18:00:00Z")
        let date = Date(timeIntervalSince1970: TimeInterval(instant))
        let utcThenAuckland = [X.segment(5, X.utc), X.segment(5, X.auckland)]
        let aucklandThenUTC = [X.segment(5, X.auckland), X.segment(5, X.utc)]

        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: instant, zoneLog: utcThenAuckland).secondsFromGMT(for: date),
                       X.aucklandOffsetSeconds, "Auckland is later in the log")
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: instant, zoneLog: aucklandThenUTC).secondsFromGMT(for: date),
                       0, "UTC is later in the log")
        XCTAssertEqual(IntakeAggregation.dayKey(epochSeconds: instant, zoneLog: utcThenAuckland), "2030-12-10")
        XCTAssertEqual(IntakeAggregation.dayKey(epochSeconds: instant, zoneLog: aucklandThenUTC), "2030-12-09")

        // The report's own input: an instant just after the shared start.
        let early = Date(timeIntervalSince1970: 10)
        XCTAssertNotEqual(IntakeAggregation.zone(atEpochSeconds: 10, zoneLog: utcThenAuckland).secondsFromGMT(for: early),
                          0, "at 10 s the later segment, Auckland, is in force")
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: 10, zoneLog: aucklandThenUTC).secondsFromGMT(for: early), 0)

        // The tie is also broken the same way when an earlier, distinct segment precedes the pair.
        let withLead = [X.segment(0, X.losAngeles), X.segment(5, X.utc), X.segment(5, X.auckland)]
        XCTAssertEqual(IntakeAggregation.dayKey(epochSeconds: instant, zoneLog: withLead), "2030-12-10")
    }

    // MARK: - A31: instants at the ends of Int

    /// Fault A31. §6.4: `aggregate` never traps. §7.1: every instant maps to exactly one day key. An
    /// instant at either end of `Int` is not on 2030-12-09 or 2030-12-10 in any zone, so it is
    /// `outsideWindow` (§6.3: "day key before firstDay or after lastDay") and the fixture's totals of
    /// §13.3 are untouched. Without a guard the day lookup traps, which fails this test by crashing.
    func testInstantsAtTheEndsOfIntAreOutsideTheWindowAndNeverTrap() {
        let extremes = [Int.max, Int.max - 1, Int.min, Int.min + 1]
        for log in [[], X.logU, X.logE, X.logW] {
            for instant in extremes {
                let key = IntakeAggregation.dayKey(epochSeconds: instant, zoneLog: log)
                XCTAssertEqual(key, IntakeAggregation.dayKey(epochSeconds: instant, zoneLog: log),
                               "one instant, one day key")
                XCTAssertNotEqual(key, X.firstDay, "instant \(instant)")
                XCTAssertNotEqual(key, X.lastDay, "instant \(instant)")
                _ = IntakeAggregation.zone(atEpochSeconds: instant, zoneLog: log)
            }
        }

        let far = extremes.enumerated().map { index, instant in
            IntakeSample(id: "far\(index)", nutrient: index % 2 == 0 ? .protein : .energy,
                         startEpochSeconds: instant, amount: 10, sourceId: X.foodAppId)
        }
        let result = aggregate(far + X.foodSamples)
        XCTAssertEqual(result.rejected.outsideWindow, 4)
        XCTAssertEqual(result.rejected.nonFinite, 0)
        XCTAssertEqual(result.rejected.negative, 0)
        XCTAssertEqual(result.rejected.duplicateId, 0)
        XCTAssertEqual(result.rejected.excludedSource, 0)
        XCTAssertEqual(result.totals.map(\.day), ["2030-12-09", "2030-12-10"])
        XCTAssertEqual(result.totals.map(\.proteinGrams), [95, 20])
        XCTAssertEqual(result.totals.map(\.energyKcal), [1450, 250])
        XCTAssertEqual(result.emptyDays, [])

        // Only far samples: the window is empty, and the plan writes nothing (§7.3 step 1).
        let onlyFar = aggregate(far)
        XCTAssertEqual(onlyFar.totals.count, 0)
        XCTAssertEqual(onlyFar.emptyDays, ["2030-12-09", "2030-12-10"])
        XCTAssertEqual(onlyFar.rejected.outsideWindow, 4)
    }

    // MARK: - P12: a stored entry that holds nothing

    /// Fault P12. §7.3 step 3 deletes for "each empty day that has a stored row". §6.2 defines
    /// `IntakeStoredDay` as what the store holds for the day, and §9.1 stores one row per key; an entry
    /// whose three fields are all nil therefore holds no row, and nothing is deleted
    /// (`testAnEmptyDayWithNothingStoredIsLeftAlone`, §12.1, for an entry that is present but empty).
    func testAnEmptyDayWhoseStoredEntryHoldsNothingGetsNoDeletions() {
        let nothingHeld = stored("2030-12-10", nil, nil, readAt: nil)
        let written = plan(oneDayResult, [firstDayAsStored, nothingHeld])

        XCTAssertEqual(deletions(written), [])
        XCTAssertEqual(written.changedDays, [])
        XCTAssertEqual(written.reason, .unchanged)
        XCTAssertEqual(written, plan(oneDayResult, [firstDayAsStored]),
                       "an entry holding nothing plans exactly as no entry")
    }

    // MARK: - P13: a stored row that holds only a read time

    /// Fault P13. §7.3 step 3: an empty day with a stored row has its `protein_g`, `calories_in` and
    /// `intake_read_at` deleted. Step 5: `changedDays` lists days where a protein or energy value
    /// changed. A row holding only a read time loses no protein or energy value, so the day is not a
    /// changed day; with 2030-12-09 already equal to what is stored, nothing changed at all.
    func testAnEmptyDayHoldingOnlyAReadTimeIsDeletedButIsNotAChangedDay() {
        let onlyReadTime = stored("2030-12-10", nil, nil, readAt: earlierRead)
        let written = plan(oneDayResult, [firstDayAsStored, onlyReadTime])

        XCTAssertEqual(deletions(written), [
            "2030-12-10 calories_in",
            "2030-12-10 intake_read_at",
            "2030-12-10 protein_g",
        ])
        XCTAssertEqual(written.changedDays, [], "no protein or energy value moved")
        XCTAssertEqual(written.reason, .unchanged)
        XCTAssertEqual(upserts(written), ["2030-12-09 intake_read_at \(Double(readAt))"],
                       "step 4: the read time still advances for the total day")

        // Contrast: the same empty day holding a value is a changed day.
        let heldValue = stored("2030-12-10", 20, nil, readAt: earlierRead)
        let changed = plan(oneDayResult, [firstDayAsStored, heldValue])
        XCTAssertEqual(changed.changedDays, ["2030-12-10"])
        XCTAssertEqual(changed.reason, .changed)
    }

    // MARK: - P14 (needs a ruling): a day named twice in `stored`

    /// P14 is NOT decided by the specification: when `stored` names one day twice with different
    /// values, either the first or the last entry could be the one compared. This test pins only what
    /// both readings share: two entries that agree plan exactly as one.
    func testADayStoredTwiceWithTheSameValuesPlansAsStoredOnce() {
        let result = aggregate(X.foodSamples)
        let first = stored("2030-12-09", 95, 1450, readAt: earlierRead)
        let second = stored("2030-12-10", 20, 250, readAt: earlierRead)
        let once = plan(result, [first, second])
        let twice = plan(result, [first, first, second, second])

        XCTAssertEqual(twice, once)
        XCTAssertEqual(once.reason, .unchanged)
        XCTAssertEqual(once.deletions.count, 0)
    }

    // MARK: - P16 (needs a ruling): a total that is not finite

    /// P16 is NOT decided by the specification: `aggregate` can never produce a non-finite total
    /// (§6.4), and §7.3 does not say what `plan` does with one built by hand. This test pins only what
    /// both readings share: `plan` returns, and the day's finite energy and its read time are planned.
    func testAHandBuiltNonFiniteTotalDoesNotStopTheRestOfTheDayBeingPlanned() {
        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            let total = IntakeDayTotal(day: "2030-12-09", proteinGrams: bad, energyKcal: 450,
                                       sampleCount: 2, sourceIds: [X.foodAppId])
            let result = IntakeAggregationResult(
                totals: [total], emptyDays: ["2030-12-10"],
                rejected: IntakeRejections(nonFinite: 0, negative: 0, duplicateId: 0, outsideWindow: 0, excludedSource: 0))
            let lines = upserts(plan(result, []))
            XCTAssertTrue(lines.contains("2030-12-09 calories_in 450.0"), "protein \(bad): \(lines)")
            XCTAssertTrue(lines.contains("2030-12-09 intake_read_at \(Double(readAt))"), "protein \(bad): \(lines)")
        }
    }
}
