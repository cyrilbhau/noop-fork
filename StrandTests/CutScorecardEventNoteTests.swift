// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md §10.6, §12.3, §12.4 and §13, and the
// approved frames N1 to N14 of design/round-s5-events, before the implementation exists. Additions
// to Strand/Data/CutScorecardPresenter.swift:
//
//     extension CutScorecardPresentation {
//         struct EventNote: Equatable {
//             var title: String            // "Events this week"
//             var lines: [String]          // events overlapping the judged week, latest start first
//             var earlierTitle: String?    // "Earlier in the weeks behind this verdict"
//             var earlierLines: [String]   // overlapping [evidenceStartDay, judged Sunday], not the judged week
//             var moreText: String?        // "and %lld more"
//             var footnote: String         // "Shown for context. Events do not change the verdict."
//         }
//         var eventNote: EventNote?        // default nil
//     }
//     extension CutScorecardPresentation.Curve { var marked: [Bool] }   // default []
//     extension CutScorecardPresentationContext { var events: [PersonalEvent] }   // default []
//
// Existing, used unchanged: `CutScorecard.evaluate(_:)`, `CutScorecardPresenter.present(_:input:context:)`,
// `CutScorecardResult.judgedWeekStart`, `.evidenceStartDay`, `.weeks`, `.verdict.reason`, and the stage 1
// fixture `ScorecardScreenFixture` of CutScorecardPresenterTests.swift (the one Fixture Person).
//
// Behaviour assumed where the specification leaves it unstated, each from the design model
// (design/round-s5-events/model.js `eventNote`, `scorecardDay`) and its frames:
//
//  1. Both lists are latest start first, each cut at three; `moreText` counts what both cuts hid
//     together ("and 1 more", frame N9).
//  2. With events only in the earlier part of the evidence window the note is present with
//     `lines` empty (frame N3, "earlier section only").
//  3. No note when there is no judged week, and none while the weigh-in is overdue (frame N12:
//     "no note; the curves keep their marks"), although the result still names a judged week then.
//  4. Each line is `PersonalEventPresenter.outsideLine` with the input's `today`: the kind name or
//     "Private event", " · ", the dates (the year only when it is not today's).
//  5. `marked` is computed over the presenter's own weeks (one per curve point); when no shown week
//     is covered it may be all false or empty, so the tests accept either then.

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

final class CutScorecardEventNoteTests: XCTestCase {

    private typealias Fx = PersonalEventAppFixture
    private typealias S1 = ScorecardScreenFixture

    private let footnote = "Shown for context. Events do not change the verdict."
    private let title = "Events this week"
    private let earlierTitle = "Earlier in the weeks behind this verdict"

    // MARK: Helpers

    private func context(_ events: [PersonalEvent]?) -> CutScorecardPresentationContext {
        var context = CutScorecardPresentationContext(unitSystem: .metric, weightSource: .labBook,
                                                      rulesNeedAttention: false, locale: Fx.british)
        if let events { context.events = events }
        return context
    }

    private func present(_ input: CutScorecardInput, _ events: [PersonalEvent]?) -> CutScorecardPresentation {
        CutScorecardPresenter.present(CutScorecard.evaluate(input), input: input, context: context(events))
    }

    private func present(today: String, _ events: [PersonalEvent]?) -> CutScorecardPresentation {
        present(S1.input(today: today), events)
    }

    /// The presentation with this stage's two outputs set back to their defaults.
    private func stripped(_ p: CutScorecardPresentation) -> CutScorecardPresentation {
        var q = p
        q.eventNote = nil
        q.weight?.marked = []
        q.waist?.marked = []
        return q
    }

    /// Every day of the twenty-two fixture weeks, Monday to Sunday.
    private var everyFixtureDay: [String] {
        (0..<(22 * 7)).map { S1.day("2031-01-06", plus: $0) }
    }

    /// The weeks the curves show (the phase's weeks once it has started), from the stage 1 result.
    private func shownWeeks(_ result: CutScorecardResult, _ input: CutScorecardInput) -> [String] {
        let phaseWeek = input.phase.flatMap { CutScorecard.weekStart(containing: $0.startDay) }
        let started = input.phase.map { input.today >= $0.startDay } ?? false
        return result.weeks.map(\.weekStart).filter { week in started ? week >= (phaseWeek ?? week) : true }
    }

