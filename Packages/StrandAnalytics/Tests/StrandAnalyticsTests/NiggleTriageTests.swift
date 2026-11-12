import XCTest
@testable import StrandAnalytics

// API ASSUMED BY THESE TESTS
//
// Stage 6 specification, docs/personal/superapp/specs/stage-6.md §6.1. Every type is public, Equatable
// and Sendable, with a public memberwise init taking the stored properties in declaration order.
//
//   enum NiggleCharacter: String, CaseIterable { case diffuse, localised, positional, other }
//   enum NiggleTrend: String, CaseIterable { case easing, unchanged, worsening, notRecorded }
//   enum NiggleAction: String, CaseIterable { case watch, modify, seeProfessional }
//
//   struct NiggleUpdate
//     init(day: String, sequence: Int, trend: NiggleTrend, weakness: Bool)
//   struct NiggleComplaint
//     init(onsetDay: String, resolvedDay: String?, character: NiggleCharacter, trend: NiggleTrend,
//          weakness: Bool, updates: [NiggleUpdate] = [])
//     let onsetDay: String; let trend: NiggleTrend; let weakness: Bool
//   struct NiggleTriageRule
//     init(id: String, action: NiggleAction, characters: [NiggleCharacter], trends: [NiggleTrend],
//          weakness: Bool?, fromDay: Int?, throughDay: Int?)
//     var id, action, characters, trends, weakness, fromDay, throughDay   (all mutable)
//   struct NiggleTriageInput
//     init(complaint: NiggleComplaint, rules: [NiggleTriageRule], today: String)
//
//   enum NiggleTriageStatus: String { case matched, noRuleMatches, noRulesEntered, resolved, invalidInput }
//   enum NiggleTriageInvalid: String {
//     case today, rules, onsetDay, onsetAfterToday, resolvedDay, resolvedBeforeOnset, resolvedAfterToday }
//   struct NiggleTriageNextChange
//     init(dayCount: Int, day: String, ruleId: String?, action: NiggleAction?)
//   struct NiggleTriageResult
//     let status: NiggleTriageStatus; let invalid: NiggleTriageInvalid?; let isOpen: Bool
//     let dayCount: Int?; let currentTrend: NiggleTrend; let currentWeakness: Bool
//     let stateDay: String?; let ruleId: String?; let action: NiggleAction?
//     let matchedRuleIds: [String]; let nextChange: NiggleTriageNextChange?; let ignoredUpdates: Int
//
//   enum NiggleTriage
//     static func evaluate(_ input: NiggleTriageInput) -> NiggleTriageResult
//     static func severity(_ action: NiggleAction) -> Int
//     static func rulesAreValid(_ rules: [NiggleTriageRule]) -> Bool
//
// From the existing test target (not stage 6): CutScorecardFixture.dayNumber(_:) and .dayKey(_:), the
// fixture's own civil-calendar arithmetic. These tests call neither CanonicalDay nor any engine date
// code, so a fault in the engine's day arithmetic cannot hide behind the same fault here.
//
// SPEC-AMBIGUITY (assumed): `isOpen` is true for every valid result of an unresolved complaint. §7.1
// states only that it is false when resolved and when invalid.

private typealias F = CutScorecardFixture

/// The onset day most tests use: 2031-03-03, a Monday, the onset of fixture complaint N2 (§13.2).
private let fixtureOnset = "2031-03-03"

/// `base` moved by `offset` days.
private func day(_ base: String, _ offset: Int) -> String {
    F.dayKey(F.dayNumber(base) + offset)
}

private func rule(_ id: String, _ action: NiggleAction = .watch,
                  characters: [NiggleCharacter] = [], trends: [NiggleTrend] = [],
                  weakness: Bool? = nil, from: Int? = nil, through: Int? = nil) -> NiggleTriageRule {
    NiggleTriageRule(id: id, action: action, characters: characters, trends: trends,
                     weakness: weakness, fromDay: from, throughDay: through)
}

private func complaint(onset: String = fixtureOnset, resolved: String? = nil,
                       character: NiggleCharacter = .diffuse, trend: NiggleTrend = .unchanged,
                       weakness: Bool = false, updates: [NiggleUpdate] = []) -> NiggleComplaint {
    NiggleComplaint(onsetDay: onset, resolvedDay: resolved, character: character, trend: trend,
                    weakness: weakness, updates: updates)
}

private func update(_ day: String, _ sequence: Int, _ trend: NiggleTrend,
                    weakness: Bool = false) -> NiggleUpdate {
    NiggleUpdate(day: day, sequence: sequence, trend: trend, weakness: weakness)
}

private func evaluate(_ complaint: NiggleComplaint, _ rules: [NiggleTriageRule],
                      today: String) -> NiggleTriageResult {
    NiggleTriage.evaluate(NiggleTriageInput(complaint: complaint, rules: rules, today: today))
}

/// Evaluates `complaint` with `today` chosen so that the day count is `n`.
private func atDay(_ n: Int, _ rules: [NiggleTriageRule],
                   _ complaint: NiggleComplaint = complaint()) -> NiggleTriageResult {
    evaluate(complaint, rules, today: day(complaint.onsetDay, n - 1))
}

private func next(_ dayCount: Int, _ day: String, _ ruleId: String?,
                  _ action: NiggleAction?) -> NiggleTriageNextChange {
    NiggleTriageNextChange(dayCount: dayCount, day: day, ruleId: ruleId, action: action)
}

/// Strings that are not a canonical "yyyy-MM-dd" key (stage 1 ruling R5).
private let nonCanonicalDays = [
    "", "2031-3-03", "2031-03-3", "20310303", "2031/03/03", "2031-02-30", "2031-13-01",
    "2031-00-10", "2031-01-00", "0000-01-01", "2031-03-03 ", " 2031-03-03", "2031-03-03T00",
    "abcd-ef-gh",
]

/// The five rules of §13.1, in the owner's order.
private let fixtureRules: [NiggleTriageRule] = [
    rule("r-a", .watch, characters: [.diffuse], trends: [.easing], from: 1, through: 10),
    rule("r-b", .modify, characters: [.positional], from: 5),
    rule("r-c", .seeProfessional, from: 30),
    rule("r-d", .seeProfessional, trends: [.worsening], from: 20),
    rule("r-e", .modify, characters: [.localised], weakness: true, from: 1),
]

/// `NiggleTriage` (stage 6 specification §6.1, §7.1, test plan §12.1, fixture §13.1 and §13.2).
///
/// Every value here is invented. Expected values were worked by hand from §7.1; none is the output of an
/// implementation.
final class NiggleTriageTests: XCTestCase {

