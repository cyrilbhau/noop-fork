import XCTest
@testable import StrandAnalytics

// API ASSUMED BY THESE TESTS
//
// Stage 6 specification, docs/personal/superapp/specs/stage-6.md §6.3. Every type is public, Equatable
// and Sendable, with a public memberwise init taking the stored properties in declaration order.
//
//   enum TimelineItemKind: String, CaseIterable {
//     case phaseStart, scan, checkpoint, dietBreak, deload, today, projection }
//   enum TimelineCheckpointCategory: String, CaseIterable {
//     case scan, bloodPanel, benchmark, weightWaypoint, targetDate, appointment, other }
//   enum TimelineSpanKind: String, CaseIterable { case dietBreak, deload }
//   enum TimelineSourceState: String { case notBuilt, off, on }
//   enum TimelinePosition: String { case past, current, upcoming }
//   enum TimelineWaypointIssue: String { case nonFinite, atOrBeyondTarget }
//
//   struct TimelinePhase
//     init(startDay: String, isCut: Bool, targetWeightKg: Double?)
//   struct TimelineCheckpoint
//     init(day: String, isApproximate: Bool, category: TimelineCheckpointCategory,
//          waypointWeightKg: Double?, phaseStartDay: String?, isDone: Bool)
//   struct TimelineSpan
//     init(kind: TimelineSpanKind, startDay: String, endDay: String?)
//   struct TimelineProjection
//     init(status: CutScorecardProjectionStatus, targetDay: String?)
//   struct CheckpointTimelineInput
//     init(phases: [TimelinePhase], checkpoints: [TimelineCheckpoint], scanDays: [String],
//          spans: [TimelineSpan], projection: TimelineProjection?, scans: TimelineSourceState,
//          events: TimelineSourceState, today: String)
//   struct TimelineItem
//     let kind: TimelineItemKind; let day: String; let endDay: String?; let isOpenEnded: Bool
//     let position: TimelinePosition; let sourceIndex: Int?; let isApproximate: Bool
//     let isDone: Bool; let isEstimate: Bool; let category: TimelineCheckpointCategory?
//     let targetWeightKg: Double?; let waypointWeightKg: Double?; let phaseIndex: Int?
//     let phaseIsCut: Bool?
//   struct TimelineRejections
//     init(invalidDay: Int, endBeforeStart: Int, futureScan: Int, duplicate: Int, nonFinite: Int,
//          waypointBeyondTarget: Int)
//   struct CheckpointTimelineResult
//     let items: [TimelineItem]; let todayIndex: Int?; let scans: TimelineSourceState
//     let events: TimelineSourceState; let rejections: TimelineRejections; let invalidToday: Bool
//   enum CheckpointTimeline
//     static func build(_ input: CheckpointTimelineInput) -> CheckpointTimelineResult
//     static func kindOrder(_ kind: TimelineItemKind) -> Int
//     static func governingPhaseIndex(on day: String, phases: [TimelinePhase]) -> Int?
//     static func waypointIssue(weightKg: Double, on day: String,
//                               phases: [TimelinePhase]) -> TimelineWaypointIssue?
//
// Existing API (not stage 6): CutScorecardProjectionStatus (all nine cases), and from the test target
// CutScorecardFixture.dayNumber(_:) / .dayKey(_:). These tests do not call CanonicalDay.
//
// SPEC-AMBIGUITY (asserted): fields that do not apply to an item's kind hold their empty value: `endDay`
// nil and `isOpenEnded` false off spans, `isApproximate` and `isDone` false and `category` nil off
// checkpoints, `sourceIndex` nil on today and projection, `phaseIsCut` nil on today, projection, scan and
// span items. §6.3 says so only through its field comments. `phaseIsCut` on a checkpoint item is not
// asserted: §7.3 does not say whether a target-date item carries its phase's kind.
// SPEC-AMBIGUITY (asserted): the today item's `day` is `today`.
// SPEC-AMBIGUITY (asserted): with an invalid `today` every rejection counter is zero (§7.3 step 1 stops
// before anything is judged), and a source that is not `on` contributes no rejection (its entries are
// "used only when" it is on).
// SPEC-AMBIGUITY (asserted): a span whose `endDay` is set and not canonical counts as `invalidDay`.
// SPEC-AMBIGUITY (not asserted): whether a `projected` projection with a non-canonical target day is
// counted anywhere; only its absence from the list is asserted.

private typealias F = CutScorecardFixture

/// The `today` most tests use.
private let today0 = "2031-03-10"

/// `base` moved by `offset` days.
private func day(_ base: String, _ offset: Int) -> String {
    F.dayKey(F.dayNumber(base) + offset)
}

/// The day number of a canonical "yyyy-MM-dd" key, nil for anything else. Safe on any string.
private func canonicalNumber(_ key: String) -> Int? {
    let bytes = Array(key.utf8)
    guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45, !key.hasPrefix("0000") else { return nil }
    for (index, byte) in bytes.enumerated() where index != 4 && index != 7 {
        guard byte >= 48, byte <= 57 else { return nil }
    }
    let number = F.dayNumber(key)
    return F.dayKey(number) == key ? number : nil
}

/// `values[index]`, or nil when the index is missing or out of range, so that a wrong list fails an
/// assertion and does not stop the run.
private func at<T>(_ values: [T], _ index: Int?) -> T? {
    guard let index, values.indices.contains(index) else { return nil }
    return values[index]
}

private func phase(_ start: String, cut: Bool = true, target: Double? = nil) -> TimelinePhase {
    TimelinePhase(startDay: start, isCut: cut, targetWeightKg: target)
}

private func checkpoint(_ day: String, _ category: TimelineCheckpointCategory = .other,
                        approximate: Bool = false, waypoint: Double? = nil,
                        phaseStart: String? = nil, done: Bool = false) -> TimelineCheckpoint {
    TimelineCheckpoint(day: day, isApproximate: approximate, category: category,
                       waypointWeightKg: waypoint, phaseStartDay: phaseStart, isDone: done)
}

private func span(_ kind: TimelineSpanKind, _ start: String, _ end: String?) -> TimelineSpan {
    TimelineSpan(kind: kind, startDay: start, endDay: end)
}

private func projected(_ day: String?) -> TimelineProjection {
    TimelineProjection(status: .projected, targetDay: day)
}

private func build(phases: [TimelinePhase] = [], checkpoints: [TimelineCheckpoint] = [],
                   scanDays: [String] = [], spans: [TimelineSpan] = [],
                   projection: TimelineProjection? = nil, scans: TimelineSourceState = .on,
                   events: TimelineSourceState = .on,
                   today: String = today0) -> CheckpointTimelineResult {
    CheckpointTimeline.build(CheckpointTimelineInput(
        phases: phases, checkpoints: checkpoints, scanDays: scanDays, spans: spans,
        projection: projection, scans: scans, events: events, today: today))
}

private func rejections(invalidDay: Int = 0, endBeforeStart: Int = 0, futureScan: Int = 0,
                        duplicate: Int = 0, nonFinite: Int = 0,
                        waypointBeyondTarget: Int = 0) -> TimelineRejections {
    TimelineRejections(invalidDay: invalidDay, endBeforeStart: endBeforeStart, futureScan: futureScan,
                       duplicate: duplicate, nonFinite: nonFinite,
                       waypointBeyondTarget: waypointBeyondTarget)
}

/// One item as "kind day position #sourceIndex", for comparing whole lists.
private func line(_ item: TimelineItem) -> String {
    let index = item.sourceIndex.map(String.init) ?? "-"
    return "\(item.kind.rawValue) \(item.day) \(item.position.rawValue) #\(index)"
}

private func lines(_ result: CheckpointTimelineResult) -> [String] { result.items.map(line) }

private func items(_ result: CheckpointTimelineResult, _ kind: TimelineItemKind) -> [TimelineItem] {
    result.items.filter { $0.kind == kind }
}

private let nonCanonicalDays = [
    "", "2031-3-10", "2031-03-1", "20310310", "2031/03/10", "2031-02-30", "2031-13-01",
    "0000-01-01", "2031-03-10 ", "nonsense",
]

private let otherProjectionStatuses: [CutScorecardProjectionStatus] = [
    .noActivePhase, .noTarget, .targetReached, .rateUnknown, .notLosing, .beyondHorizon,
    .needsNewWeighIn, .weighInOverdue,
]

/// `CheckpointTimeline` (stage 6 specification §6.3, §7.3, test plan §12.1, fixture §13.4).
///
/// Every value here is invented. Expected lists were worked by hand from §7.3; none is the output of an
/// implementation.
final class CheckpointTimelineTests: XCTestCase {

    /// The invariants every valid result keeps: one today item where `todayIndex` says, and a list in
    /// the order of §7.3 step 9.
    private func assertWellFormed(_ result: CheckpointTimelineResult,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(result.invalidToday, file: file, line: line)
        let todays = result.items.indices.filter { result.items[$0].kind == .today }
        XCTAssertEqual(todays.count, 1, file: file, line: line)
        XCTAssertEqual(result.todayIndex, todays.first, file: file, line: line)
        let keys = result.items.map {
            [canonicalNumber($0.day) ?? -1, CheckpointTimeline.kindOrder($0.kind), $0.sourceIndex ?? 0]
        }
        for (earlier, later) in zip(keys, keys.dropFirst()) {
            XCTAssertTrue(earlier.lexicographicallyPrecedes(later), "\(earlier) then \(later)",
                          file: file, line: line)
        }
    }