    private func expectedMarks(_ events: [PersonalEvent], _ weeks: [String]) -> [Bool] {
        PersonalEvents.coveredSlots(events: events, slots: weeks.map {
            PersonalEventSlot(firstDay: $0, lastDay: S1.day($0, plus: 6))
        })
    }

    private func line(_ event: PersonalEvent) -> String {
        if let fixed = Fx.outsideLine2031[event.id], event == Fx.all.first(where: { $0.id == event.id }) { return fixed }
        return PersonalEventPresenter.outsideLine(for: event, locale: Fx.british)
    }

    // MARK: Flag off and no events (§12.4)

    func testNoEventsLeavesThePresentationEqualToThePresentationWithoutTheContextField() {
        for today in everyFixtureDay + ["2031-06-25", "2030-12-20"] {
            let without = present(today: today, nil)
            let empty = present(today: today, [])
            XCTAssertEqual(empty, without, today)
            XCTAssertNil(without.eventNote, today)
            XCTAssertEqual(without.weight?.marked ?? [], [], today)
            XCTAssertEqual(without.waist?.marked ?? [], [], today)
        }
        XCTAssertTrue(CutScorecardPresentationContext().events.isEmpty, "the context field defaults to no events")
    }

    // MARK: The verdict is untouched (faults F15 and F28)

    func testVerdictRulesSignalsRateProjectionAndCardAreIdenticalWithAndWithoutEventsForAllTwentyTwoFixtureWeeks() {
        let dense = Fx.all + (0..<40).map { index in
            Fx.make(String(format: "%016x", 0x100 + index), index.isMultiple(of: 2) ? .dietBreak : .deload,
                    S1.day("2031-01-06", plus: index * 4), S1.day("2031-01-06", plus: index * 4 + 2),
                    sensitive: index.isMultiple(of: 3), createdAt: 2000 + index)
        }
        for events in [Fx.all, Fx.v9, dense] {
            for today in everyFixtureDay {
                let without = present(today: today, nil)
                let with = present(today: today, events)
                XCTAssertEqual(stripped(with), without, "\(today): only eventNote and marked may differ")
                XCTAssertEqual(with.verdict, without.verdict, today)
                XCTAssertEqual(with.card, without.card, "\(today): the Today card is unchanged")
            }
        }
    }

    func testDietBreakAndDeloadLeaveTheVerdictAndTheActivePhaseUnchanged() {
        // E2 overlaps week 5 (3 to 9 Feb); E3 weeks 15 and 16 (14 to 27 Apr).
        let days = (0..<7).map { S1.day("2031-02-03", plus: $0) } + (0..<14).map { S1.day("2031-04-14", plus: $0) }
        for events in [[Fx.e2, Fx.e3], Fx.v9.filter { $0.id == Fx.id(2) || $0.id == Fx.id(3) }] {
            for today in days {
                let without = present(today: today, nil)
                let with = present(today: today, events)
                XCTAssertEqual(stripped(with), without, today)
                XCTAssertEqual(with.phase, without.phase, "\(today): the phase is the one long block")
                XCTAssertEqual(with.status, without.status, today)
            }
        }
        XCTAssertEqual(present(today: "2031-02-05", [Fx.e2]).eventNote?.lines, ["Deload · 3 – 9 Feb"])
        XCTAssertEqual(present(today: "2031-04-16", [Fx.e3]).eventNote?.lines, ["Diet break · 14 – 27 Apr"])
    }

    // MARK: The note (§10.6), one test per state

    func testJudgedWeekEventAppearsInTheNote() throws {
        let note = try XCTUnwrap(present(today: "2031-02-05", Fx.all).eventNote)
        XCTAssertEqual(note, CutScorecardPresentation.EventNote(
            title: title, lines: ["Deload · 3 – 9 Feb"], earlierTitle: earlierTitle,
            earlierLines: ["Supplement change · 22 Jan"], moreText: nil, footnote: footnote))

        let judged22Jan = try XCTUnwrap(present(today: "2031-01-22", Fx.all).eventNote)
        XCTAssertEqual(judged22Jan.lines, ["Supplement change · 22 Jan"])
        XCTAssertNil(judged22Jan.earlierTitle)
        XCTAssertEqual(judged22Jan.earlierLines, [])
    }