    private func assertInvalid(_ result: NiggleTriageResult, _ cause: NiggleTriageInvalid,
                               _ complaint: NiggleComplaint,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.status, .invalidInput, file: file, line: line)
        XCTAssertEqual(result.invalid, cause, file: file, line: line)
        XCTAssertFalse(result.isOpen, file: file, line: line)
        XCTAssertNil(result.dayCount, file: file, line: line)
        XCTAssertEqual(result.currentTrend, complaint.trend, file: file, line: line)
        XCTAssertEqual(result.currentWeakness, complaint.weakness, file: file, line: line)
        XCTAssertNil(result.stateDay, file: file, line: line)
        XCTAssertNil(result.ruleId, file: file, line: line)
        XCTAssertNil(result.action, file: file, line: line)
        XCTAssertEqual(result.matchedRuleIds, [], file: file, line: line)
        XCTAssertNil(result.nextChange, file: file, line: line)
        XCTAssertEqual(result.ignoredUpdates, 0, file: file, line: line)
    }

    private func assertMatched(_ result: NiggleTriageResult, _ id: String, _ action: NiggleAction,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.status, .matched, file: file, line: line)
        XCTAssertNil(result.invalid, file: file, line: line)
        XCTAssertEqual(result.ruleId, id, file: file, line: line)
        XCTAssertEqual(result.action, action, file: file, line: line)
        XCTAssertTrue(result.isOpen, file: file, line: line)
    }

    private func assertNoMatch(_ result: NiggleTriageResult,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.status, .noRuleMatches, file: file, line: line)
        XCTAssertNil(result.invalid, file: file, line: line)
        XCTAssertNil(result.ruleId, file: file, line: line)
        XCTAssertNil(result.action, file: file, line: line)
        XCTAssertEqual(result.matchedRuleIds, [], file: file, line: line)
        XCTAssertTrue(result.isOpen, file: file, line: line)
    }

    // MARK: - Day count

    func testOnsetDayIsDayOne() {
        let onTheDay = evaluate(complaint(), [], today: fixtureOnset)
        XCTAssertEqual(onTheDay.dayCount, 1)
        XCTAssertEqual(evaluate(complaint(), [], today: "2031-03-04").dayCount, 2)
        XCTAssertEqual(evaluate(complaint(), [], today: "2031-03-09").dayCount, 7)
        XCTAssertEqual(evaluate(complaint(), [], today: "2031-03-10").dayCount, 8)
        // With a rule too: the count is the same whether or not a rule is present.
        XCTAssertEqual(evaluate(complaint(), [rule("a")], today: fixtureOnset).dayCount, 1)
    }

    func testDayCountAcrossAMonthAndALeapDay() {
        // 2031 is not a leap year: 28 February is followed by 1 March.
        XCTAssertEqual(evaluate(complaint(onset: "2031-02-28"), [], today: "2031-03-01").dayCount, 2)
        // 2032 is: 29 February lies between.
        XCTAssertEqual(evaluate(complaint(onset: "2032-02-28"), [], today: "2032-03-01").dayCount, 3)
        XCTAssertEqual(evaluate(complaint(onset: "2032-02-29"), [], today: "2032-02-29").dayCount, 1)
        // 31 January to 1 March 2031 is 29 days later: day 30.
        XCTAssertEqual(evaluate(complaint(onset: "2031-01-31"), [], today: "2031-03-01").dayCount, 30)
        // Across a year end.
        XCTAssertEqual(evaluate(complaint(onset: "2031-12-31"), [], today: "2032-01-01").dayCount, 2)
        // A whole leap year: 366 days later is day 367.
        XCTAssertEqual(evaluate(complaint(onset: "2032-01-01"), [], today: "2033-01-01").dayCount, 367)
    }

    // MARK: - No rules, no match

    func testNoRulesEnteredReportsDayCountAndNoLabel() {
        for (character, trend, weakness) in [(NiggleCharacter.diffuse, NiggleTrend.easing, false),
                                             (.localised, .worsening, true),
                                             (.other, .notRecorded, true)] {
            let c = complaint(character: character, trend: trend, weakness: weakness)
            let result = atDay(45, [], c)
            XCTAssertEqual(result.status, .noRulesEntered)
            XCTAssertNil(result.invalid)
            XCTAssertTrue(result.isOpen)
            XCTAssertEqual(result.dayCount, 45)
            XCTAssertNil(result.ruleId)
            XCTAssertNil(result.action)
            XCTAssertEqual(result.matchedRuleIds, [])
            XCTAssertNil(result.nextChange)
            XCTAssertEqual(result.currentTrend, trend)
            XCTAssertEqual(result.currentWeakness, weakness)
            XCTAssertEqual(result.stateDay, fixtureOnset)
            XCTAssertEqual(result.ignoredUpdates, 0)
        }
    }

    func testNoRuleMatchesWhenCharacterDiffers() {
        let rules = [rule("a", .modify, characters: [.localised, .positional])]
        let miss = atDay(3, rules, complaint(character: .diffuse))
        assertNoMatch(miss)
        XCTAssertEqual(miss.dayCount, 3)
        assertNoMatch(atDay(3, rules, complaint(character: .other)))
        // The same rule does match a character it names.
        assertMatched(atDay(3, rules, complaint(character: .localised)), "a", .modify)
        assertMatched(atDay(3, rules, complaint(character: .positional)), "a", .modify)
    }

    func testEmptyCharactersAndTrendsMatchAnything() {
        let rules = [rule("any", .watch)]
        for character in NiggleCharacter.allCases {
            for trend in NiggleTrend.allCases {
                for weakness in [false, true] {
                    let c = complaint(character: character, trend: trend, weakness: weakness)
                    let result = atDay(1, rules, c)
                    assertMatched(result, "any", .watch)
                    XCTAssertEqual(result.matchedRuleIds, ["any"])
                }
            }
        }
        // Empty on one side only is still "any" on that side.
        assertMatched(atDay(1, [rule("c", characters: [.diffuse])],
                            complaint(character: .diffuse, trend: .notRecorded)), "c", .watch)
        assertMatched(atDay(1, [rule("t", trends: [.easing])],
                            complaint(character: .other, trend: .easing)), "t", .watch)
    }

    func testDuplicatesInsideCharactersOrTrendsAreHarmless() {
        let rules = [rule("a", .modify, characters: [.diffuse, .diffuse],
                          trends: [.unchanged, .unchanged, .easing])]
        XCTAssertTrue(NiggleTriage.rulesAreValid(rules))
        let result = atDay(2, rules)
        assertMatched(result, "a", .modify)
        XCTAssertEqual(result.matchedRuleIds, ["a"])
    }

    // MARK: - Day bounds

    func testFromDayIsInclusive() {
        let rules = [rule("a", .modify, from: 5)]
        assertMatched(atDay(5, rules), "a", .modify)
        assertMatched(atDay(6, rules), "a", .modify)
        // A nil lower bound is day 1, and so is an explicit 1.
        assertMatched(atDay(1, [rule("n", .modify)]), "n", .modify)
        assertMatched(atDay(1, [rule("o", .modify, from: 1)]), "o", .modify)
    }

    func testOneDayBeforeFromDayDoesNotMatch() {
        let rules = [rule("a", .modify, from: 5)]
        assertNoMatch(atDay(4, rules))
        assertNoMatch(atDay(1, rules))
        assertNoMatch(atDay(1, [rule("b", .modify, from: 2)]))
    }

    func testThroughDayIsInclusive() {
        let rules = [rule("a", .watch, through: 10)]
        assertMatched(atDay(10, rules), "a", .watch)
        assertMatched(atDay(9, rules), "a", .watch)
        // A window of one day matches on that day.
        assertMatched(atDay(7, [rule("b", .watch, from: 7, through: 7)]), "b", .watch)
        assertMatched(atDay(1, [rule("c", .watch, through: 1)]), "c", .watch)
    }

    func testOneDayAfterThroughDayDoesNotMatch() {
        let rules = [rule("a", .watch, through: 10)]
        assertNoMatch(atDay(11, rules))
        assertNoMatch(atDay(8, [rule("b", .watch, from: 7, through: 7)]))
        assertNoMatch(atDay(6, [rule("b", .watch, from: 7, through: 7)]))
        assertNoMatch(atDay(2, [rule("c", .watch, through: 1)]))
    }

    // MARK: - Which rule wins

    func testSeverityOrdersWatchModifySeeProfessional() {
        XCTAssertEqual(NiggleTriage.severity(.watch), 0)
        XCTAssertEqual(NiggleTriage.severity(.modify), 1)
        XCTAssertEqual(NiggleTriage.severity(.seeProfessional), 2)
    }

    func testHigherSeverityWinsWhateverTheOrder() {
        let w = rule("w", .watch), m = rule("m", .modify), p = rule("p", .seeProfessional)
        for order in [[w, m, p], [w, p, m], [m, w, p], [m, p, w], [p, w, m], [p, m, w]] {
            assertMatched(atDay(4, order), "p", .seeProfessional)
        }
        for order in [[w, m], [m, w]] { assertMatched(atDay(4, order), "m", .modify) }
        for order in [[w, p], [p, w]] { assertMatched(atDay(4, order), "p", .seeProfessional) }
        for order in [[m, p], [p, m]] { assertMatched(atDay(4, order), "p", .seeProfessional) }
        // A more serious rule that does not match does not win.
        let late = rule("late", .seeProfessional, from: 30)
        assertMatched(atDay(4, [w, late]), "w", .watch)
        assertMatched(atDay(4, [late, w]), "w", .watch)
    }

    func testEqualSeverityTakesTheEarlierRule() {
        for action in NiggleAction.allCases {
            let x = rule("x", action), y = rule("y", action)
            assertMatched(atDay(2, [x, y]), "x", action)
            assertMatched(atDay(2, [y, x]), "y", action)
        }
        // Among three, with a milder rule first: the earlier of the two most serious.
        let rules = [rule("w", .watch), rule("m1", .modify), rule("m2", .modify)]
        assertMatched(atDay(2, rules), "m1", .modify)
    }

    func testMatchedRuleIdsListsEveryMatchInOwnerOrder() {
        let rules = [
            rule("p", .seeProfessional),
            rule("skip-character", .modify, characters: [.localised]),
            rule("w", .watch),
            rule("skip-day", .seeProfessional, from: 9),
            rule("m", .modify, through: 8),
            rule("skip-trend", .watch, trends: [.easing]),
        ]
        let result = atDay(8, rules)
        XCTAssertEqual(result.matchedRuleIds, ["p", "w", "m"])
        assertMatched(result, "p", .seeProfessional)
        // Owner order, not severity order.
        let reversed = atDay(8, Array(rules.reversed()))
        XCTAssertEqual(reversed.matchedRuleIds, ["m", "w", "p"])
        assertMatched(reversed, "p", .seeProfessional)
    }

    // MARK: - Weakness

    func testWeaknessNilMatchesBoth() {
        let rules = [rule("a", .modify, weakness: nil)]
        assertMatched(atDay(1, rules, complaint(weakness: false)), "a", .modify)
        assertMatched(atDay(1, rules, complaint(weakness: true)), "a", .modify)
    }

    func testWeaknessTrueRequiresWeakness() {
        let rules = [rule("a", .modify, weakness: true)]
        assertMatched(atDay(1, rules, complaint(weakness: true)), "a", .modify)
        assertNoMatch(atDay(1, rules, complaint(weakness: false)))
    }

    func testWeaknessFalseExcludesWeakness() {
        let rules = [rule("a", .modify, weakness: false)]
        assertMatched(atDay(1, rules, complaint(weakness: false)), "a", .modify)
        assertNoMatch(atDay(1, rules, complaint(weakness: true)))
    }

    // MARK: - Updates

    func testLatestUpdateSuppliesTrendAndWeakness() {
        let updates = [
            update(day(fixtureOnset, 5), 1, .easing, weakness: false),
            update(day(fixtureOnset, 2), 1, .worsening, weakness: true),
        ]
        let c = complaint(trend: .unchanged, weakness: false, updates: updates)
        let rules = [
            rule("onset", .seeProfessional, trends: [.unchanged]),
            rule("middle", .seeProfessional, trends: [.worsening]),
            rule("latest", .watch, trends: [.easing]),
        ]
        let result = atDay(10, rules, c)
        XCTAssertEqual(result.currentTrend, .easing)
        XCTAssertFalse(result.currentWeakness)
        XCTAssertEqual(result.stateDay, day(fixtureOnset, 5))
        XCTAssertEqual(result.ignoredUpdates, 0)
        assertMatched(result, "latest", .watch)
        XCTAssertEqual(result.matchedRuleIds, ["latest"])

        // Before the second update is dated, the first one is the latest, and it carries weakness.
        let earlier = atDay(4, rules + [rule("weak", .modify, weakness: true)], c)
        XCTAssertEqual(earlier.currentTrend, .worsening)
        XCTAssertTrue(earlier.currentWeakness)
        XCTAssertEqual(earlier.stateDay, day(fixtureOnset, 2))
        XCTAssertEqual(earlier.ignoredUpdates, 1)
        XCTAssertEqual(earlier.matchedRuleIds, ["middle", "weak"])

        // With no update the complaint's own values and onset day stand.
        let none = atDay(10, rules, complaint(trend: .unchanged, weakness: true))
        XCTAssertEqual(none.currentTrend, .unchanged)
        XCTAssertTrue(none.currentWeakness)
        XCTAssertEqual(none.stateDay, fixtureOnset)
        assertMatched(none, "onset", .seeProfessional)
    }

    func testUpdateOrderDoesNotChangeTheCurrentState() {
        let a = update(day(fixtureOnset, 1), 3, .easing)
        let b = update(day(fixtureOnset, 4), 1, .worsening, weakness: true)
        let c = update(day(fixtureOnset, 3), 9, .unchanged)
        let rules = [rule("w", .seeProfessional, trends: [.worsening], weakness: true)]
        let expected = atDay(9, rules, complaint(updates: [a, b, c]))
        XCTAssertEqual(expected.currentTrend, .worsening)
        XCTAssertTrue(expected.currentWeakness)
        XCTAssertEqual(expected.stateDay, day(fixtureOnset, 4))
        for order in [[a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a]] {
            XCTAssertEqual(atDay(9, rules, complaint(updates: order)), expected)
        }
    }

    func testUpdatesOnTheSameDayUseTheGreaterSequence() {
        let d = day(fixtureOnset, 3)
        let first = update(d, 1, .worsening, weakness: true)
        let second = update(d, 2, .easing, weakness: false)
        for order in [[first, second], [second, first]] {
            let result = atDay(6, [], complaint(updates: order))
            XCTAssertEqual(result.currentTrend, .easing)
            XCTAssertFalse(result.currentWeakness)
            XCTAssertEqual(result.stateDay, d)
        }
        // A later day outranks a greater sequence on an earlier day.
        let laterDay = update(day(fixtureOnset, 4), 0, .unchanged, weakness: true)
        let mixed = atDay(6, [], complaint(updates: [laterDay, second, first]))
        XCTAssertEqual(mixed.currentTrend, .unchanged)
        XCTAssertTrue(mixed.currentWeakness)
        XCTAssertEqual(mixed.stateDay, day(fixtureOnset, 4))
        // Equal day and sequence: the later in input order.
        let tieA = update(d, 5, .worsening), tieB = update(d, 5, .easing)
        XCTAssertEqual(atDay(6, [], complaint(updates: [tieA, tieB])).currentTrend, .easing)
        XCTAssertEqual(atDay(6, [], complaint(updates: [tieB, tieA])).currentTrend, .worsening)
    }

    func testUpdateAfterTodayIsIgnoredAndCounted() {
        let rules = [rule("worse", .seeProfessional, trends: [.worsening]),
                     rule("same", .watch, trends: [.unchanged])]
        // Today is day 6: onset + 5. An update dated tomorrow is not yet known.
        let tomorrow = complaint(updates: [update(day(fixtureOnset, 6), 1, .worsening, weakness: true)])
        let ignored = atDay(6, rules, tomorrow)
        XCTAssertEqual(ignored.ignoredUpdates, 1)
        XCTAssertEqual(ignored.currentTrend, .unchanged)
        XCTAssertFalse(ignored.currentWeakness)
        XCTAssertEqual(ignored.stateDay, fixtureOnset)
        assertMatched(ignored, "same", .watch)
        // The boundary: an update dated today is kept.
        let onToday = complaint(updates: [update(day(fixtureOnset, 5), 1, .worsening, weakness: true)])
        let kept = atDay(6, rules, onToday)
        XCTAssertEqual(kept.ignoredUpdates, 0)
        XCTAssertEqual(kept.currentTrend, .worsening)
        XCTAssertTrue(kept.currentWeakness)
        XCTAssertEqual(kept.stateDay, day(fixtureOnset, 5))
        assertMatched(kept, "worse", .seeProfessional)
        // Each ignored update is counted.
        let two = complaint(updates: [update(day(fixtureOnset, 6), 1, .worsening),
                                      update(day(fixtureOnset, 40), 1, .easing),
                                      update(day(fixtureOnset, 2), 1, .easing)])
        let counted = atDay(6, rules, two)
        XCTAssertEqual(counted.ignoredUpdates, 2)
        XCTAssertEqual(counted.currentTrend, .easing)
        XCTAssertEqual(counted.stateDay, day(fixtureOnset, 2))
    }

    func testUpdateBeforeOnsetIsIgnoredAndCounted() {
        let before = complaint(updates: [update(day(fixtureOnset, -1), 9, .worsening, weakness: true)])
        let ignored = atDay(6, [], before)
        XCTAssertEqual(ignored.ignoredUpdates, 1)
        XCTAssertEqual(ignored.currentTrend, .unchanged)
        XCTAssertFalse(ignored.currentWeakness)
        XCTAssertEqual(ignored.stateDay, fixtureOnset)
        // The boundary: an update dated on the onset day is kept and replaces the onset values.
        let onOnset = complaint(updates: [update(fixtureOnset, 1, .worsening, weakness: true)])
        let kept = atDay(6, [], onOnset)
        XCTAssertEqual(kept.ignoredUpdates, 0)
        XCTAssertEqual(kept.currentTrend, .worsening)
        XCTAssertTrue(kept.currentWeakness)
        XCTAssertEqual(kept.stateDay, fixtureOnset)
    }

    func testUpdateAfterResolvedDayIsIgnoredAndCounted() {
        let resolved = day(fixtureOnset, 9)
        let today = day(fixtureOnset, 30)
        // After the resolved day but not after today: ignored for that reason alone.
        let after = complaint(resolved: resolved, trend: .easing,
                              updates: [update(day(fixtureOnset, 10), 1, .worsening, weakness: true)])
        let ignored = evaluate(after, [], today: today)
        XCTAssertEqual(ignored.status, .resolved)
        XCTAssertEqual(ignored.ignoredUpdates, 1)
        XCTAssertEqual(ignored.currentTrend, .easing)
        XCTAssertFalse(ignored.currentWeakness)
        XCTAssertEqual(ignored.stateDay, fixtureOnset)
        // The boundary: an update on the resolved day is kept.
        let on = complaint(resolved: resolved, trend: .easing,
                           updates: [update(resolved, 1, .worsening, weakness: true)])
        let kept = evaluate(on, [], today: today)
        XCTAssertEqual(kept.status, .resolved)
        XCTAssertEqual(kept.ignoredUpdates, 0)
        XCTAssertEqual(kept.currentTrend, .worsening)
        XCTAssertTrue(kept.currentWeakness)
        XCTAssertEqual(kept.stateDay, resolved)
        // An update after both the resolved day and today is counted once, not twice.
        let both = complaint(resolved: resolved,
                             updates: [update(day(fixtureOnset, 31), 1, .worsening)])
        XCTAssertEqual(evaluate(both, [], today: today).ignoredUpdates, 1)
    }

    func testUpdateWithANonCanonicalDayIsIgnoredAndCounted() {
        let updates = nonCanonicalDays.map { update($0, 99, .worsening, weakness: true) }
        let result = atDay(6, [], complaint(updates: updates))
        XCTAssertEqual(result.status, .noRulesEntered)
        XCTAssertEqual(result.ignoredUpdates, nonCanonicalDays.count)
        XCTAssertEqual(result.currentTrend, .unchanged)
        XCTAssertFalse(result.currentWeakness)
        XCTAssertEqual(result.stateDay, fixtureOnset)
    }

    func testNotRecordedTrendDoesNotMatchARuleNamingTrends() {
        let c = complaint(trend: .notRecorded)
        assertNoMatch(atDay(3, [rule("a", .modify, trends: [.easing, .unchanged, .worsening])], c))
        for trend in [NiggleTrend.easing, .unchanged, .worsening] {
            assertNoMatch(atDay(3, [rule("a", .modify, trends: [trend])], c))
        }
        // A rule naming no trend matches a complaint whose trend was not recorded.
        assertMatched(atDay(3, [rule("b", .modify)], c), "b", .modify)
        // §7.1 step 9 is plain membership: a rule that lists notRecorded itself does match it.
        assertMatched(atDay(3, [rule("c", .modify, trends: [.notRecorded])], c), "c", .modify)
        // An update that records a trend makes the complaint matchable by trend.
        let updated = complaint(trend: .notRecorded,
                                updates: [update(day(fixtureOnset, 1), 1, .worsening)])
        assertMatched(atDay(3, [rule("d", .modify, trends: [.worsening])], updated), "d", .modify)
    }

    // MARK: - Resolved

    func testResolvedReportsDurationAndNoRule() {
        // Rules that would match an open complaint on every day.
        let rules = [rule("w", .watch), rule("p", .seeProfessional, through: 60)]
        let c = complaint(resolved: day(fixtureOnset, 9), trend: .easing, weakness: true)
        for today in [day(fixtureOnset, 9), day(fixtureOnset, 10), day(fixtureOnset, 300)] {
            let result = evaluate(c, rules, today: today)
            XCTAssertEqual(result.status, .resolved)
            XCTAssertNil(result.invalid)
            XCTAssertFalse(result.isOpen)
            // The duration runs to the resolved day, not to today.
            XCTAssertEqual(result.dayCount, 10)
            XCTAssertNil(result.ruleId)
            XCTAssertNil(result.action)
            XCTAssertEqual(result.matchedRuleIds, [])
            XCTAssertNil(result.nextChange)
            XCTAssertEqual(result.currentTrend, .easing)
            XCTAssertTrue(result.currentWeakness)
            XCTAssertEqual(result.stateDay, fixtureOnset)
        }
        // The same complaint, open, is triaged: the difference is the resolved day alone.
        assertMatched(evaluate(complaint(trend: .easing, weakness: true), rules,
                               today: day(fixtureOnset, 10)), "p", .seeProfessional)
        // Resolved with no rules entered is still "resolved".
        XCTAssertEqual(evaluate(c, [], today: day(fixtureOnset, 10)).status, .resolved)
    }

    func testResolvedOnTheOnsetDayIsOneDay() {
        let c = complaint(resolved: fixtureOnset)
        for today in [fixtureOnset, day(fixtureOnset, 1), day(fixtureOnset, 50)] {
            let result = evaluate(c, [rule("w")], today: today)
            XCTAssertEqual(result.status, .resolved)
            XCTAssertEqual(result.dayCount, 1)
        }
        XCTAssertEqual(evaluate(complaint(resolved: day(fixtureOnset, 1)), [],
                                today: day(fixtureOnset, 1)).dayCount, 2)
    }

    // MARK: - Next change

    func testNextChangeIsTheFirstDayTheWinnerDiffers() {
        let rules = [rule("p", .seeProfessional, from: 15), rule("w", .watch),
                     rule("m", .modify, from: 8)]
        let result = atDay(3, rules)
        assertMatched(result, "w", .watch)
        XCTAssertEqual(result.nextChange, next(8, day(fixtureOnset, 7), "m", .modify))
        // The day before the change still reports it; on the day itself the next one is reported.
        XCTAssertEqual(atDay(7, rules).nextChange, next(8, day(fixtureOnset, 7), "m", .modify))
        let onTheDay = atDay(8, rules)
        assertMatched(onTheDay, "m", .modify)
        XCTAssertEqual(onTheDay.nextChange, next(15, day(fixtureOnset, 14), "p", .seeProfessional))
        // From no match to a first match.
        let none = atDay(2, [rule("m", .modify, from: 8)])
        assertNoMatch(none)
        XCTAssertEqual(none.nextChange, next(8, day(fixtureOnset, 7), "m", .modify))
    }

    func testNextChangeWhenAWindowEndsWithNothingAfter() {
        let rules = [rule("w", .watch, through: 10)]
        XCTAssertEqual(atDay(4, rules).nextChange, next(11, day(fixtureOnset, 10), nil, nil))
        // On the window's last day the end is still ahead.
        let last = atDay(10, rules)
        assertMatched(last, "w", .watch)
        XCTAssertEqual(last.nextChange, next(11, day(fixtureOnset, 10), nil, nil))
        // Once the window has ended nothing further changes.
        let after = atDay(11, rules)
        assertNoMatch(after)
        XCTAssertNil(after.nextChange)
        // A window that ends and hands over to a milder open-ended rule.
        let handOver = [rule("p", .seeProfessional, through: 5), rule("w", .watch)]
        XCTAssertEqual(atDay(5, handOver).nextChange, next(6, day(fixtureOnset, 5), "w", .watch))
    }

    func testNextChangeSkipsACandidateThatKeepsTheWinner() {
        // Day 5 is a candidate (rule m starts) but p still wins there; the winner first differs on
        // day 21, when p's window has ended.
        let rules = [rule("p", .seeProfessional, through: 20), rule("m", .modify, from: 5)]
        let result = atDay(2, rules)
        assertMatched(result, "p", .seeProfessional)
        XCTAssertEqual(result.nextChange, next(21, day(fixtureOnset, 20), "m", .modify))
        // Two skipped candidates before the one that counts.
        let more = [rule("p", .seeProfessional, through: 20), rule("m", .modify, from: 5),
                    rule("w", .watch, from: 9, through: 12)]
        XCTAssertEqual(atDay(2, more).nextChange, next(21, day(fixtureOnset, 20), "m", .modify))
        // An equally serious later rule does not displace an earlier one when it starts.
        let equal = [rule("first", .modify), rule("second", .modify, from: 6)]
        XCTAssertNil(atDay(2, equal).nextChange)
    }

    func testNextChangeIsNilWhenNothingWillChange() {
        XCTAssertNil(atDay(3, [rule("w", .watch)]).nextChange)
        XCTAssertNil(atDay(3, [rule("w", .watch, from: 2)]).nextChange)
        // A milder rule starting later never displaces an open-ended more serious winner.
        XCTAssertNil(atDay(3, [rule("p", .seeProfessional), rule("m", .modify, from: 9)]).nextChange)
        // Nothing matches and nothing ever will.
        let never = atDay(12, [rule("w", .watch, through: 10)])
        assertNoMatch(never)
        XCTAssertNil(never.nextChange)
        // The bound that has just passed is not a candidate.
        XCTAssertNil(atDay(5, [rule("m", .modify, from: 5)]).nextChange)
    }

    func testNextChangeIgnoresRulesWhoseOtherConditionsFail() {
        let base = rule("w", .watch)
        let c = complaint(character: .diffuse, trend: .unchanged, weakness: false)
        let failing = [
            rule("p", .seeProfessional, characters: [.localised], from: 10),
            rule("q", .seeProfessional, trends: [.worsening], from: 12),
            rule("r", .seeProfessional, weakness: true, from: 14),
        ]
        for other in failing {
            XCTAssertNil(atDay(3, [base, other], c).nextChange, other.id)
        }
        XCTAssertNil(atDay(3, [base] + failing, c).nextChange)
        // The same three, with conditions the complaint meets, do announce a change.
        let passing = [
            rule("p", .seeProfessional, characters: [.diffuse], from: 10),
            rule("q", .seeProfessional, trends: [.unchanged], from: 12),
            rule("r", .seeProfessional, weakness: false, from: 14),
        ]
        for other in passing {
            XCTAssertEqual(atDay(3, [base, other], c).nextChange,
                           next(other.fromDay!, day(fixtureOnset, other.fromDay! - 1), other.id,
                                .seeProfessional), other.id)
        }
        // A failing rule's window end is not a candidate either.
        let window = rule("s", .seeProfessional, characters: [.localised], through: 6)
        XCTAssertNil(atDay(3, [base, window], c).nextChange)
    }

    func testThroughDayIntMaxDoesNotOverflow() {
        let open = [rule("w", .watch, through: Int.max)]
        XCTAssertTrue(NiggleTriage.rulesAreValid(open))
        let result = atDay(3, open)
        assertMatched(result, "w", .watch)
        XCTAssertNil(result.nextChange)
        // With a real change ahead, the Int.max bound adds no candidate and the real one is found.
        let two = [rule("w", .watch, through: Int.max), rule("m", .modify, from: 9)]
        XCTAssertEqual(atDay(3, two).nextChange, next(9, day(fixtureOnset, 8), "m", .modify))
        // A lower bound of Int.max is a valid rule; its day lies beyond year 9999, so nothing is
        // announced, and computing that must not trap.
        let far = [rule("far", .seeProfessional, from: Int.max, through: Int.max)]
        XCTAssertTrue(NiggleTriage.rulesAreValid(far))
        let never = atDay(3, far)
        assertNoMatch(never)
        XCTAssertNil(never.nextChange)
        let farOpen = atDay(3, [rule("far", .seeProfessional, from: Int.max)])
        assertNoMatch(farOpen)
        XCTAssertNil(farOpen.nextChange)
    }

    func testNextChangeBeyondYear9999IsNil() {
        // Onset 9999-12-01: day 31 is 9999-12-31, the last day there is.
        let c = complaint(onset: "9999-12-01")
        let today = "9999-12-10"
        XCTAssertEqual(evaluate(c, [rule("p", .seeProfessional, from: 31)], today: today).nextChange,
                       next(31, "9999-12-31", "p", .seeProfessional))
        XCTAssertEqual(evaluate(c, [rule("p", .seeProfessional, from: 31)], today: today).dayCount, 10)
        XCTAssertNil(evaluate(c, [rule("p", .seeProfessional, from: 32)], today: today).nextChange)
        XCTAssertNil(evaluate(c, [rule("p", .seeProfessional, from: 400)], today: today).nextChange)
        // A window whose first day after its end is 9999-12-31, and one a day later.
        XCTAssertEqual(evaluate(c, [rule("w", .watch, through: 30)], today: today).nextChange,
                       next(31, "9999-12-31", nil, nil))
        XCTAssertNil(evaluate(c, [rule("w", .watch, through: 31)], today: today).nextChange)
    }

    // MARK: - Invalid input

    func testInvalidTodayOnsetAndResolvedEachReportTheirCause() {
        let rules = [rule("w", .watch)]
        let updates = [update(day(fixtureOnset, 1), 1, .worsening, weakness: true)]
        let c = complaint(trend: .easing, weakness: false, updates: updates)
        for bad in nonCanonicalDays {
            assertInvalid(evaluate(c, rules, today: bad), .today, c)
            let badOnset = complaint(onset: bad, trend: .easing, weakness: true, updates: updates)
            assertInvalid(evaluate(badOnset, rules, today: "2031-03-10"), .onsetDay, badOnset)
            let badResolved = complaint(resolved: bad, trend: .worsening, updates: updates)
            assertInvalid(evaluate(badResolved, rules, today: "2031-03-10"), .resolvedDay, badResolved)
        }
        // Onset after today; the boundary (onset on today) is valid.
        assertInvalid(evaluate(c, rules, today: day(fixtureOnset, -1)), .onsetAfterToday, c)
        XCTAssertEqual(evaluate(c, rules, today: fixtureOnset).status, .matched)
        // Resolved before onset; the boundary (resolved on the onset day) is valid.
        let before = complaint(resolved: day(fixtureOnset, -1), updates: updates)
        assertInvalid(evaluate(before, rules, today: "2031-03-10"), .resolvedBeforeOnset, before)
        XCTAssertEqual(evaluate(complaint(resolved: fixtureOnset), rules, today: "2031-03-10").status,
                       .resolved)
        // Resolved after today; the boundary (resolved today) is valid.
        let after = complaint(resolved: "2031-03-11", updates: updates)
        assertInvalid(evaluate(after, rules, today: "2031-03-10"), .resolvedAfterToday, after)
        XCTAssertEqual(evaluate(complaint(resolved: "2031-03-10"), rules, today: "2031-03-10").status,
                       .resolved)
        XCTAssertEqual(evaluate(complaint(resolved: "2031-03-09"), rules, today: "2031-03-10").status,
                       .resolved)
    }

    func testInvalidOrderIsTodayThenRulesThenComplaint() {
        let badRules = [rule("", .watch)]
        let goodRules = [rule("w", .watch)]
        let badOnset = complaint(onset: "2031-02-30", resolved: "nonsense")
        // Everything wrong at once: today is reported.
        assertInvalid(evaluate(badOnset, badRules, today: "2031-3-10"), .today, badOnset)
        // Today valid: the rules are reported before any fault in the complaint.
        assertInvalid(evaluate(badOnset, badRules, today: "2031-03-10"), .rules, badOnset)
        let futureOnset = complaint(onset: "2031-03-11")
        assertInvalid(evaluate(futureOnset, badRules, today: "2031-03-10"), .rules, futureOnset)
        let resolved = complaint(resolved: day(fixtureOnset, 2))
        assertInvalid(evaluate(resolved, badRules, today: "2031-03-10"), .rules, resolved)
        // Rules valid: the complaint's faults in the order of §7.1 step 3.
        assertInvalid(evaluate(badOnset, goodRules, today: "2031-03-10"), .onsetDay, badOnset)
        let futureAndBadResolved = complaint(onset: "2031-03-11", resolved: "nonsense")
        assertInvalid(evaluate(futureAndBadResolved, goodRules, today: "2031-03-10"),
                      .onsetAfterToday, futureAndBadResolved)
        // Onset after today, resolved before that onset and after today: the onset fault comes first.
        let futureAndEarlyResolved = complaint(onset: "2031-03-15", resolved: "2031-03-12")
        assertInvalid(evaluate(futureAndEarlyResolved, goodRules, today: "2031-03-10"),
                      .onsetAfterToday, futureAndEarlyResolved)
    }

    func testDuplicateOrEmptyRuleIdsAreInvalid() {
        let c = complaint()
        let duplicate = [rule("a", .watch), rule("b", .modify), rule("a", .seeProfessional)]
        XCTAssertFalse(NiggleTriage.rulesAreValid(duplicate))
        assertInvalid(atDay(3, duplicate, c), .rules, c)
        let empty = [rule("a", .watch), rule("", .modify)]
        XCTAssertFalse(NiggleTriage.rulesAreValid(empty))
        assertInvalid(atDay(3, empty, c), .rules, c)
        XCTAssertFalse(NiggleTriage.rulesAreValid([rule("")]))
        // An invalid rule is reported even if it could never match this complaint.
        let unreachable = [rule("a", .watch), rule("a", .watch, characters: [.other], from: 900)]
        assertInvalid(atDay(3, unreachable, c), .rules, c)
        // Distinct non-empty ids are valid, and so is the empty list.
        XCTAssertTrue(NiggleTriage.rulesAreValid([rule("a"), rule("b"), rule("A")]))
        XCTAssertTrue(NiggleTriage.rulesAreValid([]))
        XCTAssertTrue(NiggleTriage.rulesAreValid(fixtureRules))
    }

    func testFromDayBelowOneAndThroughBeforeFromAreInvalid() {
        let c = complaint()
        func valid(from: Int?, through: Int?) -> Bool {
            let rules = [rule("a", .watch, from: from, through: through)]
            let agrees = NiggleTriage.rulesAreValid(rules)
            let status = atDay(3, rules, c).status
            XCTAssertEqual(status == .invalidInput, !agrees, "from \(String(describing: from))")
            if !agrees { assertInvalid(atDay(3, rules, c), .rules, c) }
            return agrees
        }
        // fromDay: 1 is the least valid value.
        XCTAssertTrue(valid(from: 1, through: nil))
        XCTAssertTrue(valid(from: 2, through: nil))
        XCTAssertFalse(valid(from: 0, through: nil))
        XCTAssertFalse(valid(from: -1, through: nil))
        XCTAssertFalse(valid(from: Int.min, through: nil))
        // throughDay against an explicit fromDay: equal is valid, one less is not.
        XCTAssertTrue(valid(from: 5, through: 5))
        XCTAssertTrue(valid(from: 5, through: 6))
        XCTAssertFalse(valid(from: 5, through: 4))
        // throughDay against a nil fromDay, which stands for 1.
        XCTAssertTrue(valid(from: nil, through: 1))
        XCTAssertTrue(valid(from: nil, through: 2))
        XCTAssertFalse(valid(from: nil, through: 0))
        XCTAssertFalse(valid(from: nil, through: -3))
        // An invalid fromDay is not rescued by a throughDay that is at least as large.
        XCTAssertFalse(valid(from: 0, through: 4))
        // One bad rule among good ones invalidates the list.
        XCTAssertFalse(NiggleTriage.rulesAreValid([rule("a"), rule("b", from: 7, through: 6), rule("c")]))
    }

    // MARK: - Fixture

    func testFixtureComplaintsGiveTheExpectedTable() {
        struct Row {
            let name: String
            let complaint: NiggleComplaint
            let today: String
            let n: Int
            let status: NiggleTriageStatus
            let ruleId: String?
            let action: NiggleAction?
            let matched: [String]
            let ignored: Int
            let trend: NiggleTrend
            let stateDay: String
            let next: NiggleTriageNextChange?
        }
        let n1 = complaint(onset: "2031-02-03", resolved: "2031-02-12", character: .diffuse,
                           trend: .easing)
        let n2 = complaint(onset: "2031-03-03", character: .positional, trend: .unchanged,
                           updates: [update("2031-03-22", 1, .worsening)])
        let n3 = complaint(onset: "2031-04-07", character: .localised, trend: .unchanged,
                           weakness: true)
        let n5 = complaint(onset: "2031-05-05", character: .diffuse, trend: .notRecorded)
        let n6 = complaint(onset: "2031-06-02", character: .diffuse, trend: .easing)
        let toC = next(30, "2031-04-01", "r-c", .seeProfessional)
        let rows = [
            Row(name: "N1", complaint: n1, today: "2031-03-01", n: 10, status: .resolved,
                ruleId: nil, action: nil, matched: [], ignored: 0, trend: .easing,
                stateDay: "2031-02-03", next: nil),
            Row(name: "N2a", complaint: n2, today: "2031-03-03", n: 1, status: .noRuleMatches,
                ruleId: nil, action: nil, matched: [], ignored: 1, trend: .unchanged,
                stateDay: "2031-03-03", next: next(5, "2031-03-07", "r-b", .modify)),
            Row(name: "N2b", complaint: n2, today: "2031-03-07", n: 5, status: .matched,
                ruleId: "r-b", action: .modify, matched: ["r-b"], ignored: 1, trend: .unchanged,
                stateDay: "2031-03-03", next: toC),
            Row(name: "N2c", complaint: n2, today: "2031-03-21", n: 19, status: .matched,
                ruleId: "r-b", action: .modify, matched: ["r-b"], ignored: 1, trend: .unchanged,
                stateDay: "2031-03-03", next: toC),
            Row(name: "N2d", complaint: n2, today: "2031-03-22", n: 20, status: .matched,
                ruleId: "r-d", action: .seeProfessional, matched: ["r-b", "r-d"], ignored: 0,
                trend: .worsening, stateDay: "2031-03-22", next: toC),
            Row(name: "N3", complaint: n3, today: "2031-04-07", n: 1, status: .matched,
                ruleId: "r-e", action: .modify, matched: ["r-e"], ignored: 0, trend: .unchanged,
                stateDay: "2031-04-07", next: next(30, "2031-05-06", "r-c", .seeProfessional)),
            Row(name: "N5", complaint: n5, today: "2031-05-14", n: 10, status: .noRuleMatches,
                ruleId: nil, action: nil, matched: [], ignored: 0, trend: .notRecorded,
                stateDay: "2031-05-05", next: next(30, "2031-06-03", "r-c", .seeProfessional)),
            Row(name: "N6a", complaint: n6, today: "2031-06-11", n: 10, status: .matched,
                ruleId: "r-a", action: .watch, matched: ["r-a"], ignored: 0, trend: .easing,
                stateDay: "2031-06-02", next: next(11, "2031-06-12", nil, nil)),
            Row(name: "N6b", complaint: n6, today: "2031-06-12", n: 11, status: .noRuleMatches,
                ruleId: nil, action: nil, matched: [], ignored: 0, trend: .easing,
                stateDay: "2031-06-02", next: next(30, "2031-07-01", "r-c", .seeProfessional)),
        ]
        for row in rows {
            let result = evaluate(row.complaint, fixtureRules, today: row.today)
            XCTAssertEqual(result.status, row.status, row.name)
            XCTAssertNil(result.invalid, row.name)
            XCTAssertEqual(result.isOpen, row.status != .resolved, row.name)
            XCTAssertEqual(result.dayCount, row.n, row.name)
            XCTAssertEqual(result.ruleId, row.ruleId, row.name)
            XCTAssertEqual(result.action, row.action, row.name)
            XCTAssertEqual(result.matchedRuleIds, row.matched, row.name)
            XCTAssertEqual(result.ignoredUpdates, row.ignored, row.name)
            XCTAssertEqual(result.currentTrend, row.trend, row.name)
            XCTAssertEqual(result.currentWeakness, row.complaint.weakness, row.name)
            XCTAssertEqual(result.stateDay, row.stateDay, row.name)
            XCTAssertEqual(result.nextChange, row.next, row.name)
        }
    }

    // MARK: - Determinism and sensitivity

    func testSameInputSameOutput() {
        let c = complaint(character: .positional, trend: .unchanged,
                          updates: [update("2031-03-22", 1, .worsening), update("bad", 2, .easing)])
        for today in ["2031-03-03", "2031-03-07", "2031-03-22", "2031-04-05", "nonsense"] {
            let input = NiggleTriageInput(complaint: c, rules: fixtureRules, today: today)
            let first = NiggleTriage.evaluate(input)
            for _ in 0 ..< 3 { XCTAssertEqual(NiggleTriage.evaluate(input), first) }
            // Interleaving another evaluation leaves no trace.
            _ = evaluate(complaint(character: .localised, weakness: true), [], today: today)
            XCTAssertEqual(NiggleTriage.evaluate(input), first)
        }
    }

    func testChangingEachRuleFieldChangesTheOutcomeItGoverns() {
        let c = complaint(character: .positional, trend: .worsening, weakness: true)
        let base = rule("base", .modify, characters: [.positional], trends: [.worsening],
                        weakness: true, from: 4, through: 9)
        assertMatched(atDay(6, [base], c), "base", .modify)

        var changed = base
        changed.id = "renamed"
        assertMatched(atDay(6, [changed], c), "renamed", .modify)

        changed = base
        changed.action = .seeProfessional
        assertMatched(atDay(6, [changed], c), "base", .seeProfessional)

        changed = base
        changed.characters = [.diffuse]
        assertNoMatch(atDay(6, [changed], c))

        changed = base
        changed.trends = [.easing]
        assertNoMatch(atDay(6, [changed], c))

        changed = base
        changed.weakness = false
        assertNoMatch(atDay(6, [changed], c))

        changed = base
        changed.fromDay = 7
        assertNoMatch(atDay(6, [changed], c))

        changed = base
        changed.throughDay = 5
        assertNoMatch(atDay(6, [changed], c))

        // And each complaint field the rule reads.
        assertNoMatch(atDay(6, [base], complaint(character: .other, trend: .worsening, weakness: true)))
        assertNoMatch(atDay(6, [base], complaint(character: .positional, trend: .easing, weakness: true)))
        assertNoMatch(atDay(6, [base], complaint(character: .positional, trend: .worsening,
                                                 weakness: false)))
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
        mutating func subset<T>(_ all: [T]) -> [T] {
            // One time in three: empty, which means "any".
            if next(3) == 0 { return [] }
            return all.filter { _ in next(2) == 0 }
        }
    }

    func testGeneratedInputsKeepTheTriageInvariants() {
        var generator = Generator(state: 0x6_1166_1E)
        var matchedCases = 0, changeCases = 0
        for index in 0 ..< 300 {
            var rules: [NiggleTriageRule] = []
            for r in 0 ..< generator.next(6) {
                let from: Int? = generator.next(3) == 0 ? nil : 1 + generator.next(40)
                let through: Int? = generator.next(2) == 0 ? nil : (from ?? 1) + generator.next(40)
                let weakness: Bool? = [nil, true, false][generator.next(3)]
                rules.append(rule("g\(r)", NiggleAction.allCases[generator.next(3)],
                                  characters: generator.subset(NiggleCharacter.allCases),
                                  trends: generator.subset(NiggleTrend.allCases),
                                  weakness: weakness, from: from, through: through))
            }
            XCTAssertTrue(NiggleTriage.rulesAreValid(rules), "case \(index)")
            let n = 1 + generator.next(60)
            var updates: [NiggleUpdate] = []
            for u in 0 ..< generator.next(4) {
                updates.append(update(day(fixtureOnset, generator.next(n)), u,
                                      NiggleTrend.allCases[generator.next(4)],
                                      weakness: generator.next(2) == 0))
            }
            let c = complaint(character: NiggleCharacter.allCases[generator.next(4)],
                              trend: NiggleTrend.allCases[generator.next(4)],
                              weakness: generator.next(2) == 0, updates: updates)
            let result = atDay(n, rules, c)
            let label = "case \(index)"

            XCTAssertNil(result.invalid, label)
            XCTAssertTrue(result.isOpen, label)
            XCTAssertEqual(result.dayCount, n, label)
            XCTAssertEqual(result.ignoredUpdates, 0, label)

            // The label, the rule and the matched list stand or fall together.
            let ids = rules.map(\.id)
            XCTAssertEqual(result.status == .matched, result.ruleId != nil, label)
            XCTAssertEqual(result.status == .matched, result.action != nil, label)
            XCTAssertEqual(result.status == .matched, !result.matchedRuleIds.isEmpty, label)
            if rules.isEmpty { XCTAssertEqual(result.status, .noRulesEntered, label) }
            else { XCTAssertNotEqual(result.status, .noRulesEntered, label) }
            XCTAssertEqual(result.matchedRuleIds, ids.filter { result.matchedRuleIds.contains($0) }, label)

            // The winner is the first of the most serious matching rules.
            let matched = rules.filter { result.matchedRuleIds.contains($0.id) }
            if let top = matched.map({ NiggleTriage.severity($0.action) }).max() {
                matchedCases += 1
                let winner = matched.first { NiggleTriage.severity($0.action) == top }
                XCTAssertEqual(result.ruleId, winner?.id, label)
                XCTAssertEqual(result.action, winner?.action, label)
            }

            // Reversing the owner's order changes neither the action nor the set of matches.
            let reversed = atDay(n, Array(rules.reversed()), c)
            XCTAssertEqual(reversed.status, result.status, label)
            XCTAssertEqual(reversed.action, result.action, label)
            XCTAssertEqual(reversed.matchedRuleIds, Array(result.matchedRuleIds.reversed()), label)

            // nextChange is the first later day on which the winner differs, found here by asking
            // the function itself about every later day. Every update is on or before today, so the
            // current state is the same on each of those days. The furthest candidate is day 80.
            var firstChange: NiggleTriageNextChange?
            for k in (n + 1) ... 90 {
                let later = atDay(k, rules, c)
                XCTAssertEqual(later.currentTrend, result.currentTrend, label)
                if later.ruleId != result.ruleId {
                    firstChange = next(k, day(fixtureOnset, k - 1), later.ruleId, later.action)
                    break
                }
            }
            XCTAssertEqual(result.nextChange, firstChange, label)
            if firstChange != nil { changeCases += 1 }
        }
        // The generator must reach both branches for the properties above to mean anything.
        XCTAssertGreaterThan(matchedCases, 50)
        XCTAssertGreaterThan(changeCases, 50)
    }
}