    // MARK: - The list and its order

    func testOnlyTodayWhenEverythingIsEmpty() {
        for scans in [TimelineSourceState.notBuilt, .off, .on] {
            for events in [TimelineSourceState.notBuilt, .off, .on] {
                let result = build(scans: scans, events: events)
                XCTAssertEqual(result.items.count, 1)
                XCTAssertEqual(result.todayIndex, 0)
                XCTAssertFalse(result.invalidToday)
                XCTAssertEqual(result.rejections, rejections())
                guard let item = result.items.first else { return XCTFail("no today item") }
                XCTAssertEqual(item.kind, .today)
                XCTAssertEqual(item.day, today0)
                XCTAssertEqual(item.position, .current)
                XCTAssertNil(item.sourceIndex)
                XCTAssertNil(item.endDay)
                XCTAssertFalse(item.isOpenEnded)
                XCTAssertFalse(item.isApproximate)
                XCTAssertFalse(item.isDone)
                XCTAssertFalse(item.isEstimate)
                XCTAssertNil(item.category)
                XCTAssertNil(item.targetWeightKg)
                XCTAssertNil(item.waypointWeightKg)
                XCTAssertNil(item.phaseIndex)
                XCTAssertNil(item.phaseIsCut)
            }
        }
    }

    func testKindOrderIsPhaseScanCheckpointDietBreakDeloadTodayProjection() {
        let order: [TimelineItemKind] = [.phaseStart, .scan, .checkpoint, .dietBreak, .deload, .today,
                                         .projection]
        XCTAssertEqual(order.map(CheckpointTimeline.kindOrder), [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(Set(TimelineItemKind.allCases), Set(order))
    }

    func testItemsAreAscendingByDayThenKindThenIndex() {
        let before = day(today0, -5), after = day(today0, 5)
        let result = build(
            phases: [phase(after), phase(before), phase(today0)],
            checkpoints: [checkpoint(after), checkpoint(today0), checkpoint(before), checkpoint(today0)],
            scanDays: [today0, before],
            spans: [span(.deload, today0, day(today0, 1)), span(.dietBreak, today0, nil),
                    span(.deload, before, day(today0, -4)), span(.dietBreak, after, nil)],
            projection: projected(today0))
        XCTAssertEqual(lines(result), [
            "phaseStart \(before) past #1",
            "scan \(before) past #1",
            "checkpoint \(before) past #2",
            "deload \(before) past #2",
            "phaseStart \(today0) current #2",
            "scan \(today0) current #0",
            "checkpoint \(today0) current #1",
            "checkpoint \(today0) current #3",
            "dietBreak \(today0) current #1",
            "deload \(today0) current #0",
            "today \(today0) current #-",
            "projection \(today0) current #-",
            "phaseStart \(after) upcoming #0",
            "checkpoint \(after) upcoming #0",
            "dietBreak \(after) upcoming #3",
        ])
        XCTAssertEqual(result.todayIndex, 10)
        XCTAssertEqual(result.rejections, rejections())
        assertWellFormed(result)
        // Day outranks kind: a later day's phase start follows an earlier day's projection.
        let crossed = build(phases: [phase(day(today0, 9))], projection: projected(day(today0, 8)))
        XCTAssertEqual(crossed.items.map(\.kind), [.today, .projection, .phaseStart])
        // Order is by the calendar, not by the text of the key across a year end.
        let yearEnd = build(checkpoints: [checkpoint("2032-01-01"), checkpoint("2031-12-31")],
                            today: "2031-12-30")
        XCTAssertEqual(yearEnd.items.map(\.day), ["2031-12-30", "2031-12-31", "2032-01-01"])
    }

    func testTodayMarkerFollowsItemsDatedToday() {
        let dated: [(String, CheckpointTimelineResult)] = [
            ("phase", build(phases: [phase(today0)])),
            ("scan", build(scanDays: [today0])),
            ("checkpoint", build(checkpoints: [checkpoint(today0)])),
            ("dietBreak", build(spans: [span(.dietBreak, today0, nil)])),
            ("deload", build(spans: [span(.deload, today0, today0)])),
        ]
        for (name, result) in dated {
            XCTAssertEqual(result.items.count, 2, name)
            XCTAssertEqual(result.items.last?.kind, .today, name)
            XCTAssertEqual(result.todayIndex, 1, name)
            XCTAssertEqual(result.items.first?.position, .current, name)
        }
        // Yesterday's items precede the marker and tomorrow's follow it.
        let around = build(checkpoints: [checkpoint(day(today0, 1)), checkpoint(day(today0, -1))])
        XCTAssertEqual(around.items.map(\.kind), [.checkpoint, .today, .checkpoint])
        XCTAssertEqual(around.items.map(\.position), [.past, .current, .upcoming])
        XCTAssertEqual(around.todayIndex, 1)
        // The projection is the one dated item that follows the marker on the same day.
        let estimate = build(checkpoints: [checkpoint(today0)], projection: projected(today0))
        XCTAssertEqual(estimate.items.map(\.kind), [.checkpoint, .today, .projection])
        XCTAssertEqual(estimate.todayIndex, 1)
    }

    func testProjectionIsLastOnItsDayAndMarkedEstimate() {
        let target = day(today0, 30)
        let result = build(
            phases: [phase(target, cut: false)],
            checkpoints: [checkpoint(target, .targetDate), checkpoint(target, .weightWaypoint)],
            spans: [span(.deload, target, nil), span(.dietBreak, target, day(target, 6))],
            projection: projected(target))
        XCTAssertEqual(result.items.map(\.kind),
                       [.today, .phaseStart, .checkpoint, .checkpoint, .dietBreak, .deload, .projection])
        guard let item = result.items.last else { return XCTFail("empty list") }
        XCTAssertTrue(item.isEstimate)
        XCTAssertEqual(item.day, target)
        XCTAssertEqual(item.position, .upcoming)
        XCTAssertNil(item.sourceIndex)
        XCTAssertNil(item.endDay)
        XCTAssertFalse(item.isOpenEnded)
        XCTAssertFalse(item.isApproximate)
        XCTAssertFalse(item.isDone)
        XCTAssertNil(item.category)
        XCTAssertNil(item.targetWeightKg)
        XCTAssertNil(item.waypointWeightKg)
        XCTAssertNil(item.phaseIndex)
        XCTAssertNil(item.phaseIsCut)
        // Nothing else is an estimate.
        XCTAssertEqual(result.items.filter(\.isEstimate).map(\.kind), [.projection])
        // A projected day in the past is still listed, as past.
        let past = build(projection: projected(day(today0, -1)))
        XCTAssertEqual(lines(past), ["projection \(day(today0, -1)) past #-", "today \(today0) current #-"])
        XCTAssertEqual(past.todayIndex, 1)
        XCTAssertEqual(lines(build(projection: projected(day(today0, 1)))),
                       ["today \(today0) current #-", "projection \(day(today0, 1)) upcoming #-"])
    }

    func testProjectionAppearsOnlyWhenProjected() {
        let target = day(today0, 30)
        XCTAssertEqual(items(build(projection: projected(target)), .projection).count, 1)
        for status in otherProjectionStatuses {
            let result = build(projection: TimelineProjection(status: status, targetDay: target))
            XCTAssertEqual(result.items.map(\.kind), [.today], status.rawValue)
            XCTAssertEqual(result.todayIndex, 0, status.rawValue)
            XCTAssertFalse(result.items.contains(where: \.isEstimate), status.rawValue)
        }
        // "Projected" with no day, or a day that is not canonical, yields no item either.
        XCTAssertEqual(build(projection: projected(nil)).items.map(\.kind), [.today])
        for bad in nonCanonicalDays {
            XCTAssertEqual(build(projection: projected(bad)).items.map(\.kind), [.today], bad)
        }
    }

    func testNilProjectionYieldsNoItem() {
        let result = build(phases: [phase("2031-01-06", target: 94)],
                           checkpoints: [checkpoint(day(today0, 3))], projection: nil)
        XCTAssertEqual(result.items.map(\.kind), [.phaseStart, .today, .checkpoint])
        XCTAssertFalse(result.items.contains(where: \.isEstimate))
        XCTAssertEqual(result.rejections, rejections())
    }

    // MARK: - Sources

    func testScansAreIgnoredUnlessTheSourceIsOn() {
        let scanDays = [day(today0, -3), day(today0, -3), day(today0, 4), "nonsense"]
        let planned = [checkpoint(day(today0, -3), .scan)]
        for state in [TimelineSourceState.notBuilt, .off] {
            let result = build(checkpoints: planned, scanDays: scanDays, scans: state)
            XCTAssertEqual(items(result, .scan), [], state.rawValue)
            // No scan day was read: nothing is rejected and the planned scan is not displaced.
            XCTAssertEqual(result.rejections, rejections(), state.rawValue)
            XCTAssertEqual(result.items.map(\.kind), [.checkpoint, .today], state.rawValue)
            XCTAssertEqual(result.scans, state)
        }
        let on = build(checkpoints: planned, scanDays: scanDays, scans: .on)
        XCTAssertEqual(lines(on), ["scan \(day(today0, -3)) past #0", "today \(today0) current #-"])
        XCTAssertEqual(on.rejections, rejections(invalidDay: 1, futureScan: 1, duplicate: 2))
    }

    func testSpansAreIgnoredUnlessTheSourceIsOn() {
        let spans = [span(.deload, day(today0, -9), day(today0, -3)), span(.dietBreak, today0, nil),
                     span(.deload, "nonsense", nil), span(.dietBreak, today0, day(today0, -1))]
        for state in [TimelineSourceState.notBuilt, .off] {
            let result = build(spans: spans, events: state)
            XCTAssertEqual(result.items.map(\.kind), [.today], state.rawValue)
            XCTAssertEqual(result.rejections, rejections(), state.rawValue)
            XCTAssertEqual(result.events, state)
        }
        let on = build(spans: spans, events: .on)
        XCTAssertEqual(on.items.map(\.kind), [.deload, .dietBreak, .today])
        XCTAssertEqual(on.rejections, rejections(invalidDay: 1, endBeforeStart: 1))
        // The two sources are independent.
        let scansOnly = build(scanDays: [day(today0, -1)], spans: spans, scans: .on, events: .off)
        XCTAssertEqual(scansOnly.items.map(\.kind), [.scan, .today])
        let eventsOnly = build(scanDays: [day(today0, -1)], spans: spans, scans: .off, events: .on)
        XCTAssertEqual(eventsOnly.items.map(\.kind), [.deload, .dietBreak, .today])
    }

    func testSourceStatesAreEchoed() {
        for scans in [TimelineSourceState.notBuilt, .off, .on] {
            for events in [TimelineSourceState.notBuilt, .off, .on] {
                let valid = build(scanDays: [today0], spans: [span(.deload, today0, nil)],
                                  scans: scans, events: events)
                XCTAssertEqual(valid.scans, scans)
                XCTAssertEqual(valid.events, events)
                let invalid = build(scans: scans, events: events, today: "nonsense")
                XCTAssertEqual(invalid.scans, scans)
                XCTAssertEqual(invalid.events, events)
            }
        }
    }

    // MARK: - Scans

    func testFutureScanDayIsRejected() {
        let result = build(scanDays: [day(today0, 1), today0, day(today0, -1), day(today0, 200)])
        XCTAssertEqual(lines(result), [
            "scan \(day(today0, -1)) past #2",
            "scan \(today0) current #1",
            "today \(today0) current #-",
        ])
        XCTAssertEqual(result.rejections, rejections(futureScan: 2))
    }

    func testRepeatedScanDayIsCountedOnce() {
        let a = day(today0, -20), b = day(today0, -10)
        let result = build(scanDays: [a, b, a])
        XCTAssertEqual(lines(result), ["scan \(a) past #0", "scan \(b) past #1",
                                       "today \(today0) current #-"])
        XCTAssertEqual(result.rejections, rejections(duplicate: 1))
        // The item is listed once however often the day repeats; each repeat is counted.
        let many = build(scanDays: [b, a, a, a, b])
        XCTAssertEqual(lines(many), ["scan \(a) past #1", "scan \(b) past #0",
                                     "today \(today0) current #-"])
        XCTAssertEqual(many.rejections, rejections(duplicate: 3))
    }

    func testScanCheckpointOnARecordedScanDayIsDropped() {
        let scanDay = day(today0, -7)
        let result = build(checkpoints: [checkpoint(scanDay, .scan), checkpoint(scanDay, .bloodPanel)],
                           scanDays: [scanDay])
        // The recorded scan stands for the planned one; another category on that day stays.
        XCTAssertEqual(lines(result), ["scan \(scanDay) past #0", "checkpoint \(scanDay) past #1",
                                       "today \(today0) current #-"])
        XCTAssertEqual(at(result.items, 1)?.category, .bloodPanel)
        XCTAssertEqual(result.rejections, rejections(duplicate: 1))
        // Two planned scans on the recorded day are both dropped.
        let two = build(checkpoints: [checkpoint(scanDay, .scan), checkpoint(scanDay, .scan, done: true)],
                        scanDays: [scanDay])
        XCTAssertEqual(two.items.map(\.kind), [.scan, .today])
        XCTAssertEqual(two.rejections, rejections(duplicate: 2))
    }

    func testScanCheckpointOnAnotherDayIsKept() {
        let scanDay = day(today0, -7)
        for other in [day(scanDay, -1), day(scanDay, 1), day(today0, 14)] {
            let result = build(checkpoints: [checkpoint(other, .scan)], scanDays: [scanDay])
            XCTAssertEqual(items(result, .checkpoint).map(\.day), [other])
            XCTAssertEqual(items(result, .checkpoint).first?.category, .scan)
            XCTAssertEqual(items(result, .scan).map(\.day), [scanDay])
            XCTAssertEqual(result.rejections, rejections())
        }
        // A scan day that was itself rejected displaces nothing.
        let future = day(today0, 14)
        let rejected = build(checkpoints: [checkpoint(future, .scan)], scanDays: [future])
        XCTAssertEqual(rejected.items.map(\.kind), [.today, .checkpoint])
        XCTAssertEqual(rejected.rejections, rejections(futureScan: 1))
    }

    // MARK: - Spans

    func testSpanPositions() {
        let cases: [(String, String, String?, TimelinePosition)] = [
            ("before", day(today0, -30), day(today0, -20), .past),
            ("ending yesterday", day(today0, -9), day(today0, -1), .past),
            ("ending today", day(today0, -9), today0, .current),
            ("spanning today", day(today0, -5), day(today0, 5), .current),
            ("starting today", today0, day(today0, 10), .current),
            ("starting tomorrow", day(today0, 1), day(today0, 10), .upcoming),
            ("open-ended in the past", day(today0, -30), nil, .current),
            ("open-ended from yesterday", day(today0, -1), nil, .current),
            ("open-ended from today", today0, nil, .current),
            ("open-ended in the future", day(today0, 20), nil, .upcoming),
            ("open-ended from tomorrow", day(today0, 1), nil, .upcoming),
            ("zero-length today", today0, today0, .current),
            ("zero-length yesterday", day(today0, -1), day(today0, -1), .past),
            ("zero-length tomorrow", day(today0, 1), day(today0, 1), .upcoming),
        ]
        for kind in TimelineSpanKind.allCases {
            for (name, start, end, position) in cases {
                let result = build(spans: [span(kind, start, end)])
                let found = result.items.filter { $0.kind != .today }
                XCTAssertEqual(found.count, 1, name)
                guard let item = found.first else { continue }
                XCTAssertEqual(item.kind, kind == .deload ? .deload : .dietBreak, name)
                XCTAssertEqual(item.position, position, name)
                XCTAssertEqual(item.day, start, name)
                XCTAssertEqual(item.endDay, end, name)
                XCTAssertEqual(item.isOpenEnded, end == nil, name)
                XCTAssertEqual(item.sourceIndex, 0, name)
                XCTAssertFalse(item.isEstimate, name)
                XCTAssertNil(item.category, name)
                XCTAssertNil(item.targetWeightKg, name)
                XCTAssertNil(item.phaseIsCut, name)
                XCTAssertEqual(result.rejections, rejections(), name)
                assertWellFormed(result)
            }
        }
    }

    func testSpanEndingBeforeItStartsIsRejected() {
        let start = day(today0, -4)
        let result = build(spans: [span(.deload, start, day(start, -1)),
                                   span(.dietBreak, start, day(start, -30)),
                                   span(.deload, start, start),
                                   span(.dietBreak, start, day(start, 1))])
        XCTAssertEqual(lines(result), ["dietBreak \(start) past #3", "deload \(start) past #2",
                                       "today \(today0) current #-"])
        XCTAssertEqual(result.rejections, rejections(endBeforeStart: 2))
    }

    // MARK: - Checkpoints

    func testCheckpointPositionsAndFlagsAreCarried() {
        let result = build(checkpoints: [
            checkpoint(day(today0, 1), .appointment, approximate: true, done: false),
            checkpoint(today0, .benchmark, approximate: false, done: true),
            checkpoint(day(today0, -1), .bloodPanel, approximate: true, done: true),
            checkpoint(day(today0, 40), .other),
        ])
        XCTAssertEqual(lines(result), [
            "checkpoint \(day(today0, -1)) past #2",
            "checkpoint \(today0) current #1",
            "today \(today0) current #-",
            "checkpoint \(day(today0, 1)) upcoming #0",
            "checkpoint \(day(today0, 40)) upcoming #3",
        ])
        let found = items(result, .checkpoint)
        XCTAssertEqual(found.map(\.category), [.bloodPanel, .benchmark, .appointment, .other])
        XCTAssertEqual(found.map(\.isApproximate), [true, false, true, false])
        XCTAssertEqual(found.map(\.isDone), [true, true, false, false])
        for item in found {
            XCTAssertNil(item.endDay)
            XCTAssertFalse(item.isOpenEnded)
            XCTAssertFalse(item.isEstimate)
        }
        // A past checkpoint that is not done is simply past: there is no fourth position.
        let late = build(checkpoints: [checkpoint(day(today0, -60), .benchmark, done: false)])
        XCTAssertEqual(late.items.first?.position, .past)
        XCTAssertEqual(late.items.first?.isDone, false)
        // Every category gives a checkpoint item of that category.
        for category in TimelineCheckpointCategory.allCases {
            let one = build(checkpoints: [checkpoint(day(today0, 2), category)])
            XCTAssertEqual(items(one, .checkpoint).map(\.category), [category], category.rawValue)
        }
    }

    func testTargetWeightIsCarriedOnlyOnPhaseStartItems() {
        let result = build(
            phases: [phase("2031-01-06", cut: true, target: 94.0), phase("2031-06-16", cut: false)],
            checkpoints: [checkpoint("2031-03-19", .weightWaypoint, waypoint: 96.0),
                          checkpoint("2031-06-02", .targetDate, phaseStart: "2031-01-06"),
                          checkpoint("2031-02-10", .bloodPanel),
                          checkpoint("2031-03-01", .scan), checkpoint("2031-03-02", .benchmark),
                          checkpoint("2031-03-03", .appointment), checkpoint("2031-03-04", .other)],
            scanDays: ["2031-01-08"],
            spans: [span(.deload, "2031-02-17", "2031-02-23"), span(.dietBreak, "2031-03-24", nil)],
            projection: projected("2031-05-27"))
        XCTAssertEqual(result.items.count, 14)
        for item in result.items where item.kind != .phaseStart {
            XCTAssertNil(item.targetWeightKg, line(item))
        }
        let phases = items(result, .phaseStart)
        XCTAssertEqual(phases.map(\.targetWeightKg), [94.0, nil])
        XCTAssertEqual(phases.map(\.phaseIsCut), [true, false])
        XCTAssertEqual(phases.map(\.sourceIndex), [0, 1])
        XCTAssertEqual(phases.map(\.position), [.past, .upcoming])
        for item in phases {
            XCTAssertNil(item.waypointWeightKg)
            XCTAssertNil(item.phaseIndex)
            XCTAssertNil(item.category)
            XCTAssertFalse(item.isEstimate)
        }
        XCTAssertEqual(result.rejections, rejections())
    }

    func testWaypointWeightIsCarriedOnlyForWeightWaypoints() {
        let d = day(today0, 5)
        for category in TimelineCheckpointCategory.allCases {
            let result = build(checkpoints: [checkpoint(d, category, waypoint: 96.0)])
            let item = items(result, .checkpoint).first
            XCTAssertEqual(item?.waypointWeightKg, category == .weightWaypoint ? 96.0 : nil,
                           category.rawValue)
            // A weight on another category is not a waypoint and is not judged as one.
            XCTAssertEqual(result.rejections, rejections(), category.rawValue)
        }
        // A waypoint with no weight is a waypoint with no weight: nothing is counted.
        let empty = build(checkpoints: [checkpoint(d, .weightWaypoint, waypoint: nil)])
        XCTAssertNil(items(empty, .checkpoint).first?.waypointWeightKg)
        XCTAssertEqual(items(empty, .checkpoint).count, 1)
        XCTAssertEqual(empty.rejections, rejections())
        // No other kind of item carries one.
        let mixed = build(phases: [phase("2031-01-06", target: 94)], scanDays: ["2031-01-08"],
                          spans: [span(.deload, "2031-02-17", nil)], projection: projected("2031-05-27"))
        for item in mixed.items { XCTAssertNil(item.waypointWeightKg, line(item)) }
    }

    func testNonFiniteTargetWeightIsDroppedAndCounted() {
        let bad: [Double] = [.nan, .infinity, -.infinity, 0, -0.0, -1, -Double.leastNonzeroMagnitude]
        for target in bad {
            let result = build(phases: [phase("2031-01-06", target: target)])
            let item = items(result, .phaseStart).first
            XCTAssertEqual(items(result, .phaseStart).count, 1, "\(target)")
            XCTAssertNil(item?.targetWeightKg, "\(target)")
            XCTAssertEqual(item?.phaseIsCut, true, "\(target)")
            XCTAssertEqual(result.rejections, rejections(nonFinite: 1), "\(target)")
        }
        // The least positive weight is positive; a missing target is not a rejection.
        let least = build(phases: [phase("2031-01-06", target: Double.leastNonzeroMagnitude)])
        XCTAssertEqual(items(least, .phaseStart).first?.targetWeightKg, Double.leastNonzeroMagnitude)
        XCTAssertEqual(least.rejections, rejections())
        XCTAssertEqual(build(phases: [phase("2031-01-06", target: nil)]).rejections, rejections())
        // Each bad target is counted.
        let three = build(phases: [phase("2031-01-06", target: .nan), phase("2031-02-03", target: 94),
                                   phase("2031-03-03", target: 0)])
        XCTAssertEqual(three.rejections, rejections(nonFinite: 2))
        XCTAssertEqual(items(three, .phaseStart).map(\.targetWeightKg), [nil, 94, nil])
    }

    // MARK: - Waypoints against the phase target

    /// One waypoint of `weight` on 2031-03-19 against `phases`; returns the built item's weight, the
    /// counters, and what `waypointIssue` says for the same case.
    private func waypoint(_ weight: Double, _ phases: [TimelinePhase], on waypointDay: String = "2031-03-19")
        -> (carried: Double?, rejections: TimelineRejections, issue: TimelineWaypointIssue?, kept: Int) {
        let result = build(phases: phases,
                           checkpoints: [checkpoint(waypointDay, .weightWaypoint, waypoint: weight)],
                           today: "2031-02-05")
        let found = items(result, .checkpoint)
        return (found.first?.waypointWeightKg, result.rejections,
                CheckpointTimeline.waypointIssue(weightKg: weight, on: waypointDay, phases: phases),
                found.count)
    }

    private let cut94 = [phase("2031-01-06", cut: true, target: 94.0)]
    private let other94 = [phase("2031-01-06", cut: false, target: 94.0)]

    func testNonFiniteOrNonPositiveWaypointWeightIsDroppedAndCounted() {
        let bad: [Double] = [.nan, .infinity, -.infinity, 0, -0.0, -96, -Double.leastNonzeroMagnitude]
        for phases in [[], cut94, other94] {
            for weight in bad {
                let found = waypoint(weight, phases)
                XCTAssertNil(found.carried, "\(weight)")
                XCTAssertEqual(found.kept, 1, "\(weight)")
                XCTAssertEqual(found.rejections, rejections(nonFinite: 1), "\(weight)")
                XCTAssertEqual(found.issue, .nonFinite, "\(weight)")
            }
        }
        // The least positive weight is positive: with no phase it is kept.
        let least = waypoint(Double.leastNonzeroMagnitude, [])
        XCTAssertEqual(least.carried, Double.leastNonzeroMagnitude)
        XCTAssertNil(least.issue)
        XCTAssertEqual(least.rejections, rejections())
    }

    func testWaypointShortOfACutTargetKeepsItsWeight() {
        for weight in [96.0, 94.5, (94.0).nextUp] {
            let found = waypoint(weight, cut94)
            XCTAssertEqual(found.carried, weight, "\(weight)")
            XCTAssertNil(found.issue, "\(weight)")
            XCTAssertEqual(found.rejections, rejections(), "\(weight)")
        }
    }

    func testWaypointEqualToACutTargetLosesItsWeightAndIsCounted() {
        let found = waypoint(94.0, cut94)
        XCTAssertNil(found.carried)
        XCTAssertEqual(found.issue, .atOrBeyondTarget)
        XCTAssertEqual(found.rejections, rejections(waypointBeyondTarget: 1))
    }

    func testWaypointBelowACutTargetLosesItsWeightAndIsCounted() {
        for weight in [(94.0).nextDown, 93.9, 80.0, Double.leastNonzeroMagnitude] {
            let found = waypoint(weight, cut94)
            XCTAssertNil(found.carried, "\(weight)")
            XCTAssertEqual(found.issue, .atOrBeyondTarget, "\(weight)")
            XCTAssertEqual(found.rejections, rejections(waypointBeyondTarget: 1), "\(weight)")
        }
    }

    func testWaypointEqualToANonCutTargetLosesItsWeight() {
        let found = waypoint(94.0, other94)
        XCTAssertNil(found.carried)
        XCTAssertEqual(found.issue, .atOrBeyondTarget)
        XCTAssertEqual(found.rejections, rejections(waypointBeyondTarget: 1))
    }

    func testWaypointEitherSideOfANonCutTargetKeepsItsWeight() {
        for weight in [(94.0).nextDown, (94.0).nextUp, 90.0, 98.0] {
            let found = waypoint(weight, other94)
            XCTAssertEqual(found.carried, weight, "\(weight)")
            XCTAssertNil(found.issue, "\(weight)")
            XCTAssertEqual(found.rejections, rejections(), "\(weight)")
        }
    }

    func testWaypointWithNoGoverningPhaseOrNoPhaseTargetIsKept() {
        // No phase at all, and a phase that starts after the waypoint's day.
        for phases in [[], [phase("2031-03-20", target: 99.0)]] {
            let found = waypoint(96.0, phases)
            XCTAssertEqual(found.carried, 96.0)
            XCTAssertNil(found.issue)
            XCTAssertEqual(found.rejections, rejections())
        }
        // A governing phase with no target.
        for cut in [true, false] {
            let found = waypoint(96.0, [phase("2031-01-06", cut: cut, target: nil)])
            XCTAssertEqual(found.carried, 96.0)
            XCTAssertNil(found.issue)
            XCTAssertEqual(found.rejections, rejections())
        }
        // A governing phase whose target is unusable: the waypoint is kept, and the one rejection
        // counted is the phase's own target (§7.3 step 2), not the waypoint.
        for target in [Double.nan, .infinity, 0, -94] {
            let found = waypoint(96.0, [phase("2031-01-06", target: target)])
            XCTAssertEqual(found.carried, 96.0, "\(target)")
            XCTAssertNil(found.issue, "\(target)")
            XCTAssertEqual(found.rejections, rejections(nonFinite: 1), "\(target)")
        }
        // A waypoint day that is not canonical has no governing phase.
        XCTAssertNil(CheckpointTimeline.waypointIssue(weightKg: 90, on: "nonsense", phases: cut94))
        XCTAssertEqual(CheckpointTimeline.waypointIssue(weightKg: .nan, on: "nonsense", phases: cut94),
                       .nonFinite)
    }

    func testWaypointIsJudgedAgainstThePhaseInForceOnItsOwnDay() {
        // A first cut to 94 and a second, from 2031-04-07, to 90.
        let phases = [phase("2031-01-06", target: 94.0), phase("2031-04-07", target: 90.0)]
        let first = waypoint(92.0, phases, on: "2031-03-19")
        XCTAssertNil(first.carried)
        XCTAssertEqual(first.issue, .atOrBeyondTarget)
        XCTAssertEqual(first.rejections, rejections(waypointBeyondTarget: 1))
        let second = waypoint(92.0, phases, on: "2031-05-01")
        XCTAssertEqual(second.carried, 92.0)
        XCTAssertNil(second.issue)
        XCTAssertEqual(second.rejections, rejections())
        // The day the second phase starts is already governed by it; the day before is not.
        XCTAssertEqual(waypoint(92.0, phases, on: "2031-04-07").carried, 92.0)
        XCTAssertNil(waypoint(92.0, phases, on: "2031-04-06").carried)
        // The phases' input order is irrelevant; and "today" plays no part.
        let reversed = Array(phases.reversed())
        XCTAssertNil(waypoint(92.0, reversed, on: "2031-03-19").carried)
        XCTAssertEqual(waypoint(92.0, reversed, on: "2031-05-01").carried, 92.0)
        // A cut followed by a phase of kind other with the same target: only equality is refused.
        let mixed = [phase("2031-01-06", cut: true, target: 94.0),
                     phase("2031-04-07", cut: false, target: 94.0)]
        XCTAssertNil(waypoint(93.0, mixed, on: "2031-03-19").carried)
        XCTAssertEqual(waypoint(93.0, mixed, on: "2031-05-01").carried, 93.0)
    }

    func testWaypointItemStaysWhenItsWeightIsDropped() {
        let result = build(phases: cut94,
                           checkpoints: [checkpoint("2031-03-19", .weightWaypoint, approximate: true,
                                                    waypoint: 94.0, done: true),
                                         checkpoint("2031-03-20", .weightWaypoint, waypoint: .nan)],
                           today: "2031-02-05")
        let found = items(result, .checkpoint)
        XCTAssertEqual(found.map(\.day), ["2031-03-19", "2031-03-20"])
        XCTAssertEqual(found.map(\.category), [.weightWaypoint, .weightWaypoint])
        XCTAssertEqual(found.map(\.waypointWeightKg), [nil, nil])
        XCTAssertEqual(found.map(\.sourceIndex), [0, 1])
        XCTAssertEqual(found.first?.isApproximate, true)
        XCTAssertEqual(found.first?.isDone, true)
        XCTAssertEqual(found.first?.position, .upcoming)
        XCTAssertEqual(result.rejections, rejections(nonFinite: 1, waypointBeyondTarget: 1))
    }

    func testWaypointIssueAgreesWithBuildForEveryCase() {
        let weights: [Double] = [.nan, .infinity, -.infinity, 0, -1, 80, 93, (94.0).nextDown, 94,
                                 (94.0).nextUp, 96, 99, 120]
        let phaseSets: [[TimelinePhase]] = [
            [], cut94, other94,
            [phase("2031-01-06", target: nil)],
            [phase("2031-01-06", target: .nan)],
            [phase("2031-01-06", target: 0)],
            [phase("2031-01-06", target: -5)],
            [phase("2031-03-19", target: 99)],                   // starts on the waypoint's day
            [phase("2031-03-20", target: 99)],                   // starts the day after
            [phase("2031-01-06", target: 90), phase("2031-02-03", target: 94)],
            [phase("2031-02-03", target: 94), phase("2031-01-06", target: 90)],
            [phase("2031-01-06", target: 94), phase("2031-01-06", cut: false, target: 99)],
            [phase("nonsense", target: 120), phase("2031-01-06", cut: false, target: 96)],
        ]
        var seen: Set<String> = []
        for (index, phases) in phaseSets.enumerated() {
            // Unusable targets on phases with a canonical start are counted by step 2.
            let badTargets = phases.filter { p in
                guard canonicalNumber(p.startDay) != nil, let t = p.targetWeightKg else { return false }
                return !(t.isFinite && t > 0)
            }.count
            let badStarts = phases.filter { canonicalNumber($0.startDay) == nil }.count
            for weight in weights {
                let found = waypoint(weight, phases)
                let label = "phases \(index), weight \(weight)"
                seen.insert(found.issue?.rawValue ?? "none")
                XCTAssertEqual(found.kept, 1, label)
                switch found.issue {
                case nil:
                    XCTAssertEqual(found.carried, weight, label)
                case .nonFinite?, .atOrBeyondTarget?:
                    XCTAssertNil(found.carried, label)
                }
                XCTAssertEqual(found.rejections, rejections(
                    invalidDay: badStarts,
                    nonFinite: badTargets + (found.issue == .nonFinite ? 1 : 0),
                    waypointBeyondTarget: found.issue == .atOrBeyondTarget ? 1 : 0), label)
            }
        }
        XCTAssertEqual(seen, ["none", "nonFinite", "atOrBeyondTarget"])
        // Pinned outcomes from the table above, so that agreement cannot be reached by both being wrong.
        XCTAssertEqual(waypoint(99, phaseSets[7]).issue, .atOrBeyondTarget)
        XCTAssertNil(waypoint(99, phaseSets[8]).issue)
        XCTAssertEqual(waypoint(93, phaseSets[9]).issue, .atOrBeyondTarget)   // the later start governs: 94
        XCTAssertEqual(waypoint(93, phaseSets[10]).issue, .atOrBeyondTarget)
        XCTAssertNil(waypoint(96, phaseSets[11]).issue)          // the later index governs: other, 99
        XCTAssertEqual(waypoint(99, phaseSets[11]).issue, .atOrBeyondTarget)
        XCTAssertEqual(waypoint(96, phaseSets[12]).issue, .atOrBeyondTarget)
        XCTAssertNil(waypoint(99, phaseSets[12]).issue)
    }

    // MARK: - The governing phase

    func testGoverningPhaseIsTheLatestStartOnOrBeforeTheDay() {
        let phases = [phase("2031-04-07"), phase("2031-01-06"), phase("2031-06-16", cut: false)]
        func governing(_ day: String) -> Int? {
            CheckpointTimeline.governingPhaseIndex(on: day, phases: phases)
        }
        XCTAssertEqual(governing("2031-01-06"), 1)
        XCTAssertEqual(governing("2031-01-07"), 1)
        XCTAssertEqual(governing("2031-04-06"), 1)
        XCTAssertEqual(governing("2031-04-07"), 0)
        XCTAssertEqual(governing("2031-04-08"), 0)
        XCTAssertEqual(governing("2031-06-15"), 0)
        XCTAssertEqual(governing("2031-06-16"), 2)
        XCTAssertEqual(governing("2099-01-01"), 2)
        // A phase whose start day is not canonical never governs.
        let withBad = [phase("nonsense"), phase("2031-01-06"), phase("2031-02-30")]
        XCTAssertEqual(CheckpointTimeline.governingPhaseIndex(on: "2031-12-31", phases: withBad), 1)
    }

    func testGoverningPhaseTakesTheGreaterIndexAmongEqualStartDays() {
        let phases = [phase("2031-01-06"), phase("2031-01-06", cut: false), phase("2030-01-07"),
                      phase("2031-01-06")]
        XCTAssertEqual(CheckpointTimeline.governingPhaseIndex(on: "2031-01-06", phases: phases), 3)
        XCTAssertEqual(CheckpointTimeline.governingPhaseIndex(on: "2031-05-01", phases: phases), 3)
        XCTAssertEqual(CheckpointTimeline.governingPhaseIndex(on: "2031-01-05", phases: phases), 2)
        XCTAssertEqual(CheckpointTimeline.governingPhaseIndex(
            on: "2031-05-01", phases: Array(phases.prefix(2))), 1)
    }

    func testGoverningPhaseIsNilBeforeTheFirstPhaseAndForANonCanonicalDay() {
        let phases = [phase("2031-01-06"), phase("2031-04-07")]
        XCTAssertNil(CheckpointTimeline.governingPhaseIndex(on: "2031-01-05", phases: phases))
        XCTAssertNil(CheckpointTimeline.governingPhaseIndex(on: "2000-01-01", phases: phases))
        XCTAssertNil(CheckpointTimeline.governingPhaseIndex(on: "2031-06-01", phases: []))
        for bad in nonCanonicalDays {
            XCTAssertNil(CheckpointTimeline.governingPhaseIndex(on: bad, phases: phases), bad)
        }
        XCTAssertNil(CheckpointTimeline.governingPhaseIndex(on: "2031-06-01", phases: [phase("nonsense")]))
    }

    // MARK: - Target dates

    func testTargetDateCarriesItsPhaseIndexAndNoWeight() {
        let phases = [phase("2031-01-06", target: 94.0), phase("2031-06-16", cut: false, target: 95.0),
                      phase("2031-06-16", target: 90.0)]
        let result = build(phases: phases, checkpoints: [
            checkpoint("2031-06-02", .targetDate, waypoint: 94.0, phaseStart: "2031-01-06"),
            checkpoint("2031-09-01", .targetDate, phaseStart: "2031-06-16"),
        ], today: "2031-02-05")
        let found = items(result, .checkpoint)
        XCTAssertEqual(found.map(\.day), ["2031-06-02", "2031-09-01"])
        // The first phase with that start day, even where a later one shares it.
        XCTAssertEqual(found.map(\.phaseIndex), [0, 1])
        XCTAssertEqual(found.map(\.category), [.targetDate, .targetDate])
        for item in found {
            XCTAssertNil(item.targetWeightKg)
            XCTAssertNil(item.waypointWeightKg)
        }
        XCTAssertEqual(result.rejections, rejections())
        // The target date's own day does not decide the phase: it may fall inside another phase.
        let late = build(phases: phases,
                         checkpoints: [checkpoint("2031-08-01", .targetDate, phaseStart: "2031-01-06")],
                         today: "2031-02-05")
        XCTAssertEqual(items(late, .checkpoint).first?.phaseIndex, 0)
    }

    func testTargetDateForAnUnknownPhaseHasNoPhaseIndex() {
        let phases = [phase("2031-01-06", target: 94.0)]
        for start in [nil, "2031-01-07", "2031-01-05", "nonsense", ""] as [String?] {
            let result = build(phases: phases,
                               checkpoints: [checkpoint("2031-06-02", .targetDate, phaseStart: start)],
                               today: "2031-02-05")
            let found = items(result, .checkpoint)
            XCTAssertEqual(found.count, 1, String(describing: start))
            XCTAssertNil(found.first?.phaseIndex, String(describing: start))
            XCTAssertNil(found.first?.targetWeightKg)
            XCTAssertEqual(result.rejections, rejections())
        }
        // With no phases at all.
        let none = build(checkpoints: [checkpoint("2031-06-02", .targetDate, phaseStart: "2031-01-06")])
        XCTAssertNil(items(none, .checkpoint).first?.phaseIndex)
    }

    func testSecondTargetDateForOnePhaseIsDroppedAsDuplicate() {
        let phases = [phase("2031-01-06", target: 94.0), phase("2031-06-16", target: 90.0)]
        let result = build(phases: phases, checkpoints: [
            checkpoint("2031-06-02", .targetDate, phaseStart: "2031-01-06"),
            checkpoint("2031-05-01", .targetDate, phaseStart: "2031-01-06"),
            checkpoint("2031-09-01", .targetDate, phaseStart: "2031-06-16"),
            checkpoint("2031-05-01", .appointment, phaseStart: "2031-01-06"),
        ], today: "2031-02-05")
        // The earlier in input order is kept, though its day is the later one.
        XCTAssertEqual(lines(result).filter { $0.hasPrefix("checkpoint") }, [
            "checkpoint 2031-05-01 upcoming #3",
            "checkpoint 2031-06-02 upcoming #0",
            "checkpoint 2031-09-01 upcoming #2",
        ])
        XCTAssertEqual(result.rejections, rejections(duplicate: 1))
        // A third for the same phase is dropped too.
        let three = build(phases: phases, checkpoints: [
            checkpoint("2031-06-02", .targetDate, phaseStart: "2031-01-06"),
            checkpoint("2031-05-01", .targetDate, phaseStart: "2031-01-06"),
            checkpoint("2031-07-01", .targetDate, phaseStart: "2031-01-06"),
        ], today: "2031-02-05")
        XCTAssertEqual(items(three, .checkpoint).map(\.day), ["2031-06-02"])
        XCTAssertEqual(three.rejections, rejections(duplicate: 2))
        // Target dates attached to no phase are not duplicates of each other.
        let unattached = build(phases: phases, checkpoints: [
            checkpoint("2031-06-02", .targetDate), checkpoint("2031-07-02", .targetDate),
        ], today: "2031-02-05")
        XCTAssertEqual(items(unattached, .checkpoint).count, 2)
        XCTAssertEqual(unattached.rejections, rejections())
        // Only a kept target date blocks a later one: the first here is rejected for its day.
        let afterRejected = build(phases: phases, checkpoints: [
            checkpoint("nonsense", .targetDate, phaseStart: "2031-01-06"),
            checkpoint("2031-06-02", .targetDate, phaseStart: "2031-01-06"),
        ], today: "2031-02-05")
        XCTAssertEqual(items(afterRejected, .checkpoint).map(\.day), ["2031-06-02"])
        XCTAssertEqual(items(afterRejected, .checkpoint).first?.phaseIndex, 0)
        XCTAssertEqual(afterRejected.rejections, rejections(invalidDay: 1))
    }

    func testPhaseIndexIsNilForEveryOtherCategory() {
        let phases = [phase("2031-01-06", target: 94.0)]
        for category in TimelineCheckpointCategory.allCases {
            let result = build(phases: phases, checkpoints: [
                checkpoint("2031-06-02", category, phaseStart: "2031-01-06"),
                checkpoint("2031-06-03", category, phaseStart: "2031-01-06"),
            ], today: "2031-02-05")
            let found = items(result, .checkpoint)
            if category == .targetDate {
                XCTAssertEqual(found.map(\.phaseIndex), [0])
            } else {
                // Two of them: the one-per-phase rule is for target dates only.
                XCTAssertEqual(found.map(\.phaseIndex), [nil, nil], category.rawValue)
                XCTAssertEqual(result.rejections, rejections(), category.rawValue)
            }
        }
        // No other kind of item carries a phase index.
        let mixed = build(phases: phases, scanDays: ["2031-01-08"],
                          spans: [span(.deload, "2031-02-17", nil)], projection: projected("2031-05-27"))
        for item in mixed.items { XCTAssertNil(item.phaseIndex, line(item)) }
    }

    // MARK: - Invalid input

    func testInvalidDaysAreRejectedPerKind() {
        let good = day(today0, -2)
        for bad in nonCanonicalDays {
            let phases = build(phases: [phase(bad, target: 94), phase(good)])
            XCTAssertEqual(lines(phases), ["phaseStart \(good) past #1", "today \(today0) current #-"], bad)
            XCTAssertEqual(phases.rejections, rejections(invalidDay: 1), bad)

            let scans = build(scanDays: [bad, good])
            XCTAssertEqual(lines(scans), ["scan \(good) past #1", "today \(today0) current #-"], bad)
            XCTAssertEqual(scans.rejections, rejections(invalidDay: 1), bad)

            let checkpoints = build(checkpoints: [checkpoint(bad), checkpoint(good)])
            XCTAssertEqual(lines(checkpoints), ["checkpoint \(good) past #1", "today \(today0) current #-"],
                           bad)
            XCTAssertEqual(checkpoints.rejections, rejections(invalidDay: 1), bad)

            let starts = build(spans: [span(.deload, bad, nil), span(.dietBreak, good, nil)])
            XCTAssertEqual(lines(starts), ["dietBreak \(good) current #1", "today \(today0) current #-"], bad)
            XCTAssertEqual(starts.rejections, rejections(invalidDay: 1), bad)

            // SPEC-AMBIGUITY: a non-canonical end day is counted as invalidDay (see the header).
            let ends = build(spans: [span(.deload, good, bad), span(.dietBreak, good, nil)])
            XCTAssertEqual(lines(ends), ["dietBreak \(good) current #1", "today \(today0) current #-"], bad)
            XCTAssertEqual(ends.rejections, rejections(invalidDay: 1), bad)
        }
        // All at once: each kind's rejection is counted.
        let all = build(phases: [phase("nonsense")], checkpoints: [checkpoint("nonsense")],
                        scanDays: ["nonsense"],
                        spans: [span(.deload, "nonsense", nil), span(.deload, today0, "nonsense")])
        XCTAssertEqual(all.items.map(\.kind), [.today])
        XCTAssertEqual(all.rejections, rejections(invalidDay: 5))
    }

    func testInvalidTodayGivesAnEmptyList() {
        for bad in nonCanonicalDays {
            let result = build(
                phases: [phase("2031-01-06", target: .nan)],
                checkpoints: [checkpoint("2031-03-19", .weightWaypoint, waypoint: 96)],
                scanDays: ["2031-01-08", "nonsense"],
                spans: [span(.deload, "2031-02-17", "2031-02-10")],
                projection: projected("2031-05-27"), today: bad)
            XCTAssertTrue(result.invalidToday, bad)
            XCTAssertEqual(result.items, [], bad)
            XCTAssertNil(result.todayIndex, bad)
            XCTAssertEqual(result.scans, .on, bad)
            XCTAssertEqual(result.events, .on, bad)
            // SPEC-AMBIGUITY: nothing was judged, so nothing is counted (see the header).
            XCTAssertEqual(result.rejections, rejections(), bad)
        }
        // The first and last canonical days are valid values of today.
        for edge in ["0001-01-01", "9999-12-31"] {
            let result = build(today: edge)
            XCTAssertFalse(result.invalidToday)
            XCTAssertEqual(result.items.map(\.day), [edge])
            XCTAssertEqual(result.todayIndex, 0)
        }
    }

    // MARK: - Fixture

    private func fixture(today: String, p0Target: Double? = 94.0, events: TimelineSourceState = .on,
                         projection: TimelineProjection? = projected("2031-05-27"))
        -> CheckpointTimelineResult {
        build(
            phases: [phase("2031-01-06", cut: true, target: p0Target),
                     phase("2031-06-16", cut: false, target: nil)],
            checkpoints: [
                checkpoint("2031-03-19", .weightWaypoint, approximate: true, waypoint: 96.0),   // C1
                checkpoint("2031-02-10", .bloodPanel, done: true),                               // C2
                checkpoint("2031-03-17", .scan),                                                 // C3
                checkpoint("2031-02-05", .benchmark),                                            // C4
                checkpoint("2031-06-02", .targetDate, phaseStart: "2031-01-06"),                 // C5
            ],
            scanDays: ["2031-01-08", "2031-03-17"],
            spans: [span(.deload, "2031-02-17", "2031-02-23"), span(.dietBreak, "2031-03-24", nil)],
            projection: projection, scans: .on, events: events, today: today)
    }

    private let fixtureFirstList = [
        "phaseStart 2031-01-06 past #0",
        "scan 2031-01-08 past #0",
        "checkpoint 2031-02-05 current #3",
        "today 2031-02-05 current #-",
        "checkpoint 2031-02-10 upcoming #1",
        "deload 2031-02-17 upcoming #0",
        "checkpoint 2031-03-17 upcoming #2",
        "checkpoint 2031-03-19 upcoming #0",
        "dietBreak 2031-03-24 upcoming #1",
        "projection 2031-05-27 upcoming #-",
        "checkpoint 2031-06-02 upcoming #4",
        "phaseStart 2031-06-16 upcoming #1",
    ]

    func testFixtureTimelineGivesTheExpectedList() {
        // Today 2031-02-05.
        let first = fixture(today: "2031-02-05")
        XCTAssertEqual(lines(first), fixtureFirstList)
        XCTAssertEqual(first.todayIndex, 3)
        XCTAssertEqual(first.rejections, rejections(futureScan: 1))
        XCTAssertFalse(first.invalidToday)
        XCTAssertEqual(first.scans, .on)
        XCTAssertEqual(first.events, .on)
        assertWellFormed(first)
        XCTAssertEqual(at(first.items, 0)?.targetWeightKg, 94.0)
        XCTAssertEqual(at(first.items, 0)?.phaseIsCut, true)
        XCTAssertEqual(at(first.items, 4)?.isDone, true)                       // C2
        XCTAssertEqual(at(first.items, 4)?.category, .bloodPanel)
        XCTAssertEqual(at(first.items, 5)?.endDay, "2031-02-23")               // the deload
        XCTAssertEqual(at(first.items, 5)?.isOpenEnded, false)
        XCTAssertEqual(at(first.items, 6)?.category, .scan)                    // C3 stays
        XCTAssertEqual(at(first.items, 7)?.category, .weightWaypoint)          // C1
        XCTAssertEqual(at(first.items, 7)?.isApproximate, true)
        XCTAssertEqual(at(first.items, 7)?.waypointWeightKg, 96.0)
        XCTAssertNil(at(first.items, 7)?.targetWeightKg)
        XCTAssertNil(at(first.items, 8)?.endDay)                               // the diet break
        XCTAssertEqual(at(first.items, 8)?.isOpenEnded, true)
        XCTAssertEqual(at(first.items, 9)?.isEstimate, true)
        XCTAssertEqual(first.items.filter(\.isEstimate).count, 1)
        XCTAssertEqual(at(first.items, 10)?.category, .targetDate)             // C5
        XCTAssertEqual(at(first.items, 10)?.phaseIndex, 0)
        XCTAssertNil(at(first.items, 10)?.targetWeightKg)
        XCTAssertNil(at(first.items, 10)?.waypointWeightKg)
        XCTAssertNil(at(first.items, 11)?.targetWeightKg)                      // P1 has no target
        XCTAssertEqual(at(first.items, 11)?.phaseIsCut, false)

        // Today 2031-03-24: the second scan is recorded, so the planned one (C3) gives way.
        let second = fixture(today: "2031-03-24")
        XCTAssertEqual(lines(second), [
            "phaseStart 2031-01-06 past #0",
            "scan 2031-01-08 past #0",
            "checkpoint 2031-02-05 past #3",
            "checkpoint 2031-02-10 past #1",
            "deload 2031-02-17 past #0",
            "scan 2031-03-17 past #1",
            "checkpoint 2031-03-19 past #0",
            "dietBreak 2031-03-24 current #1",
            "today 2031-03-24 current #-",
            "projection 2031-05-27 upcoming #-",
            "checkpoint 2031-06-02 upcoming #4",
            "phaseStart 2031-06-16 upcoming #1",
        ])
        XCTAssertEqual(second.todayIndex, 8)
        XCTAssertEqual(second.rejections, rejections(duplicate: 1))
        XCTAssertEqual(at(second.items, 7)?.isOpenEnded, true)
        assertWellFormed(second)

        // Today 2031-02-20, events off, no projection.
        let third = fixture(today: "2031-02-20", events: .off, projection: nil)
        XCTAssertEqual(lines(third), [
            "phaseStart 2031-01-06 past #0",
            "scan 2031-01-08 past #0",
            "checkpoint 2031-02-05 past #3",
            "checkpoint 2031-02-10 past #1",
            "today 2031-02-20 current #-",
            "checkpoint 2031-03-17 upcoming #2",
            "checkpoint 2031-03-19 upcoming #0",
            "checkpoint 2031-06-02 upcoming #4",
            "phaseStart 2031-06-16 upcoming #1",
        ])
        XCTAssertEqual(third.todayIndex, 4)
        XCTAssertEqual(third.events, .off)
        XCTAssertEqual(third.scans, .on)
        XCTAssertEqual(third.rejections, rejections(futureScan: 1))
        assertWellFormed(third)
        // With events on at that date the deload is in progress.
        let during = fixture(today: "2031-02-20", projection: nil)
        XCTAssertEqual(items(during, .deload).map(\.position), [.current])
        XCTAssertEqual(Array(lines(during).dropFirst(4).prefix(2)),
                       ["deload 2031-02-17 current #0", "today 2031-02-20 current #-"])

        // Changed-target variant: the phase target has overtaken the waypoint.
        let overtaken = fixture(today: "2031-02-05", p0Target: 96.0)
        XCTAssertEqual(lines(overtaken), fixtureFirstList)
        XCTAssertEqual(at(overtaken.items, 0)?.targetWeightKg, 96.0)
        XCTAssertEqual(at(overtaken.items, 7)?.category, .weightWaypoint)
        XCTAssertNil(at(overtaken.items, 7)?.waypointWeightKg)
        XCTAssertEqual(at(overtaken.items, 7)?.isApproximate, true)
        XCTAssertEqual(overtaken.rejections, rejections(futureScan: 1, waypointBeyondTarget: 1))
        XCTAssertEqual(at(overtaken.items, 10)?.phaseIndex, 0)
        // One step short of the waypoint: it keeps its weight.
        let short = fixture(today: "2031-02-05", p0Target: 95.9)
        XCTAssertEqual(lines(short), fixtureFirstList)
        XCTAssertEqual(at(short.items, 0)?.targetWeightKg, 95.9)
        XCTAssertEqual(at(short.items, 7)?.waypointWeightKg, 96.0)
        XCTAssertEqual(short.rejections, rejections(futureScan: 1))
    }

    // MARK: - Shape and determinism

    func testInputsAndItemsCarryNoNameNoteOrOtherText() {
        // The timeline's pure layer sees days, kinds and numbers only: no title, note or label can
        // reach an item, so a private event's name cannot either. Private events themselves are
        // removed before this function, by the event adapter in the app target (§8.4).
        func labels(_ value: Any) -> [String] { Mirror(reflecting: value).children.compactMap(\.label) }
        XCTAssertEqual(labels(span(.deload, today0, nil)), ["kind", "startDay", "endDay"])
        XCTAssertEqual(labels(checkpoint(today0)),
                       ["day", "isApproximate", "category", "waypointWeightKg", "phaseStartDay", "isDone"])
        XCTAssertEqual(labels(phase(today0)), ["startDay", "isCut", "targetWeightKg"])
        guard let item = build().items.first else { return XCTFail("no today item") }
        XCTAssertEqual(labels(item), [
            "kind", "day", "endDay", "isOpenEnded", "position", "sourceIndex", "isApproximate", "isDone",
            "isEstimate", "category", "targetWeightKg", "waypointWeightKg", "phaseIndex", "phaseIsCut",
        ])
        // The only strings on an item are day keys.
        let result = fixture(today: "2031-03-24")
        for item in result.items {
            XCTAssertNotNil(canonicalNumber(item.day), line(item))
            if let end = item.endDay { XCTAssertNotNil(canonicalNumber(end), line(item)) }
        }
    }

    func testSameInputSameOutput() {
        for today in ["2031-02-05", "2031-03-24", "2031-02-20", "nonsense"] {
            let first = fixture(today: today)
            for _ in 0 ..< 3 { XCTAssertEqual(fixture(today: today), first) }
            _ = build(checkpoints: [checkpoint(today0)], scanDays: [today0])
            XCTAssertEqual(fixture(today: today), first)
        }
    }

    // MARK: - Properties over generated inputs

    /// A 64-bit linear congruential generator (Knuth's MMIX constants) with a fixed seed. Nothing here
    /// draws randomness from the system, so every run sees the same inputs.
    private struct Generator {
        var state: UInt64
        /// A value in `0 ..< bound`.
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33) % bound
        }
        mutating func shuffled<T>(_ values: [T]) -> [T] {
            var out = values
            for i in stride(from: out.count - 1, to: 0, by: -1) { out.swapAt(i, next(i + 1)) }
            return out
        }
    }