    func testEarlierEvidenceWindowEventAppearsInTheEarlierSection() throws {
        // Only earlier: the judged week (10 to 16 Feb) has no event (frame N3's shape).
        let only = try XCTUnwrap(present(today: "2031-02-12", Fx.all).eventNote)
        XCTAssertEqual(only, CutScorecardPresentation.EventNote(
            title: title, lines: [], earlierTitle: earlierTitle,
            earlierLines: ["Deload · 3 – 9 Feb", "Supplement change · 22 Jan"], moreText: nil, footnote: footnote))

        // 26 March (§13.2): the judged week is week 12; E1 is in the earlier section because the
        // evidence window reaches back past 16 March.
        let input = S1.input(today: "2031-03-26")
        let result = CutScorecard.evaluate(input)
        XCTAssertEqual(result.judgedWeekStart, "2031-03-24")
        let evidence = try XCTUnwrap(result.evidenceStartDay)
        XCTAssertLessThanOrEqual(evidence, "2031-03-16")
        let note = try XCTUnwrap(present(input, Fx.all).eventNote)
        XCTAssertEqual(note.lines, ["Private event · 26 Mar"])
        XCTAssertEqual(note.earlierTitle, earlierTitle)
        let expectedEarlier = PersonalEvents.events(overlapping: evidence, "2031-03-30", in: Fx.all)
            .filter { $0.id != Fx.id(6) }.reversed().prefix(3).map(line)
        XCTAssertEqual(note.earlierLines, Array(expectedEarlier))
        XCTAssertEqual(note.earlierLines, ["Travel · 10 – 16 Mar", "Travel · 22 – 24 Feb"], "the design's golden")
        XCTAssertEqual(note.footnote, footnote)
    }

    func testEveryFixtureDayMatchesTheNoteRule() {
        for today in everyFixtureDay {
            let input = S1.input(today: today)
            let result = CutScorecard.evaluate(input)
            let note = present(input, Fx.all).eventNote
            guard let judged = result.judgedWeekStart, let evidence = result.evidenceStartDay,
                  result.verdict.reason != .noReadings, result.verdict.reason != .weighInOverdue else {
                XCTAssertNil(note, "\(today): no judged week, no note")
                continue
            }
            let sunday = S1.day(judged, plus: 6)
            let inWeek = PersonalEvents.events(overlapping: judged, sunday, in: Fx.all).reversed()
            let earlier = PersonalEvents.events(overlapping: evidence, sunday, in: Fx.all)
                .filter { e in !inWeek.contains { $0.id == e.id } }.reversed()
            if inWeek.isEmpty && earlier.isEmpty {
                XCTAssertNil(note, "\(today): nothing in the window")
                continue
            }
            XCTAssertEqual(note?.lines, inWeek.prefix(3).map(line), today)
            XCTAssertEqual(note?.earlierLines, earlier.prefix(3).map(line), today)
            XCTAssertEqual(note?.earlierTitle, earlier.isEmpty ? nil : earlierTitle, today)
            let hidden = max(0, inWeek.count - 3) + max(0, earlier.count - 3)
            XCTAssertEqual(note?.moreText, hidden == 0 ? nil : "and \(hidden) more", today)
        }
    }

    func testMissedWeekWithAnEventIsMarkedOnBothCurves() throws {
        // Week 10 (10 to 16 March) has no weigh-in and carries the fixture trip.
        for today in ["2031-03-12", "2031-03-19", "2031-03-26"] {
            let p = present(today: today, Fx.all)
            let weight = try XCTUnwrap(p.weight, today)
            let waist = try XCTUnwrap(p.waist, today)
            XCTAssertGreaterThan(weight.points.count, 9, today)
            XCTAssertNil(weight.points[9], "\(today): week 10 is the missed week")
            XCTAssertEqual(weight.marked[safe: 9], true, "\(today): the weight curve marks week 10")
            XCTAssertEqual(waist.marked[safe: 9], true, "\(today): the waist curve marks week 10")
        }
        // The gap explains itself even before week 10 is judged.
        XCTAssertEqual(present(today: "2031-03-12", Fx.all).weight?.marked,
                       [false, false, true, false, true, false, true, true, false, true])
    }

