// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §7.1, §10.2, §10.3, §10.5, §11 and §13.2
// before the implementation exists. The full API block (`NiggleLogPresenter`, its presentations and
// rows) is at the top of Stage6TestSupport.swift. Expected labels, day counts and next changes are
// those of §13.2, which the pure tests already pin; here they are asserted as the presenter words them.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. An open row with no label sorts after every labelled row (no action is below "Watch"). Rows
//     with equal severity sort by day count descending, then by location.
//  2. "Logged before" counts entries of either kind whose onset is before this entry's and whose
//     location (trimmed, case-insensitive) and side are the same; zero gives no text.
//  3. The detail's actions are, in order: open [addUpdate, markResolved, edit, delete]; resolved
//     [reopen, edit, delete]; observation [edit, delete].
//  4. Side words: "Left", "Right", "Both", "Not applicable" (§11).
//  5. Several labels in "Also matches: %@" are joined by ", ".
//
// Not pinnable here: Loading (skeleton lines), the largest text size and Reduce Motion are view
// behaviour with no presenter output; the delete confirmation is a view.
//
// Synthetic values only.

import XCTest
import StrandAnalytics
@testable import Strand

final class NiggleLogPresenterTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let gb = Stage6Fixture.british

    private static let disclaimer = "Your rule, applied to what you logged. This is not a diagnosis."

    private func present(_ entries: [StoredNiggle], rules: StoredTriageRules = Fx.rules,
                         paused: [StoredPausedExercise] = [], entriesNeedAttention: Bool = false,
                         rulesNeedAttention: Bool = false, today: String) -> NiggleLogPresentation {
        NiggleLogPresenter.present(entries: entries, rules: rules, paused: paused,
                                   entriesNeedAttention: entriesNeedAttention, rulesNeedAttention: rulesNeedAttention,
                                   pausedNeedAttention: false, today: today, locale: gb)
    }

    private func detail(_ id: String, _ entries: [StoredNiggle], rules: StoredTriageRules = Fx.rules,
                        paused: [StoredPausedExercise] = [Fx.pausedPress, Fx.pausedRow],
                        rulesNeedAttention: Bool = false, today: String) -> NiggleDetailPresentation? {
        NiggleLogPresenter.detail(niggleId: id, entries: entries, rules: rules, paused: paused,
                                  rulesNeedAttention: rulesNeedAttention, today: today, locale: gb)
    }

    // MARK: §10.2 log screen

    func testFirstUseNothingStored() {
        let p = present([], rules: Fx.noRules, today: "2031-03-22")
        XCTAssertEqual(p.state, .firstUse)
        let text = Stage6Text.strings(in: p)
        XCTAssertTrue(text.contains("Log a niggle"), "\(text)")
        XCTAssertTrue(text.contains("Set up your rules"), "\(text)")
        XCTAssertTrue(p.canAdd)
        XCTAssertEqual(p.open, [])
    }

    func testNoRulesEnteredHeaderAndRows() throws {
        let p = present([Fx.n2], rules: Fx.noRules, today: "2031-03-22")
        XCTAssertEqual(p.state, .list)
        XCTAssertEqual(p.professionalNotice, "No rules entered yet")
        XCTAssertTrue(Stage6Text.strings(in: p).contains("Set up your rules"))
        let row = try XCTUnwrap(p.open.first)
        XCTAssertEqual(row.dayCountText, "Day 20")
        XCTAssertEqual(row.triageLine, "No rules entered yet")
        XCTAssertNil(row.label)
        XCTAssertNil(row.actionText)
        XCTAssertNil(row.nextChangeLine, "no rule, so nothing changes")
    }

    func testRulesEnteredButProfessionalRuleEmpty() {
        let p = present([Fx.n2], rules: StoredTriageRules(professionalRule: "", rules: Fx.rules.rules), today: "2031-03-22")
        XCTAssertEqual(p.professionalNotice, "You have not written a rule for seeing a professional")
        XCTAssertNil(p.professionalRule)
        let withRule = present([Fx.n2], today: "2031-03-22")
        XCTAssertEqual(withRule.professionalRule, "Fixture rule text.")
        XCTAssertNil(withRule.professionalNotice)
    }

    func testOpenComplaintRuleMatched() throws {
        let row = try XCTUnwrap(present([Fx.n2], today: "2031-03-22").open.first)
        XCTAssertEqual(row.id, Fx.n2.id)
        XCTAssertEqual(row.location, "Fixture location B")
        XCTAssertEqual(row.sideText, "Right")
        XCTAssertEqual(row.dayCountText, "Day 20")
        XCTAssertEqual(row.label, "Fixture label D", "the more serious action wins (N2d)")
        XCTAssertEqual(row.actionText, "See a professional")
        XCTAssertEqual(row.disclaimer, Self.disclaimer)
        XCTAssertNil(row.triageLine)
    }

    func testOpenComplaintNoRuleMatches() throws {
        let row = try XCTUnwrap(present([Fx.n5], today: "2031-05-14").open.first)
        XCTAssertEqual(row.dayCountText, "Day 10")
        XCTAssertEqual(row.triageLine, "None of your rules covers this")
        XCTAssertNil(row.label)
        XCTAssertNil(row.actionText)
        XCTAssertNil(row.disclaimer, "the disclaimer sits under a label")
    }

    func testOpenComplaintWithANextChangeToARule() throws {
        let row = try XCTUnwrap(present([Fx.n2], today: "2031-03-22").open.first)
        XCTAssertEqual(row.nextChangeLine, "Day 30: your rule \u{201C}Fixture label C\u{201D} applies")
        let early = try XCTUnwrap(present([Fx.n2], today: "2031-03-03").open.first)
        XCTAssertEqual(early.nextChangeLine, "Day 5: your rule \u{201C}Fixture label B\u{201D} applies", "N2a")
    }

    func testOpenComplaintWithANextChangeToNoRule() throws {
        let row = try XCTUnwrap(present([Fx.n6], today: "2031-06-11").open.first)
        XCTAssertEqual(row.label, "Fixture label A")
        XCTAssertEqual(row.actionText, "Watch")
        XCTAssertEqual(row.nextChangeLine, "Day 11: no rule of yours applies")
    }

    func testRecurrenceCountsEarlierEntriesWithTheSameLocationAndSide() throws {
        let p = present([Fx.n2, Fx.n7], today: "2031-06-16")
        let recurrence = try XCTUnwrap(p.open.first { $0.id == Fx.n7.id })
        XCTAssertTrue(recurrence.recurrenceText?.hasPrefix("Logged before: 1") == true, "\(String(describing: recurrence.recurrenceText))")
        XCTAssertNil(p.open.first { $0.id == Fx.n2.id }?.recurrenceText, "the first episode has no earlier one")

        var otherSide = Fx.n7
        otherSide.side = .left
        XCTAssertNil(present([Fx.n2, otherSide], today: "2031-06-16").open.first { $0.id == otherSide.id }?.recurrenceText)

        var spelled = Fx.n7
        spelled.location = "  fixture LOCATION b "
        let folded = present([Fx.n2, spelled], today: "2031-06-16").open.first { $0.id == spelled.id }
        XCTAssertTrue(folded?.recurrenceText?.hasPrefix("Logged before: 1") == true, "trimmed and case-insensitive")
        XCTAssertEqual(folded?.location, "  fixture LOCATION b ", "but shown as typed")

        // Resolved earlier episodes count too.
        var resolved = Fx.n2
        resolved.resolvedDay = "2031-04-01"
        let afterResolved = present([resolved, Fx.n7], today: "2031-06-16").open.first { $0.id == Fx.n7.id }
        XCTAssertTrue(afterResolved?.recurrenceText?.hasPrefix("Logged before: 1") == true)
    }

    func testOpenRowsSortBySeverityThenDayCount() {
        let p = present([Fx.n7, Fx.n6, Fx.n5, Fx.n3, Fx.n2, Fx.n1], today: "2031-06-16")
        XCTAssertEqual(p.open.map(\.id), [Fx.n2.id, Fx.n3.id, Fx.n5.id, Fx.n6.id, Fx.n7.id])
        XCTAssertEqual(p.open.map(\.dayCountText), ["Day 106", "Day 71", "Day 43", "Day 15", "Day 1"])
        XCTAssertEqual(p.open.map(\.label), ["Fixture label C", "Fixture label C", "Fixture label C", nil, nil])

        // Equal severity and equal day count: by location.
        var twin = Fx.n5
        twin.id = "n-0000000f"
        twin.location = "Fixture location AA"
        let tied = present([Fx.n5, twin], today: "2031-06-16")
        XCTAssertEqual(tied.open.map(\.id), [twin.id, Fx.n5.id])
    }

    func testPausedExercisesSection() throws {
        let p = present([Fx.n2], paused: [Fx.pausedPress, Fx.pausedRow], today: "2031-03-22")
        XCTAssertEqual(p.paused.map(\.id), [Fx.pausedPress.id])
        let row = try XCTUnwrap(p.paused.first)
        XCTAssertEqual(row.exercise, "Fixture Press")
        XCTAssertEqual(row.reason, "Fixture reason A")
        XCTAssertTrue(row.sinceText.hasPrefix("since "), row.sinceText)
        XCTAssertTrue(row.sinceText.contains("10") && row.sinceText.contains("Mar"), row.sinceText)
        XCTAssertEqual(row.untilText.map { $0.contains("Fixture until text") }, true)
        XCTAssertEqual(row.niggleId, Fx.n2.id)
        XCTAssertNil(row.resumedText)
    }

    func testNoPausedExercisesMeansNoSection() {
        let p = present([Fx.n2], paused: [], today: "2031-03-22")
        XCTAssertEqual(p.paused, [])
        XCTAssertEqual(p.resumed, [])
        XCTAssertFalse(Stage6Text.strings(in: p).contains("Paused by your coach"), "the heading goes with the section")
    }

    func testResumedExercisesUnderTheirOwnList() throws {
        let p = present([Fx.n2], paused: [Fx.pausedPress, Fx.pausedRow], today: "2031-03-22")
        let row = try XCTUnwrap(p.resumed.first)
        XCTAssertEqual(p.resumed.map(\.id), [Fx.pausedRow.id])
        XCTAssertTrue(row.resumedText?.hasPrefix("Resumed ") == true)
        XCTAssertTrue(row.resumedText?.contains("10") == true && row.resumedText?.contains("Feb") == true)
        XCTAssertEqual(row.reason, "Fixture reason B")
        XCTAssertNil(row.niggleId)
    }

    func testObservationsSection() throws {
        let p = present([Fx.n4, Fx.n2], today: "2031-03-22")
        let row = try XCTUnwrap(p.observations.first)
        XCTAssertEqual(row.id, Fx.n4.id)
        XCTAssertEqual(row.location, "Fixture observation")
        XCTAssertEqual(row.sideText, "Not applicable")
        XCTAssertEqual(row.note, "Fixture observation note")
        XCTAssertTrue(row.notedText.hasPrefix("noted ") && row.notedText.contains("13") && row.notedText.contains("Jan"),
                      row.notedText)
        XCTAssertFalse(p.open.contains { $0.id == Fx.n4.id })
    }

    func testResolvedCarriesDurationAndNoLabel() throws {
        let p = present([Fx.n1, Fx.n2], today: "2031-03-22")
        let row = try XCTUnwrap(p.resolved.first)
        XCTAssertEqual(row.id, Fx.n1.id)
        XCTAssertEqual(row.durationText, "Resolved after 10 days")
        XCTAssertTrue(row.datesText.contains("3") && row.datesText.contains("12") && row.datesText.contains("Feb"),
                      row.datesText)
        XCTAssertFalse(Stage6Text.joined(row).contains("Fixture label"), "a resolved entry carries no label")
        XCTAssertFalse(p.open.contains { $0.id == Fx.n1.id })
    }

    func testEntriesNeedAttention() {
        let p = present([], entriesNeedAttention: true, today: "2031-03-22")
        XCTAssertEqual(p.state, .entriesNeedAttention)
        XCTAssertEqual(p.entriesAttentionText, "Your log could not be read. Nothing has been changed.")
        XCTAssertTrue(Stage6Text.strings(in: p).contains("Discard unreadable data"))
        XCTAssertFalse(p.canAdd, "adding is disabled")
    }

    func testRulesNeedAttention() throws {
        let p = present([Fx.n2], rules: Fx.noRules, rulesNeedAttention: true, today: "2031-03-22")
        XCTAssertEqual(p.rulesAttentionText, "Your rules could not be read. Nothing has been changed.")
        XCTAssertTrue(Stage6Text.strings(in: p).contains("Discard unreadable data"))
        let row = try XCTUnwrap(p.open.first)
        XCTAssertEqual(row.dayCountText, "Day 20", "complaints still show day counts")
        XCTAssertEqual(row.triageLine, "Your rules need attention")
        XCTAssertNil(row.label)
    }

    func testLimitReached() {
        let many = (0..<500).map { i -> StoredNiggle in
            var n = Fx.n1
            n.id = String(format: "n-%08x", i + 0x100)
            return n
        }
        let p = present(many, today: "2031-03-22")
        XCTAssertFalse(p.canAdd)
        XCTAssertEqual(p.limitText, "The log holds up to 500 entries")
        XCTAssertTrue(present([Fx.n1], today: "2031-03-22").canAdd)
        XCTAssertNil(present([Fx.n1], today: "2031-03-22").limitText)
    }

    // MARK: §10.3 detail

    func testDetailOpenMatched() throws {
        let d = try XCTUnwrap(detail(Fx.n2.id, [Fx.n1, Fx.n2], today: "2031-03-22"))
        XCTAssertEqual(d.kind, .open)
        XCTAssertEqual(d.location, "Fixture location B")
        XCTAssertEqual(d.dayCountText, "Day 20")
        XCTAssertEqual(d.label, "Fixture label D")
        XCTAssertEqual(d.actionText, "See a professional")
        XCTAssertEqual(d.ruleNote, "Fixture rule note D")
        XCTAssertEqual(d.disclaimer, Self.disclaimer)
        XCTAssertEqual(d.alsoMatchesText, "Also matches: Fixture label B")
        XCTAssertEqual(d.nextChangeLine, "Day 30: your rule \u{201C}Fixture label C\u{201D} applies")
        XCTAssertEqual(d.updates.map(\.seq), [1])
        XCTAssertEqual(d.updates.first?.trendText, "Getting worse")
        XCTAssertEqual(d.updates.first?.isUsed, true)
        XCTAssertNil(d.ignoredUpdatesText)
        XCTAssertEqual(d.pausedExercises.map(\.id), [Fx.pausedPress.id], "linked pauses only")
        XCTAssertEqual(d.professionalRule, "Fixture rule text.")
        XCTAssertEqual(d.actions, [.addUpdate, .markResolved, .edit, .delete])
    }

    func testDetailUpdatesAreNewestFirst() throws {
        var n = Fx.n2
        n.updates = [StoredNiggleUpdate(seq: 1, day: "2031-03-10", trend: .easing, weakness: false, note: "first"),
                     StoredNiggleUpdate(seq: 3, day: "2031-03-12", trend: .unchanged, weakness: false, note: "third"),
                     StoredNiggleUpdate(seq: 2, day: "2031-03-12", trend: .worsening, weakness: true, note: "second")]
        let d = try XCTUnwrap(detail(n.id, [n], today: "2031-03-22"))
        XCTAssertEqual(d.updates.map(\.seq), [3, 2, 1])
        XCTAssertEqual(d.updates.map(\.note), ["third", "second", "first"])
    }

    func testDetailOpenNoRuleMatchesNoRulesAndRulesNeedAttention() throws {
        let none = try XCTUnwrap(detail(Fx.n5.id, [Fx.n5], today: "2031-05-14"))
        XCTAssertEqual(none.triageLine, "None of your rules covers this")
        XCTAssertNil(none.label)
        XCTAssertNil(none.disclaimer)
        XCTAssertEqual(none.nextChangeLine, "Day 30: your rule \u{201C}Fixture label C\u{201D} applies")

        let empty = try XCTUnwrap(detail(Fx.n2.id, [Fx.n2], rules: Fx.noRules, today: "2031-03-22"))
        XCTAssertEqual(empty.triageLine, "No rules entered yet")
        XCTAssertNil(empty.label)
        XCTAssertEqual(empty.dayCountText, "Day 20")

        let attention = try XCTUnwrap(detail(Fx.n2.id, [Fx.n2], rules: Fx.noRules, rulesNeedAttention: true,
                                             today: "2031-03-22"))
        XCTAssertEqual(attention.triageLine, "Your rules need attention")
        XCTAssertNil(attention.label)
        XCTAssertEqual(attention.actions, [.addUpdate, .markResolved, .edit, .delete])
    }

    func testDetailResolved() throws {
        let d = try XCTUnwrap(detail(Fx.n1.id, [Fx.n1], today: "2031-03-01"))
        XCTAssertEqual(d.kind, .resolved)
        XCTAssertEqual(d.dayCountText, "Resolved after 10 days")
        XCTAssertNil(d.label)
        XCTAssertNil(d.actionText)
        XCTAssertNil(d.nextChangeLine)
        XCTAssertEqual(d.actions, [.reopen, .edit, .delete])
    }

    func testDetailObservation() throws {
        let d = try XCTUnwrap(detail(Fx.n4.id, [Fx.n4], today: "2031-03-22"))
        XCTAssertEqual(d.kind, .observation)
        XCTAssertEqual(d.note, "Fixture observation note")
        XCTAssertNil(d.dayCountText)
        XCTAssertNil(d.label)
        XCTAssertNil(d.triageLine)
        XCTAssertNil(d.nextChangeLine)
        XCTAssertEqual(d.actions, [.edit, .delete])
    }

    func testDetailUpdatesIgnoredFootnote() throws {
        // N2c: the stored update is dated after today; it is kept, shown as not used, and footnoted.
        let d = try XCTUnwrap(detail(Fx.n2.id, [Fx.n2], today: "2031-03-21"))
        XCTAssertEqual(d.dayCountText, "Day 19")
        XCTAssertEqual(d.label, "Fixture label B")
        XCTAssertEqual(d.updates.map(\.isUsed), [false])
        XCTAssertTrue(d.ignoredUpdatesText?.hasPrefix("1 update") == true, "\(String(describing: d.ignoredUpdatesText))")
        // An edited onset after the update's day: kept, ignored, footnoted, never deleted.
        var moved = Fx.n2
        moved.onsetDay = "2031-03-23"
        moved.updates = [StoredNiggleUpdate(seq: 1, day: "2031-03-22", trend: .worsening, weakness: false, note: "")]
        let later = try XCTUnwrap(detail(moved.id, [moved], today: "2031-03-25"))
        XCTAssertEqual(later.updates.count, 1)
        XCTAssertTrue(later.ignoredUpdatesText?.hasPrefix("1 update") == true)
    }

    func testDetailOfAnEntryThatNoLongerExistsIsNil() {
        XCTAssertNil(detail(Fx.n2.id, [Fx.n1], today: "2031-03-22"), "the screen pops")
    }

    // MARK: §10.5 rule preview and action words

    func testActionWords() {
        XCTAssertEqual(NiggleLogPresenter.actionText(.watch, locale: gb), "Watch")
        XCTAssertEqual(NiggleLogPresenter.actionText(.modify, locale: gb), "Modify training")
        XCTAssertEqual(NiggleLogPresenter.actionText(.seeProfessional, locale: gb), "See a professional")
    }

    func testRulePreviewReadsBackEveryField() {
        let a = NiggleLogPresenter.rulePreview(Fx.ruleA, locale: gb)
        for part in ["Spread over an area", "Easing", "from day 1", "through day 10",
                     "is labelled \u{201C}Fixture label A\u{201D}"] {
            XCTAssertTrue(a.contains(part), "\(part) missing from: \(a)")
        }
        let c = NiggleLogPresenter.rulePreview(Fx.ruleC, locale: gb)
        XCTAssertTrue(c.contains("Any complaint"), c)
        XCTAssertTrue(c.contains("from day 30"), c)
        XCTAssertFalse(c.contains("through day"), c)
        let e = NiggleLogPresenter.rulePreview(Fx.ruleE, locale: gb)
        XCTAssertTrue(e.contains("with weakness"), e)
        var without = Fx.ruleE
        without.weakness = false
        XCTAssertTrue(NiggleLogPresenter.rulePreview(without, locale: gb).contains("without weakness"))
        // Changing a field changes the read-back.
        var later = Fx.ruleA
        later.throughDay = 12
        XCTAssertNotEqual(NiggleLogPresenter.rulePreview(later, locale: gb), a)
    }

    // MARK: Health row

    func testHealthRowShowsTheOpenCountOnlyWhileEnabled() {
        let all = [Fx.n1, Fx.n2, Fx.n3, Fx.n4, Fx.n5, Fx.n6, Fx.n7]
        XCTAssertNil(NiggleLogPresenter.healthRow(enabled: false, entries: all, today: "2031-06-16", locale: gb))
        let row = NiggleLogPresenter.healthRow(enabled: true, entries: all, today: "2031-06-16", locale: gb)
        XCTAssertEqual(row?.title, "Niggle log")
        XCTAssertEqual(row?.detail, "5 open")
        let none = NiggleLogPresenter.healthRow(enabled: true, entries: [Fx.n1, Fx.n4], today: "2031-06-16", locale: gb)
        XCTAssertEqual(none?.title, "Niggle log")
        XCTAssertNil(none?.detail, "nothing open: no detail, never \"0 open\"")
    }

    // MARK: Cross-cutting

    func testObservationsAreNeverTriaged() throws {
        let anything = StoredTriageRule(id: "r-000000ff", label: "Fixture label any", action: .seeProfessional,
                                        characters: [], trends: [], weakness: nil, fromDay: 1, throughDay: nil, note: "")
        let rules = StoredTriageRules(professionalRule: "", rules: [anything])
        let p = present([Fx.n4], rules: rules, today: "2031-06-16")
        XCTAssertEqual(p.open, [])
        XCTAssertEqual(p.observations.map(\.id), [Fx.n4.id])
        XCTAssertFalse(Stage6Text.joined(p).contains("Fixture label any"))
        let d = try XCTUnwrap(detail(Fx.n4.id, [Fx.n4], rules: rules, today: "2031-06-16"))
        XCTAssertNil(d.label)
        XCTAssertNil(d.dayCountText)
        XCTAssertEqual(NiggleLogPresenter.healthRow(enabled: true, entries: [Fx.n4], today: "2031-06-16", locale: gb)?.detail,
                       nil, "an observation is not open")
    }

    func testOwnerTextIsShownVerbatim() throws {
        let rule = StoredTriageRule(id: "r-0000000a", label: "fixture Label – MiXed ✓", action: .watch, characters: [],
                                    trends: [], weakness: nil, fromDay: 1, throughDay: nil, note: "fixture note, as typed")
        let rules = StoredTriageRules(professionalRule: "Fixture rule text.\nSecond line, as typed.", rules: [rule])
        var n = Fx.n2
        n.location = "fixture LOCATION – b"
        let p = present([n], rules: rules, today: "2031-03-22")
        let strings = Stage6Text.strings(in: p)
        XCTAssertTrue(strings.contains("fixture LOCATION – b"))
        XCTAssertTrue(strings.contains("fixture Label – MiXed ✓"))
        XCTAssertEqual(p.professionalRule, "Fixture rule text.\nSecond line, as typed.")
        let d = try XCTUnwrap(detail(n.id, [n], rules: rules, today: "2031-03-22"))
        XCTAssertEqual(d.ruleNote, "fixture note, as typed")
        XCTAssertEqual(d.label, "fixture Label – MiXed ✓")
        XCTAssertEqual(d.professionalRule, "Fixture rule text.\nSecond line, as typed.")
        XCTAssertTrue(NiggleLogPresenter.rulePreview(rule, locale: gb).contains("\u{201C}fixture Label – MiXed ✓\u{201D}"))
    }

    /// Every presentation over the fixture, across days, rule sets and attention states.
    private func sweep() -> [Any] {
        let entries = [Fx.n1, Fx.n2, Fx.n3, Fx.n4, Fx.n5, Fx.n6, Fx.n7]
        var out: [Any] = []
        for today in ["2031-02-05", "2031-03-03", "2031-03-07", "2031-03-21", "2031-03-22", "2031-04-07",
                      "2031-05-14", "2031-06-11", "2031-06-12", "2031-06-16", "2031-08-01"] {
            let valid = entries.filter { $0.onsetDay <= today && ($0.resolvedDay ?? today) <= today }
            for rules in [Fx.rules, Fx.noRules, StoredTriageRules(professionalRule: "", rules: Fx.rules.rules)] {
                for attention in [false, true] {
                    out.append(present(valid, rules: rules, paused: [Fx.pausedPress, Fx.pausedRow],
                                       rulesNeedAttention: attention, today: today))
                    for entry in valid {
                        if let d = detail(entry.id, valid, rules: rules, rulesNeedAttention: attention, today: today) {
                            out.append(d)
                        }
                    }
                }
            }
        }
        out.append(present([], rules: Fx.noRules, today: "2031-03-22"))
        out.append(present([], entriesNeedAttention: true, today: "2031-03-22"))
        for rule in Fx.rules.rules { out.append(NiggleLogPresenter.rulePreview(rule, locale: gb)) }
        return out
    }

    func testEveryLabelCarriesTheNotADiagnosisLine() {
        var labelled = 0
        for value in sweep() {
            if let p = value as? NiggleLogPresentation {
                for row in p.open where row.label != nil {
                    labelled += 1
                    XCTAssertEqual(row.disclaimer, Self.disclaimer, "row \(row.id)")
                }
            }
            if let d = value as? NiggleDetailPresentation, d.label != nil {
                labelled += 1
                XCTAssertEqual(d.disclaimer, Self.disclaimer, d.location)
            }
        }
        XCTAssertGreaterThan(labelled, 20, "the sweep reaches labelled rows")
    }

    func testNoPresenterStringNamesACauseOrTreatment() {
        let stems = ["diagnos", "injur", "treat"]
        let words = ["tendon", "tendons", "strain", "sprain", "tear", "torn", "rest it", "ice", "should"]
        var scanned = 0
        for value in sweep() {
            for text in Stage6Text.strings(in: value) where text != Self.disclaimer {
                scanned += 1
                for stem in stems {
                    XCTAssertFalse(Stage6Text.containsStem(text, stem), "\"\(stem)\" in: \(text)")
                }
                for word in words {
                    XCTAssertFalse(Stage6Text.containsWord(text, word), "\"\(word)\" in: \(text)")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 500, "the sweep reaches the strings")
    }

    func testNoStateRendersAMissingValueAsZero() {
        for value in sweep() {
            for text in Stage6Text.strings(in: value) {
                XCTAssertNil(text.range(of: "\\bDay 0\\b", options: .regularExpression), text)
                XCTAssertNil(text.range(of: "\\b0 days\\b", options: .regularExpression), text)
                XCTAssertNil(text.range(of: "^0 open$", options: .regularExpression), text)
                XCTAssertNil(text.range(of: "Logged before: 0", options: .regularExpression), text)
                XCTAssertNil(text.range(of: "^0 updates", options: .regularExpression), text)
            }
        }
    }

    func testActionsCarryNoColourWords() {
        // D6: an action is a word, never a colour state. Nothing in the presentations names one.
        for value in sweep() {
            for text in Stage6Text.strings(in: value) {
                for word in ["red", "amber", "green", "warning", "urgent", "overdue"] {
                    XCTAssertFalse(Stage6Text.containsWord(text, word), "\(word) in \(text)")
                }
            }
        }
    }
}
