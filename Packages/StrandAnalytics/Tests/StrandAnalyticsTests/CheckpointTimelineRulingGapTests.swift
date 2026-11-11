import XCTest
@testable import StrandAnalytics

// Cases the fault injection of the stage 6 pure logic found no test for (faults T33, T34 and T42 of the
// stage 6 report). Every expected value is read from docs/personal/superapp/specs/stage-6.md §7.3; none
// is taken from what the implementation returns.
//
// T33, §7.3 step 4b: "A targetDate checkpoint whose non-nil phaseStartDay equals that of an earlier
// kept targetDate checkpoint (input order) is dropped and counted duplicate". The condition names the
// two `phaseStartDay` values only; it does not require a phase to start on that day.
// T34, §7.3 step 4b: `phaseIndex` is "the index of the first phase whose canonical startDay equals the
// checkpoint's phaseStartDay", so a phase whose start day is not canonical is never matched.
// T42, §7.3 step 3: "Non-canonical: invalidDay. After today: futureScan. A repeat of a day already
// taken: duplicate." A future day yields no item, so it takes no day; and judged in the listed order a
// future day is `futureScan` before it can be a repeat. Both routes give the same counts.
//
// NOT PINNED (needs a ruling): whether a target-date item carries its phase's `isCut` in `phaseIsCut`
// (fault T36). §7.3 gives `phaseIsCut` to phase-start items only and is silent for checkpoints.

/// The `today` of these tests.
private let gapToday = "2031-03-10"

private func targetDate(_ day: String, phase phaseStartDay: String?) -> TimelineCheckpoint {
    TimelineCheckpoint(day: day, isApproximate: false, category: .targetDate, waypointWeightKg: nil,
                       phaseStartDay: phaseStartDay, isDone: false)
}

private func build(phases: [TimelinePhase] = [], checkpoints: [TimelineCheckpoint] = [],
                   scanDays: [String] = [],
                   scans: TimelineSourceState = .on) -> CheckpointTimelineResult {
    CheckpointTimeline.build(CheckpointTimelineInput(
        phases: phases, checkpoints: checkpoints, scanDays: scanDays, spans: [], projection: nil,
        scans: scans, events: .off, today: gapToday))
}

private func items(_ result: CheckpointTimelineResult, _ kind: TimelineItemKind) -> [TimelineItem] {
    result.items.filter { $0.kind == kind }
}

final class CheckpointTimelineRulingGapTests: XCTestCase {

    // MARK: T33 — one target date per `phaseStartDay`, whether or not a phase starts that day

    func testSecondTargetDateForOnePhaseStartDayIsDroppedWhenNoPhaseStartsThatDay() {
        let result = build(
            phases: [TimelinePhase(startDay: "2031-01-06", isCut: true, targetWeightKg: 80)],
            checkpoints: [targetDate("2031-04-01", phase: "2031-01-07"),
                          targetDate("2031-05-01", phase: "2031-01-07")])
        let kept = items(result, .checkpoint)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.day, "2031-04-01")
        XCTAssertEqual(kept.first?.sourceIndex, 0)
        XCTAssertNil(kept.first?.phaseIndex)
        XCTAssertEqual(result.rejections.duplicate, 1)
    }

    func testSecondTargetDateForOnePhaseStartDayIsDroppedWithNoPhasesAtAll() {
        let result = build(
            checkpoints: [targetDate("2031-04-01", phase: "2031-01-07"),
                          targetDate("2031-05-01", phase: "2031-01-07"),
                          targetDate("2031-06-01", phase: "2031-01-08")])
        let kept = items(result, .checkpoint)
        XCTAssertEqual(kept.map(\.day), ["2031-04-01", "2031-06-01"])
        XCTAssertEqual(kept.map(\.sourceIndex), [0, 2])
        XCTAssertEqual(result.rejections.duplicate, 1)
    }

    // MARK: T34 — `phaseIndex` matches canonical start days only

    func testPhaseIndexIsNilWhenTheOnlyEqualStartDayIsNotCanonical() {
        let result = build(
            phases: [TimelinePhase(startDay: "nonsense", isCut: true, targetWeightKg: 80)],
            checkpoints: [targetDate("2031-04-01", phase: "nonsense")])
        let kept = items(result, .checkpoint)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.category, .targetDate)
        XCTAssertNil(kept.first?.phaseIndex)
        XCTAssertTrue(items(result, .phaseStart).isEmpty)
    }

    func testPhaseIndexCountsPhasesWithANonCanonicalStartDay() {
        // The index is into the input's phases, so a phase that is not shown still holds its place.
        let result = build(
            phases: [TimelinePhase(startDay: "nonsense", isCut: true, targetWeightKg: 80),
                     TimelinePhase(startDay: "2031-01-06", isCut: true, targetWeightKg: 80)],
            checkpoints: [targetDate("2031-04-01", phase: "2031-01-06")])
        XCTAssertEqual(items(result, .checkpoint).first?.phaseIndex, 1)
    }

    // MARK: T42 — a future scan day takes no day

    func testRepeatedFutureScanDayCountsAsFutureEachTime() {
        let result = build(scanDays: ["2031-03-11", "2031-03-11"])
        XCTAssertTrue(items(result, .scan).isEmpty)
        XCTAssertEqual(result.rejections.futureScan, 2)
        XCTAssertEqual(result.rejections.duplicate, 0)
    }

    func testRepeatedFutureScanDayBesideARepeatedKeptDay() {
        let result = build(scanDays: [gapToday, "2031-03-11", "2031-03-11", gapToday])
        let scans = items(result, .scan)
        XCTAssertEqual(scans.map(\.day), [gapToday])
        XCTAssertEqual(scans.first?.sourceIndex, 0)
        XCTAssertEqual(result.rejections.futureScan, 2)
        XCTAssertEqual(result.rejections.duplicate, 1)
    }
}