    func testSensitiveEventIsWordedPrivateEvent() throws {
        XCTAssertEqual(present(today: "2031-03-26", Fx.all).eventNote?.lines, ["Private event · 26 Mar"])
        XCTAssertEqual(present(today: "2031-05-21", Fx.all).eventNote?.lines, ["Private event · since 19 May"])
        let v9 = try XCTUnwrap(present(today: "2031-02-05", Fx.v9).eventNote)
        XCTAssertEqual(v9.lines, ["Private event · 3 – 9 Feb"], "V9: the flag decides, not the kind")
        XCTAssertEqual(present(today: "2031-02-05", Fx.v9).weight?.marked, [false, false, true, false, true],
                       "a private event keeps its mark")

        for today in everyFixtureDay {
            let note = present(today: today, Fx.all).eventNote
            let text = ScorecardScreenFixture.strings(in: note as Any).joined(separator: "\n")
            for needle in Fx.privateNeedles + [Fx.ordinaryNote] {
                XCTAssertFalse(text.contains(needle), "\(today): the note prints \(needle)")
            }
        }
    }

    func testMoreThanThreeEventsAreCutWithACount() throws {
        // Design variant DMany: three more events in week 15 beside the diet break.
        let many = Fx.all + [
            Fx.make("d100000000000000", .deload, "2031-04-15", "2031-04-15", createdAt: 1010),
            Fx.make("d200000000000000", .travel, "2031-04-16", "2031-04-17", createdAt: 1011),
            Fx.make("d300000000000000", .supplementChange, "2031-04-18", "2031-04-18", createdAt: 1012),
        ]
        let note = try XCTUnwrap(present(today: "2031-04-16", many).eventNote)
        XCTAssertEqual(note, CutScorecardPresentation.EventNote(
            title: title, lines: ["Supplement change · 18 Apr", "Travel · 16 – 17 Apr", "Deload · 15 Apr"],
            earlierTitle: earlierTitle, earlierLines: ["Private event · 26 Mar", "Travel · 10 – 16 Mar"],
            moreText: "and 1 more", footnote: footnote))
    }

    func testNoJudgedWeekGivesNoNote() throws {
        // No readings at all.
        let empty = S1.input(today: "2031-03-12", without: Set(1...22))
        XCTAssertNil(CutScorecard.evaluate(empty).judgedWeekStart)
        XCTAssertNil(present(empty, Fx.all).eventNote)

        // A phase that has not started.
        let later = CutScorecardPhase(name: "Fixture cut", startDay: "2031-07-07", targetWeightKg: 94.0,
                                      rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
        let notStarted = S1.input(today: "2031-03-12", phase: later)
        let notStartedNote = present(notStarted, Fx.all).eventNote
        if CutScorecard.evaluate(notStarted).judgedWeekStart == nil { XCTAssertNil(notStartedNote) }
        XCTAssertEqual(stripped(present(notStarted, Fx.all)), present(notStarted, nil))

        // Overdue (frame N12): no note, and the curves keep their marks.
        let overdue = S1.input(today: "2031-06-25")
        XCTAssertEqual(CutScorecard.evaluate(overdue).verdict.reason, .weighInOverdue)
        let p = present(overdue, Fx.all)
        XCTAssertNil(p.eventNote)
        XCTAssertEqual(p.weight?.marked.contains(true), true)
    }

    func testMarkedHasOneEntryPerCurvePoint() {
        for events in [Fx.all, [Fx.e7], Fx.v9] {
            for today in everyFixtureDay {
                let input = S1.input(today: today)
                let p = present(input, events)
                let expected = expectedMarks(events, shownWeeks(CutScorecard.evaluate(input), input))
                for curve in [p.weight, p.waist].compactMap({ $0 }) {
                    if expected.contains(true) {
                        XCTAssertEqual(curve.marked.count, curve.points.count, "\(today) \(curve.title)")
                        XCTAssertEqual(curve.marked, expected, "\(today) \(curve.title)")
                    } else {
                        XCTAssertTrue(curve.marked.isEmpty || curve.marked == expected, "\(today) \(curve.title)")
                    }
                }
            }
        }
        // Week 22's screen: the fixture table of §13.2.
        let marks = present(today: "2031-06-04", Fx.all).weight?.marked.map { $0 ? "1" : "0" }.joined()
        XCTAssertEqual(marks, "0010101101010011000111")
    }
}