    func testGeneratedInputsKeepTheListInvariants() {
        var generator = Generator(state: 0x71_3E11_4E)
        let base = "2031-01-06"
        let states: [TimelineSourceState] = [.notBuilt, .off, .on, .on]
        var scanItems = 0, spanItems = 0, projections = 0
        for index in 0 ..< 200 {
            let label = "case \(index)"
            let today = day(base, 30 + generator.next(90))
            // Distinct phase start days, so that the governing phase does not depend on input order.
            let phases = (0 ..< generator.next(4)).map { i in
                phase(day(base, i * 40 + generator.next(30)), cut: generator.next(2) == 0,
                      target: generator.next(3) == 0 ? nil : Double(85 + generator.next(15)))
            }
            // No target dates attached to a phase: which of two is kept depends on input order.
            let categories: [TimelineCheckpointCategory] = [.scan, .bloodPanel, .benchmark,
                                                            .weightWaypoint, .appointment, .other]
            let checkpoints = (0 ..< generator.next(7)).map { _ in
                checkpoint(day(base, generator.next(150)), categories[generator.next(categories.count)],
                           approximate: generator.next(2) == 0,
                           waypoint: generator.next(2) == 0 ? nil : Double(85 + generator.next(15)),
                           done: generator.next(2) == 0)
            }
            let scanDays = (0 ..< generator.next(5)).map { _ in day(base, generator.next(150)) }
            let spans = (0 ..< generator.next(4)).map { _ -> TimelineSpan in
                let start = day(base, generator.next(150))
                let end: String? = generator.next(3) == 0 ? nil : day(start, generator.next(21))
                return span(generator.next(2) == 0 ? .deload : .dietBreak, start, end)
            }
            let statuses: [CutScorecardProjectionStatus] = [.projected, .projected, .rateUnknown, .noTarget]
            let projection: TimelineProjection? = generator.next(4) == 0 ? nil
                : TimelineProjection(status: statuses[generator.next(statuses.count)],
                                     targetDay: day(base, generator.next(200)))
            let scans = states[generator.next(states.count)]
            let events = states[generator.next(states.count)]
            let result = build(phases: phases, checkpoints: checkpoints, scanDays: scanDays,
                               spans: spans, projection: projection, scans: scans, events: events,
                               today: today)
            assertWellFormed(result)
            XCTAssertEqual(result.scans, scans, label)
            XCTAssertEqual(result.events, events, label)
            XCTAssertEqual(result.rejections.invalidDay, 0, label)
            XCTAssertEqual(result.rejections.endBeforeStart, 0, label)

            for item in result.items {
                // Every item points back at the entry it was built from.
                switch item.kind {
                case .phaseStart:
                    XCTAssertEqual(at(phases, item.sourceIndex)?.startDay, item.day, label)
                    XCTAssertEqual(at(phases, item.sourceIndex)?.isCut, item.phaseIsCut, label)
                    XCTAssertEqual(at(phases, item.sourceIndex)?.targetWeightKg,
                                   item.targetWeightKg, label)
                case .scan:
                    scanItems += 1
                    XCTAssertEqual(scans, .on, label)
                    XCTAssertEqual(item.sourceIndex, scanDays.firstIndex(of: item.day), label)
                    XCTAssertLessThanOrEqual(item.day, today, label)
                case .checkpoint:
                    XCTAssertEqual(at(checkpoints, item.sourceIndex)?.day, item.day, label)
                    XCTAssertEqual(at(checkpoints, item.sourceIndex)?.category, item.category, label)
                    XCTAssertEqual(at(checkpoints, item.sourceIndex)?.isDone, item.isDone, label)
                    if let weight = item.waypointWeightKg {
                        XCTAssertEqual(item.category, .weightWaypoint, label)
                        XCTAssertEqual(at(checkpoints, item.sourceIndex)?.waypointWeightKg,
                                       weight, label)
                        XCTAssertNil(CheckpointTimeline.waypointIssue(weightKg: weight, on: item.day,
                                                                      phases: phases), label)
                    }
                case .dietBreak, .deload:
                    spanItems += 1
                    XCTAssertEqual(events, .on, label)
                    XCTAssertEqual(at(spans, item.sourceIndex)?.startDay, item.day, label)
                    XCTAssertEqual(at(spans, item.sourceIndex)?.endDay, item.endDay, label)
                    XCTAssertEqual(at(spans, item.sourceIndex).map { $0.kind == .deload },
                                   item.kind == .deload, label)
                    XCTAssertEqual(item.isOpenEnded, item.endDay == nil, label)
                case .today:
                    XCTAssertEqual(item.day, today, label)
                    XCTAssertNil(item.sourceIndex, label)
                case .projection:
                    projections += 1
                    XCTAssertEqual(projection?.status, .projected, label)
                    XCTAssertEqual(item.day, projection?.targetDay, label)
                    XCTAssertNil(item.sourceIndex, label)
                }
                XCTAssertEqual(item.isEstimate, item.kind == .projection, label)
                if item.kind != .phaseStart { XCTAssertNil(item.targetWeightKg, label) }
                // Position follows from the days alone.
                let expected: TimelinePosition
                if item.kind == .dietBreak || item.kind == .deload {
                    if item.day > today { expected = .upcoming }
                    else if let end = item.endDay, end < today { expected = .past }
                    else { expected = .current }
                } else {
                    expected = item.day < today ? .past : (item.day == today ? .current : .upcoming)
                }
                XCTAssertEqual(item.position, expected, label)
            }
            // Counts: every phase is listed; no source that is not on contributes.
            XCTAssertEqual(items(result, .phaseStart).count, phases.count, label)
            if scans != .on { XCTAssertEqual(items(result, .scan).count, 0, label) }
            if events != .on {
                XCTAssertEqual(items(result, .dietBreak).count + items(result, .deload).count, 0, label)
            } else {
                XCTAssertEqual(items(result, .dietBreak).count + items(result, .deload).count,
                               spans.count, label)
            }
            // Every checkpoint is either listed or counted as a planned scan that gave way.
            let plannedGaveWay = scans == .on
                ? checkpoints.filter { c in c.category == .scan && c.day <= today && scanDays.contains(c.day) }.count
                : 0
            XCTAssertEqual(items(result, .checkpoint).count, checkpoints.count - plannedGaveWay, label)

            // The order the entries arrive in changes source indexes but not the list of kinds, days
            // and positions, nor the counters.
            let again = build(phases: generator.shuffled(phases),
                              checkpoints: generator.shuffled(checkpoints),
                              scanDays: generator.shuffled(scanDays), spans: generator.shuffled(spans),
                              projection: projection, scans: scans, events: events, today: today)
            // Compared as sorted lists: two spans of one kind starting on one day are ordered by their
            // source index, which a shuffle changes. The order itself is checked by assertWellFormed.
            func shape(_ r: CheckpointTimelineResult) -> [String] {
                r.items.map { "\($0.kind.rawValue) \($0.day) \($0.endDay ?? "-") \($0.position.rawValue)" }
                    .sorted()
            }
            assertWellFormed(again)
            XCTAssertEqual(shape(again), shape(result), label)
            XCTAssertEqual(again.rejections, result.rejections, label)
            XCTAssertEqual(again.todayIndex, result.todayIndex, label)
        }
        // The generator must reach each kind for the properties above to mean anything.
        XCTAssertGreaterThan(scanItems, 50)
        XCTAssertGreaterThan(spanItems, 50)
        XCTAssertGreaterThan(projections, 30)
    }
}
