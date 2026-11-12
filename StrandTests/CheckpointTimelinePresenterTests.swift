// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §7.3, §8.1, §10.1, §10.8, §11, §12.3 and §13.4
// before the implementation exists. The full API block (`CheckpointTimelinePresenter`,
// `CheckpointTimelinePresentation`, `TimelineRow`, `TimelineRowDestination`, `TimelineFootnote`) is at
// the top of Stage6TestSupport.swift. Results come from the merged `CheckpointTimeline.build` over the
// §13.4 inputs; weights are worded by the existing `CutScorecardPresenter.Wording`.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `rows` holds one row per built item, in the built order, and nothing else (§7.3, "This list is
//     the only one"); headings are the view's, from `position`.
//  2. A row's owner text (a checkpoint title, a phase name) is in `title` or `details`; its category
//     word, "Done", "Not marked done", "now" and "estimate" are in `details` or `tags`. The tests read
//     a row's strings as a set and do not depend on which of the two fields holds a word.
//  3. "Target <weight>" and "Waypoint <weight>" use `Wording(unitSystem:locale:).weight(_:)`.
//  4. `offersSetUpPhase` is true only when no phase is stored and the scorecard is on (§10.8).
//  5. Destinations: phase start → the phase sheet of that stored index; checkpoint → its sheet; scan
//     → `RedesignRoute.bodyRecord`; break or deload → `RedesignRoute.personalEvents` for that event;
//     projection → the scorecard; today → none.
//
// Not pinnable here: Loading (skeleton rows), the largest text size and Reduce Motion are view
// behaviour.
//
// Synthetic values only (§13.4).

import XCTest
import StrandAnalytics
@testable import Strand

final class CheckpointTimelinePresenterTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let gb = Stage6Fixture.british

    private func present(_ result: CheckpointTimelineResult, phases: [CutScorecardStoredPhase] = Fx.phases,
                         checkpoints: [StoredCheckpoint] = Fx.checkpoints, events: [PersonalEvent] = [Fx.e1, Fx.e3],
                         scorecardEnabled: Bool = true, phasesNeedAttention: Bool = false,
                         checkpointsNeedAttention: Bool = false,
                         unitSystem: UnitSystem = .metric) -> CheckpointTimelinePresentation {
        CheckpointTimelinePresenter.present(result, phases: phases, checkpoints: checkpoints, events: events,
                                            scorecardEnabled: scorecardEnabled, phasesNeedAttention: phasesNeedAttention,
                                            checkpointsNeedAttention: checkpointsNeedAttention, unitSystem: unitSystem,
                                            locale: gb)
    }

    private func words(_ row: TimelineRow) -> [String] { [row.title, row.dateText] + row.details + row.tags }
    private func text(_ row: TimelineRow) -> String { words(row).joined(separator: "\n") }

    private func row(_ p: CheckpointTimelinePresentation, _ kind: TimelineItemKind, day: String,
                     file: StaticString = #filePath, line: UInt = #line) -> TimelineRow? {
        let found = p.rows.first { $0.kind == kind && $0.day == day }
        if found == nil { XCTFail("no \(kind) row on \(day): \(p.rows.map { "\($0.kind) \($0.day)" })", file: file, line: line) }
        return found
    }

    private func weight(_ kg: Double, _ system: UnitSystem = .metric) -> String {
        CutScorecardPresenter.Wording(unitSystem: system, locale: gb).weight(kg)
    }

    // MARK: The single list

    func testViewRowsAreExactlyTheBuiltItemsInOrder() {
        for today in ["2031-02-05", "2031-03-24", "2031-02-20"] {
            let result = Fx.build(today: today)
            let p = present(result)
            XCTAssertEqual(p.rows.map(\.kind), result.items.map(\.kind), today)
            XCTAssertEqual(p.rows.map(\.day), result.items.map(\.day), today)
            XCTAssertEqual(p.rows.map(\.position), result.items.map(\.position), today)
            XCTAssertEqual(p.todayRowIndex, result.todayIndex, today)
        }
        let first = present(Fx.build(today: "2031-02-05"))
        XCTAssertEqual(first.rows.map(\.kind), [.phaseStart, .scan, .checkpoint, .today, .checkpoint, .deload, .checkpoint,
                                                .checkpoint, .dietBreak, .projection, .checkpoint, .phaseStart])
    }

    // MARK: §10.8 rows

    func testPhaseStartRow() throws {
        let p = present(Fx.build(today: "2031-02-05"))
        let started = try XCTUnwrap(row(p, .phaseStart, day: "2031-01-06"))
        XCTAssertTrue(text(started).contains("Fixture cut"), text(started))
        XCTAssertTrue(text(started).contains("started"), text(started))
        XCTAssertTrue(words(started).contains("Target \(weight(94))"), text(started))
        XCTAssertEqual(started.destination, .phaseSheet(phaseIndex: 0))
        let upcoming = try XCTUnwrap(row(p, .phaseStart, day: "2031-06-16"))
        XCTAssertTrue(text(upcoming).contains("Fixture hold") && text(upcoming).contains("starts"), text(upcoming))
        XCTAssertFalse(text(upcoming).contains("Target"), "a phase with no target shows none")
        XCTAssertEqual(upcoming.destination, .phaseSheet(phaseIndex: 1))
    }

    func testTargetWeightUsesTheScorecardsWording() throws {
        let p = present(Fx.build(today: "2031-02-05"), unitSystem: .imperial)
        let phase = try XCTUnwrap(row(p, .phaseStart, day: "2031-01-06"))
        XCTAssertTrue(words(phase).contains("Target \(weight(94, .imperial))"), text(phase))
        let target = try XCTUnwrap(row(p, .checkpoint, day: "2031-06-02"))
        XCTAssertTrue(words(target).contains("Target \(weight(94, .imperial))"), text(target))
        let waypoint = try XCTUnwrap(row(p, .checkpoint, day: "2031-03-19"))
        XCTAssertTrue(words(waypoint).contains("Waypoint \(weight(96, .imperial))"), text(waypoint))
    }

    func testCheckpointUpcomingRow() throws {
        let p = present(Fx.build(today: "2031-02-05"))
        let panel = try XCTUnwrap(row(p, .checkpoint, day: "2031-02-10"))
        XCTAssertTrue(text(panel).contains("Fixture panel"))
        XCTAssertTrue(words(panel).contains("Blood panel"), text(panel))
        XCTAssertEqual(panel.destination, .checkpointSheet(checkpointId: Fx.c2.id))
        XCTAssertFalse(words(panel).contains("Not marked done"))
        let waypoint = try XCTUnwrap(row(p, .checkpoint, day: "2031-03-19"))
        XCTAssertTrue(waypoint.dateText.hasPrefix("around "), "approximate: \(waypoint.dateText)")
        XCTAssertFalse(panel.dateText.hasPrefix("around "))
    }

    func testCheckpointPastDoneAndNotDone() throws {
        let p = present(Fx.build(today: "2031-03-24"))
        let done = try XCTUnwrap(row(p, .checkpoint, day: "2031-02-10"))
        XCTAssertEqual(done.position, .past)
        XCTAssertTrue(words(done).contains("Done"), text(done))
        let notDone = try XCTUnwrap(row(p, .checkpoint, day: "2031-03-19"))
        XCTAssertTrue(words(notDone).contains("Not marked done"), text(notDone))
    }

    func testPastCheckpointNotDoneHasNoOverdueWording() throws {
        let p = present(Fx.build(today: "2031-03-24"))
        for row in p.rows {
            for word in ["overdue", "late", "missed", "behind", "failed"] {
                XCTAssertFalse(Stage6Text.containsWord(text(row), word), "\(word) in \(text(row))")
            }
        }
        for note in p.footnotes { XCTAssertFalse(Stage6Text.containsWord(note.text, "overdue")) }
    }

    func testWeightWaypointRow() throws {
        let p = present(Fx.build(today: "2031-02-05"))
        let waypoint = try XCTUnwrap(row(p, .checkpoint, day: "2031-03-19"))
        XCTAssertTrue(words(waypoint).contains("Waypoint \(weight(96))"), text(waypoint))
        XCTAssertTrue(text(waypoint).contains("Fixture waypoint"))
        XCTAssertEqual(p.footnotes, [], "both sources on, nothing hidden")
    }

    func testWaypointRowIsNeverWordedAsATarget() throws {
        for today in ["2031-02-05", "2031-03-24"] {
            let p = present(Fx.build(today: today))
            let waypoint = try XCTUnwrap(row(p, .checkpoint, day: "2031-03-19"))
            XCTAssertNil(text(waypoint).range(of: "target", options: .caseInsensitive), text(waypoint))
        }
    }

    func testWaypointPastTheTargetShowsTheRowWithoutWeightAndOneFootnote() throws {
        var overtaken = Fx.p0
        overtaken.targetWeightKg = 96.0
        let phases = [overtaken, Fx.p1]
        let result = Fx.build(today: "2031-02-05", phases: phases)
        XCTAssertEqual(result.rejections.waypointBeyondTarget, 1)
        let p = present(result, phases: phases)
        let waypoint = try XCTUnwrap(row(p, .checkpoint, day: "2031-03-19"))
        XCTAssertTrue(text(waypoint).contains("Fixture waypoint"), "the row stays")
        XCTAssertFalse(text(waypoint).contains("Waypoint"), "without its weight: \(text(waypoint))")
        XCTAssertFalse(text(waypoint).contains("kg"))
        XCTAssertEqual(p.footnotes.filter { $0.text == "A waypoint at or past your target weight is not shown" }.count, 1)
        // 95.9 keeps the weight and needs no footnote.
        var short = Fx.p0
        short.targetWeightKg = 95.9
        let kept = present(Fx.build(today: "2031-02-05", phases: [short, Fx.p1]), phases: [short, Fx.p1])
        XCTAssertTrue(words(try XCTUnwrap(row(kept, .checkpoint, day: "2031-03-19"))).contains("Waypoint \(weight(96))"))
        XCTAssertEqual(kept.footnotes, [])
    }

    func testTargetDateRowShowsThePhasesStoredTargetWeight() throws {
        let p = present(Fx.build(today: "2031-02-05"))
        let target = try XCTUnwrap(row(p, .checkpoint, day: "2031-06-02"))
        XCTAssertTrue(text(target).contains("Target date for Fixture cut"), text(target))
        XCTAssertTrue(words(target).contains("Target \(weight(94))"), text(target))
        XCTAssertEqual(target.destination, .checkpointSheet(checkpointId: Fx.c5.id))
        XCTAssertEqual(target.weightDestination, .phaseSheet(phaseIndex: 0))

        var changed = Fx.p0
        changed.targetWeightKg = 95.5
        let follows = present(Fx.build(today: "2031-02-05", phases: [changed, Fx.p1]), phases: [changed, Fx.p1])
        let row = try XCTUnwrap(self.row(follows, .checkpoint, day: "2031-06-02"))
        XCTAssertTrue(words(row).contains("Target \(weight(95.5))"), text(row))
        XCTAssertFalse(text(row).contains(weight(94)))
    }

    func testTargetDateRowWithoutItsPhaseShowsNoWeight() throws {
        let result = Fx.build(today: "2031-02-05", phases: [Fx.p1])
        let p = present(result, phases: [Fx.p1])
        let target = try XCTUnwrap(row(p, .checkpoint, day: "2031-06-02"))
        XCTAssertTrue(words(target).contains("Target date"), text(target))
        XCTAssertTrue(text(target).contains("Fixture target date"), text(target))
        XCTAssertFalse(text(target).contains("Fixture cut"))
        XCTAssertFalse(text(target).contains("kg"), "no weight without a phase")
        XCTAssertNil(target.weightDestination)
    }

    func testScanItemOpensTheBodyRecordRoute() throws {
        let p = present(Fx.build(today: "2031-02-05"))
        let scan = try XCTUnwrap(row(p, .scan, day: "2031-01-08"))
        XCTAssertEqual(scan.title, "Scan")
        XCTAssertEqual(scan.destination, .bodyRecord)
        XCTAssertTrue(scan.dateText.contains("8") && scan.dateText.contains("Jan"), scan.dateText)
    }

    func testSpanItemOpensTheEventsRoute() throws {
        let p = present(Fx.build(today: "2031-02-05"))
        let deload = try XCTUnwrap(row(p, .deload, day: "2031-02-17"))
        XCTAssertEqual(deload.title, "Deload")
        XCTAssertEqual(deload.destination, .personalEvents(eventId: Fx.e1.id))
        let dietBreak = try XCTUnwrap(row(p, .dietBreak, day: "2031-03-24"))
        XCTAssertEqual(dietBreak.title, "Diet break")
        XCTAssertEqual(dietBreak.destination, .personalEvents(eventId: Fx.e3.id))
    }

    func testSpanRowsPastCurrentAndOpenEnded() throws {
        let past = try XCTUnwrap(row(present(Fx.build(today: "2031-03-24")), .deload, day: "2031-02-17"))
        XCTAssertEqual(past.position, .past)
        XCTAssertTrue(past.dateText.contains(" to "), past.dateText)
        XCTAssertTrue(past.dateText.contains("17") && past.dateText.contains("23"), past.dateText)
        XCTAssertFalse(past.tags.contains("now"))

        let running = try XCTUnwrap(row(present(Fx.build(today: "2031-02-20")), .deload, day: "2031-02-17"))
        XCTAssertEqual(running.position, .current)
        XCTAssertTrue(running.tags.contains("now"), "\(running.tags)")

        let p = present(Fx.build(today: "2031-03-24"))
        let open = try XCTUnwrap(row(p, .dietBreak, day: "2031-03-24"))
        XCTAssertTrue(open.dateText.hasPrefix("Since "), open.dateText)
        XCTAssertTrue(open.tags.contains("now"))
        let openIndex = try XCTUnwrap(p.rows.firstIndex { $0.kind == .dietBreak })
        XCTAssertLessThan(openIndex, try XCTUnwrap(p.todayRowIndex), "placed before the today marker")
    }

    func testSpanRowShowsKindAndDatesOnly() throws {
        let labelled = PersonalEvent(id: Fx.e1.id, kind: .deload, label: "Fixture label secret", startDay: Fx.e1.startDay,
                                     endDay: Fx.e1.endDay, note: "Fixture note secret", sensitive: false, createdAt: 1)
        let p = present(Fx.build(today: "2031-02-20", events: [labelled]), events: [labelled])
        let deload = try XCTUnwrap(row(p, .deload, day: "2031-02-17"))
        for needle in ["Fixture label secret", "Fixture note secret"] {
            XCTAssertFalse(Stage6Text.joined(p).contains(needle), needle)
        }
        let allowed = Set(["Deload", "now", deload.dateText])
        for word in words(deload) where !word.isEmpty {
            XCTAssertTrue(allowed.contains(word), "a span row shows kind and dates only, found: \(word)")
        }
    }

    func testProjectionRow() throws {
        let p = present(Fx.build(today: "2031-02-05"))
        let projection = try XCTUnwrap(row(p, .projection, day: "2031-05-27"))
        XCTAssertTrue(text(projection).contains("Estimated"), text(projection))
        XCTAssertTrue(text(projection).contains("at this rate"), text(projection))
        XCTAssertTrue(projection.tags.contains("estimate"), "\(projection.tags)")
        XCTAssertTrue(text(projection).contains(weight(94)), "the phase's target weight")
        XCTAssertEqual(projection.destination, .scorecard)
        XCTAssertEqual(p.rows.last?.kind, .phaseStart, "P1 starts after the estimate")
    }

    func testNoProjectionMeansNoItemAndNothingSaid() {
        let p = present(Fx.build(today: "2031-02-05", projection: nil))
        XCTAssertFalse(p.rows.contains { $0.kind == .projection })
        XCTAssertEqual(p.footnotes, [], "the scorecard explains why")
        let notProjected = present(Fx.build(today: "2031-02-05",
                                            projection: TimelineProjection(status: .rateUnknown, targetDay: nil)))
        XCTAssertFalse(notProjected.rows.contains { $0.kind == .projection })
        XCTAssertEqual(notProjected.footnotes, [])
    }

    func testNothingButToday() {
        let empty = CheckpointTimeline.build(CheckpointTimelineInput(
            phases: [], checkpoints: [], scanDays: [], spans: [], projection: nil, scans: .on, events: .on,
            today: "2031-02-05"))
        let p = present(empty, phases: [], checkpoints: [], events: [])
        XCTAssertEqual(p.rows.map(\.kind), [.today])
        XCTAssertEqual(p.emptyText, "Nothing on your timeline yet")
        XCTAssertTrue(Stage6Text.strings(in: p).contains("Add a checkpoint"))
        XCTAssertTrue(p.offersSetUpPhase)
        XCTAssertFalse(present(empty, phases: [], checkpoints: [], events: [], scorecardEnabled: false).offersSetUpPhase)
        XCTAssertNil(present(Fx.build(today: "2031-02-05")).emptyText)
    }

    func testScanSourceNotBuiltShowsNoFootnote() {
        let p = present(Fx.build(today: "2031-02-05", scans: .notBuilt))
        XCTAssertFalse(p.rows.contains { $0.kind == .scan })
        XCTAssertEqual(p.footnotes, [])
    }

    func testScanSourceOffShowsTheFootnote() {
        let p = present(Fx.build(today: "2031-02-05", scans: .off))
        XCTAssertFalse(p.rows.contains { $0.kind == .scan })
        XCTAssertEqual(p.footnotes.map(\.text), ["Scans are not shown while the body record is off"])
    }

    func testEventSourceNotBuiltShowsNoFootnote() {
        let p = present(Fx.build(today: "2031-02-05", eventsState: .notBuilt))
        XCTAssertFalse(p.rows.contains { $0.kind == .deload || $0.kind == .dietBreak })
        XCTAssertEqual(p.footnotes, [])
    }

    func testEventSourceOffShowsTheFootnote() {
        let p = present(Fx.build(today: "2031-02-05", eventsState: .off))
        XCTAssertFalse(p.rows.contains { $0.kind == .deload || $0.kind == .dietBreak })
        XCTAssertEqual(p.footnotes.map(\.text), ["Breaks and deloads are not shown while events are off"])
    }

    func testScorecardFlagOffKeepsPhasesAndDropsTheEstimate() {
        let p = present(Fx.build(today: "2031-02-05", projection: nil), scorecardEnabled: false)
        XCTAssertEqual(p.rows.filter { $0.kind == .phaseStart }.count, 2)
        XCTAssertFalse(p.rows.contains { $0.kind == .projection })
        XCTAssertEqual(p.footnotes.map(\.text), ["No estimate while the scorecard is off"])
    }

    func testCheckpointsNeedAttention() {
        let result = Fx.build(today: "2031-02-05", checkpoints: [])
        let p = present(result, checkpoints: [], checkpointsNeedAttention: true)
        XCTAssertEqual(p.attentionText, "Your checkpoints could not be read. Nothing has been changed.")
        XCTAssertTrue(Stage6Text.strings(in: p).contains("Discard unreadable data"))
        XCTAssertFalse(p.canAdd)
        XCTAssertTrue(p.rows.contains { $0.kind == .phaseStart }, "other items still show")
        XCTAssertTrue(p.rows.contains { $0.kind == .scan })
    }

    func testPhasesNeedAttention() throws {
        let result = Fx.build(today: "2031-02-05", phases: [])
        let p = present(result, phases: [], phasesNeedAttention: true)
        XCTAssertFalse(p.rows.contains { $0.kind == .phaseStart })
        let target = try XCTUnwrap(row(p, .checkpoint, day: "2031-06-02"))
        XCTAssertTrue(words(target).contains("Target date"), text(target))
        XCTAssertFalse(text(target).contains("Fixture cut"))
        XCTAssertEqual(p.footnotes.count, 1, "one footnote, linking to the phase sheet")
        XCTAssertNotNil(p.footnotes.first?.linkTitle)
    }

    func testLimitReached() {
        let many = (0..<200).map { i -> StoredCheckpoint in
            var c = Fx.c4
            c.id = String(format: "c-%08x", i + 0x100)
            return c
        }
        let p = present(Fx.build(today: "2031-02-05", checkpoints: many), checkpoints: many)
        XCTAssertFalse(p.canAdd)
        XCTAssertTrue(p.limitText?.contains("200") == true, "\(String(describing: p.limitText))")
        XCTAssertTrue(present(Fx.build(today: "2031-02-05")).canAdd)
    }

    // MARK: Entry points and wording across every state

    func testHealthRowNextDetailIsADateOnly() throws {
        XCTAssertNil(CheckpointTimelinePresenter.healthRow(enabled: false, result: Fx.build(today: "2031-02-05"), locale: gb))
        let row = try XCTUnwrap(CheckpointTimelinePresenter.healthRow(enabled: true, result: Fx.build(today: "2031-02-05"),
                                                                      locale: gb))
        XCTAssertEqual(row.title, "Timeline")
        let detail = try XCTUnwrap(row.detail)
        XCTAssertTrue(detail.hasPrefix("Next: "), detail)
        XCTAssertTrue(detail.contains("10") && detail.contains("Feb"), "the first upcoming item is C2 on 10 Feb: \(detail)")
        for word in ["Fixture", "kg", "Deload", "Diet break", "Blood panel", "Target", "Waypoint", "Scan"] {
            XCTAssertFalse(detail.contains(word), "\(word) in \(detail)")
        }
        // Nothing upcoming: no detail.
        let past = CheckpointTimeline.build(CheckpointTimelineInput(
            phases: Fx.timelinePhases([Fx.p0]), checkpoints: [], scanDays: [], spans: [], projection: nil, scans: .on,
            events: .on, today: "2031-02-05"))
        XCTAssertNil(CheckpointTimelinePresenter.healthRow(enabled: true, result: past, locale: gb)?.detail)
        // A private event cannot be named: the first upcoming built item is all it reads.
        let withPrivateOnly = Fx.build(today: "2031-04-01", checkpoints: [], scanDays: [], events: [], projection: nil)
        XCTAssertTrue(CheckpointTimelinePresenter.healthRow(enabled: true, result: withPrivateOnly, locale: gb)?.detail?
            .contains("Jun") == true, "P1 on 16 Jun, never the private deload of 7 Apr")
    }

    private func sweep() -> [CheckpointTimelinePresentation] {
        var out: [CheckpointTimelinePresentation] = []
        for today in ["2031-01-01", "2031-02-05", "2031-02-20", "2031-03-24", "2031-07-01"] {
            for scans in [TimelineSourceState.on, .off, .notBuilt] {
                for events in [TimelineSourceState.on, .off, .notBuilt] {
                    for scorecard in [true, false] {
                        let projection = scorecard ? TimelineProjection(status: .projected, targetDay: "2031-05-27") : nil
                        out.append(present(Fx.build(today: today, projection: projection, scans: scans, eventsState: events),
                                           scorecardEnabled: scorecard))
                    }
                }
            }
        }
        return out
    }

    func testNoStringOffersAPhaseForABreakOrDeload() {
        for p in sweep() {
            for text in Stage6Text.strings(in: p) {
                XCTAssertNil(text.range(of: "add a phase", options: .caseInsensitive), text)
                XCTAssertNil(text.range(of: "new phase", options: .caseInsensitive), text)
            }
            for row in p.rows where row.kind == .deload || row.kind == .dietBreak {
                XCTAssertNil(self.text(row).range(of: "phase", options: .caseInsensitive), self.text(row))
            }
        }
    }

    func testNoPrivateEventPlaceholderInAnyState() {
        for p in sweep() {
            let all = Stage6Text.joined(p)
            XCTAssertFalse(all.contains("Private event"))
            XCTAssertFalse(all.lowercased().contains("private"))
        }
    }

    func testEveryEstimateIsLabelledAndNoMissingValueIsZero() {
        for p in sweep() {
            for row in p.rows where row.kind == .projection {
                XCTAssertTrue(row.tags.contains("estimate"))
            }
            for text in Stage6Text.strings(in: p) {
                XCTAssertNil(text.range(of: "(^|[^0-9.,])0([.,]0)? ?(kg|lb)", options: .regularExpression), text)
            }
        }
    }
}
